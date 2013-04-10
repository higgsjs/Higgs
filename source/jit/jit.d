/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2013, Maxime Chevalier-Boisvert. All rights reserved.
*
*  This software is licensed under the following license (Modified BSD
*  License):
*
*  Redistribution and use in source and binary forms, with or without
*  modification, are permitted provided that the following conditions are
*  met:
*   1. Redistributions of source code must retain the above copyright
*      notice, this list of conditions and the following disclaimer.
*   2. Redistributions in binary form must reproduce the above copyright
*      notice, this list of conditions and the following disclaimer in the
*      documentation and/or other materials provided with the distribution.
*   3. The name of the author may not be used to endorse or promote
*      products derived from this software without specific prior written
*      permission.
*
*  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
*  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
*  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
*  NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
*  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
*  NOT LIMITED TO PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
*  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
*  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
*  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
*  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
*****************************************************************************/

module jit.jit;

import std.stdio;
import std.string;
import std.array;
import std.stdint;
import options;
import ir.ir;
import ir.livevars;
import interp.interp;
import interp.layout;
import interp.object;
import interp.string;
import jit.codeblock;
import jit.assembler;
import jit.x86;
import jit.encodings;
import jit.peephole;
import jit.regalloc;

/// Block execution count at which a function should be compiled
const JIT_COMPILE_COUNT = 500;

X86Reg interpReg;
X86Reg wspReg;
X86Reg tspReg;
X86Reg cspReg;
X86Reg[] cargRegs;
X86Reg[] cfpArgRegs;
X86Reg[] scratchRegs;
X86Reg[] allocRegs;

/**
Mapping of the x86 machine registers
*/
static this()
{
    /// R15: interpreter object pointer (C callee-save) 
    interpReg = R15;

    /// R14: word stack pointer (C callee-save)
    wspReg = R14;

    /// R13: type stack pointer (C callee-save)
    tspReg = R13;

    // RSP: C stack pointer (used for C calls only)
    cspReg = RSP;

    /// C argument registers
    cargRegs = [RDI, RSI, RDX, RCX, R8, R9];

    /// C fp argument registers
    cfpArgRegs = [XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7];

    /// RAX: scratch register
    /// RDX: scratch register
    /// RDI: scratch register, first C argument register
    /// RSI: scratch register, second C argument register
    scratchRegs = [RAX, RDX, RDI, RSI];

    /// RCX, RBX, RBP, R8-R12: 8 allocatable registers
    allocRegs = [RCX, RBX, RBP, R8, R9, R10, R11, R12];
}

/**
Compile a function to machine code
*/
void compFun(Interp interp, IRFunction fun)
{
    if (opts.jit_dumpinfo)
    {
        writefln(
            "compiling function %s", 
            fun.getName()
        );
    }


    // Run a live variable analysis on the function
    auto liveSets = compLiveVars(fun);

    // Assign a register mapping to each temporary
    auto regMapping = mapRegs(fun, liveSets);






    // Assembler to write code into
    auto as = new Assembler();

    // Assembler for out of line code (slow paths)
    auto ol = new Assembler();

    // Bailout to interpreter label
    auto bailLabel = new Label("BAILOUT");

    // Work list of blocks to be compiled
    IRBlock[] workList;

    // Map of blocks to labels
    Label[IRBlock] labelMap;

    // Map of blocks to exported entry point labels
    Label[IRBlock] entryMap;
    Label[IRBlock] fastEntryMap;

    /// Get a label for a given basic block
    auto getBlockLabel = delegate Label(IRBlock block)
    {
        // If there is no label for this block
        if (block !in labelMap)
        {
            // Create a label for the block
            auto label = new Label(block.getName().toUpper(), true);
            labelMap[block] = label;

            // Add the block to the work list
            workList ~= block;
        }

        // Return the label for this block
        return labelMap[block];
    };

    /// Get an entry point label for a given basic block
    auto getEntryPoint = delegate Label(IRBlock block)
    {
        if (block in entryMap)
            return entryMap[block];

        // Create an exported label for the entry point
        ol.comment("Entry point for " ~ block.getName());
        auto entryLabel = ol.label("ENTRY_" ~ block.getName().toUpper(), true);
        entryMap[block] = entryLabel;

        // Align SP to a multiple of 16 bytes
        ol.instr(SUB, RSP, 8);

        // Save the callee-save GP registers
        ol.instr(PUSH, RBX);
        ol.instr(PUSH, RBP);
        ol.instr(PUSH, R12);
        ol.instr(PUSH, R13);
        ol.instr(PUSH, R14);
        ol.instr(PUSH, R15);

        // Load a pointer to the interpreter object
        ol.ptr(interpReg, interp);

        // Load the stack pointers into RBX and RBP
        ol.getMember!("Interp", "wsp")(wspReg, interpReg);
        ol.getMember!("Interp", "tsp")(tspReg, interpReg);

        // TODO: get block with context where everything is spilled

        // Jump to the target block
        auto blockLabel = getBlockLabel(block);
        ol.instr(JMP, blockLabel);

        // For the fast entry point, use the block label directly
        fastEntryMap[block] = blockLabel;

        return entryLabel;
    };

    // Create a code generation context
    auto ctx = CodeGenCtx(
        interp,
        fun,
        as, 
        ol, 
        bailLabel,
        getBlockLabel,
        getEntryPoint
    );

    // Create an entry point for the function
    getEntryPoint(fun.entryBlock);

    // Until the work list is empty
    BLOCK_LOOP:
    while (workList.length > 0)
    {
        // Remove a block from the work list
        auto block = workList[$-1];
        workList.popBack();

        if (opts.jit_dumpinfo)
        {
            writefln("compiling block: %s", block.getName());
            //writefln("compiling block: %s", block.toString());
        }

        // If this block was never executed
        if (block.execCount == 0)
        {
            if (opts.jit_dumpinfo)
                writefln("producing stub");
            
            // Insert the label for this block in the out of line code
            ol.addInstr(labelMap[block]);

            // Invalidate the compiled code for this function
            ol.ptr(cargRegs[0], block);
            ol.ptr(scratchRegs[0], &visitStub);
            ol.instr(jit.encodings.CALL, scratchRegs[0]);

            // Bailout to the interpreter and jump to the block
            ol.jump(ctx, block);

            // Don't compile the block
            continue BLOCK_LOOP;
        }

        // If this is a loop header block, generate an entry point
        auto blockName = block.getName();
        if (blockName.startsWith("do_test") ||
            blockName.startsWith("for_test") ||
            blockName.startsWith("forin_test") ||
            blockName.startsWith("while_test"))
        {
            //writefln("generating entry point");
            getEntryPoint(block);
        }

        // Insert the label for this block
        as.addInstr(labelMap[block]);

        // For each instruction of the block
        INSTR_LOOP:
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            auto opcode = instr.opcode;

            as.comment(instr.toString());

            //writefln("instr: %s", instr.toString());

            // If there is a codegen function for this opcode
            if (opcode in codeGenFns)
            {
                // Call the code generation function for the opcode
                codeGenFns[opcode](ctx, instr);
            }
            else
            {
                if (opts.jit_dumpinfo)
                {
                    writefln(
                        "using default for: %s (%s)",
                        instr.toString(),
                        instr.block.fun.getName()
                    );
                }

                // Use the default code generation function
                defaultFn(as, ctx, instr);
            }

            // If we know the instruction will definitely leave 
            // this block, stop the block compilation
            if (opcode.isBranch)
            {
                break INSTR_LOOP;
            }
        }
    }

    //writefln("done compiling blocks");

    // Bailout/exit to interpreter
    ol.comment("Bailout to interpreter");
    ol.addInstr(bailLabel);

    // Store the stack pointers back in the interpreter
    ol.setMember!("Interp", "wsp")(interpReg, wspReg);
    ol.setMember!("Interp", "tsp")(interpReg, tspReg);

    // Restore the callee-save GP registers
    ol.instr(POP, R15);
    ol.instr(POP, R14);
    ol.instr(POP, R13);
    ol.instr(POP, R12);
    ol.instr(POP, RBP);
    ol.instr(POP, RBX);

    // Pop the stack alignment padding
    ol.instr(ADD, RSP, 8);

    // Return to the interpreter
    ol.instr(jit.encodings.RET);

    // Append the out of line code to the rest
    as.comment("Out of line code");
    as.append(ol);

    /*
    // If JIT optimizations are not disabled
    if (!opts.jit_noopts)
    {
        // Perform peephole optimizations on the generated code
        optAsm(as);
    }
    */

    // Assemble the machine code
    auto codeBlock = as.assemble();

    // Store the CodeBlock pointer on the compiled function
    fun.codeBlock = codeBlock;

    // For each block with an exported label
    foreach (block, label; entryMap)
    {
        // Set the entry point function pointer on the block
        auto entryAddr = codeBlock.getExportAddr(label.name);
        block.entryFn = cast(EntryFn)entryAddr;

        // Set the fast entry point on the block
        auto fastLabel = fastEntryMap[block];
        block.jitEntry = codeBlock.getExportAddr(fastLabel.name); 
    }

    if (opts.jit_dumpasm)
    {
        writefln("%s\n", as.toString(true));
    }

    if (opts.jit_dumpinfo)
    {
        writefln("machine code bytes: %s", codeBlock.length);
        writefln("");
    }
}

/**
Visit a stubbed (uncompiled) basic block
*/
extern (C) void visitStub(IRBlock stubBlock)
{
    auto fun = stubBlock.fun;

    if (opts.jit_dumpinfo)
        writefln("invalidating %s", fun.getName());

    // Remove block entry points for this function
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        block.entryFn = null;
        block.jitEntry = null;
    }

    // Invalidate the compiled code for this function
    fun.codeBlock = null;
}

/**
Code generation context
*/
struct CodeGenCtx
{
    /// Interpreter object
    Interp interp;

    /// Function being compiled
    IRFunction fun;

    /// Assembler into which to generate code
    Assembler as;

    /// Assembler for out of line code
    Assembler ol;

    /// Bailout to interpreter label
    Label bailLabel;

    /// Function to get the label for a given block
    Label delegate(IRBlock) getBlockLabel;

    /// Function to generate an entry point for a given block
    Label delegate(IRBlock) getEntryPoint;

    /// Postblit (copy) constructor
    this(this)
    {
    }
}

void comment(Assembler as, string str)
{
    if (!opts.jit_dumpasm)
        return;

    as.addInstr(new Comment(str));
}

/// Load a pointer constant into a register
void ptr(TPtr)(Assembler as, X86Reg destReg, TPtr ptr)
{
    as.instr(MOV, destReg, new X86Imm(cast(void*)ptr));
}

/// Increment a global JIT stat counter variable
void incStatCnt(string varName)(Assembler as)
{
    if (!opts.jit_stats)
        return;

    mixin("auto vSize = " ~ varName ~ ".sizeof;");
    mixin("auto vAddr = &" ~ varName ~ ";");

    as.ptr(RAX, vAddr);

    as.instr(INC, new X86Mem(vSize * 8, RAX));
}

void getField(Assembler as, X86Reg dstReg, X86Reg baseReg, size_t fSize, size_t fOffset)
{
    as.instr(MOV, dstReg, new X86Mem(8*fSize, baseReg, cast(int32_t)fOffset));
}

void setField(Assembler as, X86Reg baseReg, size_t fSize, size_t fOffset, X86Reg srcReg)
{
    as.instr(MOV, new X86Mem(8*fSize, baseReg, cast(int32_t)fOffset), srcReg);
}

void getMember(string className, string fName)(Assembler as, X86Reg dstReg, X86Reg baseReg)
{
    mixin("auto fSize = " ~ className ~ "." ~ fName ~ ".sizeof;");
    mixin("auto fOffset = " ~ className ~ "." ~ fName ~ ".offsetof;");

    return as.getField(dstReg, baseReg, fSize, fOffset);
}

void setMember(string className, string fName)(Assembler as, X86Reg baseReg, X86Reg srcReg)
{
    mixin("auto fSize = " ~ className ~ "." ~ fName ~ ".sizeof;");
    mixin("auto fOffset = " ~ className ~ "." ~ fName ~ ".offsetof;");

    return as.setField(baseReg, fSize, fOffset, srcReg);
}

/// Read from the word stack
void getWord(Assembler as, X86Reg dstReg, LocalIdx idx)
{
    if (dstReg.type == X86Reg.GP)
        as.instr(MOV, dstReg, new X86Mem(dstReg.size, wspReg, 8 * idx));
    else if (dstReg.type == X86Reg.XMM)
        as.instr(MOVSD, dstReg, new X86Mem(64, wspReg, 8 * idx));
    else
        assert (false, "unsupported register type");
}

/// Read from the type stack
void getType(Assembler as, X86Reg dstReg, LocalIdx idx)
{
    as.instr(MOV, dstReg, new X86Mem(8, tspReg, idx));
}

/// Write to the word stack
void setWord(Assembler as, LocalIdx idx, X86Reg srcReg)
{
    if (srcReg.type == X86Reg.GP)
        as.instr(MOV, new X86Mem(64, wspReg, 8 * idx), srcReg);
    else if (srcReg.type == X86Reg.XMM)
        as.instr(MOVSD, new X86Mem(64, wspReg, 8 * idx), srcReg);
    else
        assert (false, "unsupported register type");
}

// Write a constant to the word type
void setWord(Assembler as, LocalIdx idx, int32_t imm)
{
    as.instr(MOV, new X86Mem(64, wspReg, 8 * idx), imm);
}

/// Write to the type stack
void setType(Assembler as, LocalIdx idx, X86Reg srcReg)
{
    as.instr(MOV, new X86Mem(8, tspReg, idx), srcReg);
}

/// Write a constant to the type stack
void setType(Assembler as, LocalIdx idx, Type type)
{
    as.instr(MOV, new X86Mem(8, tspReg, idx), type);
}

void jump(Assembler as, CodeGenCtx ctx, IRBlock target)
{
    auto INTERP_JUMP = new Label("INTERP_JUMP");

    // Get a pointer to the branch target
    as.ptr(scratchRegs[0], target);

    // If a JIT entry point exists, jump to it directly
    as.getMember!("IRBlock", "jitEntry")(scratchRegs[1], scratchRegs[0]);
    as.instr(CMP, scratchRegs[1], 0);
    as.instr(JE, INTERP_JUMP);
    as.instr(JMP, scratchRegs[1]);

    // Make the interpreter jump to the target
    ctx.ol.addInstr(INTERP_JUMP);
    ctx.ol.setMember!("Interp", "target")(interpReg, scratchRegs[0]);
    ctx.ol.instr(JMP, ctx.bailLabel);
}

void jump(Assembler as, CodeGenCtx ctx, X86Reg targetAddr)
{
    assert (targetAddr != RCX);
    
    // Make the interpreter jump to the target
    as.setMember!("Interp", "target")(interpReg, targetAddr);
    as.instr(JMP, ctx.bailLabel);
}

void printUint(Assembler as, X86Reg reg)
{
    as.instr(PUSH, RAX);
    as.instr(PUSH, RCX);
    as.instr(PUSH, RDX);
    as.instr(PUSH, RSI);
    as.instr(PUSH, RDI);
    as.instr(PUSH, R8);
    as.instr(PUSH, R9);
    as.instr(PUSH, R10);
    as.instr(PUSH, R11);
    as.instr(PUSH, R11);

    as.instr(MOV, RDI, reg);
    as.ptr(RAX, &jit.jit.printUint);
    as.instr(jit.encodings.CALL, RAX);

    as.instr(POP, R11);
    as.instr(POP, R11);
    as.instr(POP, R10);
    as.instr(POP, R9);
    as.instr(POP, R8);
    as.instr(POP, RDI);
    as.instr(POP, RSI);
    as.instr(POP, RDX);
    as.instr(POP, RCX);
    as.instr(POP, RAX);
}

/**
Print an unsigned integer value. Callable from the JIT
*/
extern (C) void printUint(uint64_t v)
{
    writefln("%s", v);
}

void gen_set_true(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, TRUE.int8Val);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_set_false(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, FALSE.int8Val);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_set_undef(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, UNDEF.int8Val);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_set_missing(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, MISSING.int8Val);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_set_null(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, NULL.int8Val);
    ctx.as.setType(instr.outSlot, Type.REFPTR);
}

void gen_set_int32(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, instr.args[0].int32Val);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_set_str(ref CodeGenCtx ctx, IRInstr instr)
{
    auto linkIdx = instr.args[1].linkIdx;

    assert (
        linkIdx !is NULL_LINK,
        "link not allocated for set_str"
    );

    ctx.as.getMember!("Interp", "wLinkTable")(RCX, interpReg);
    ctx.as.instr(MOV, RCX, new X86Mem(64, RCX, 8 * linkIdx));

    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.REFPTR);
}

void gen_move(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(RDI, instr.args[0].localIdx);
    ctx.as.getType(SIL, instr.args[0].localIdx);
    ctx.as.setWord(instr.outSlot, RDI);
    ctx.as.setType(instr.outSlot, SIL);
}

void IsTypeOp(Type type)(ref CodeGenCtx ctx, IRInstr instr)
{
    // AL = tsp[a0]
    ctx.as.getType(AL, instr.args[0].localIdx);

    // CMP RAX, Type.FLOAT
    ctx.as.instr(CMP, AL, type);

    ctx.as.instr(MOV, RAX, FALSE.int64Val);
    ctx.as.instr(MOV, RCX, TRUE.int64Val);
    ctx.as.instr(CMOVE, RAX, RCX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

alias IsTypeOp!(Type.CONST) gen_is_const;
alias IsTypeOp!(Type.REFPTR) gen_is_refptr;
alias IsTypeOp!(Type.INT32) gen_is_int32;
alias IsTypeOp!(Type.FLOAT) gen_is_float;

void gen_i32_to_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.instr(CVTSI2SD, XMM0, new X86Mem(32, wspReg, instr.args[0].localIdx * 8));

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_f64_to_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // Cast to int64 and truncate to int32 (to match JS semantics)
    ctx.as.instr(CVTSD2SI, RAX, new X86Mem(64, wspReg, instr.args[0].localIdx * 8));
    ctx.as.instr(MOV, ECX, EAX);

    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_add_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // EAX = wsp[a0]
    // ECX = wsp[a1]
    ctx.as.getWord(EAX, instr.args[0].localIdx);
    ctx.as.getWord(ECX, instr.args[1].localIdx);

    // EAX = add EAX, ECX
    ctx.as.instr(ADD, EAX, ECX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_mul_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // EAX = wsp[o0]
    // ECX = wsp[o1]
    ctx.as.getWord(EAX, instr.args[0].localIdx);
    ctx.as.getWord(ECX, instr.args[1].localIdx);

    // EAX = and EAX, ECX
    ctx.as.instr(IMUL, EAX, ECX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_and_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // EAX = wsp[o0]
    // ECX = wsp[o1]
    ctx.as.getWord(EAX, instr.args[0].localIdx);
    ctx.as.getWord(ECX, instr.args[1].localIdx);

    // EAX = and EAX, ECX
    ctx.as.instr(AND, EAX, ECX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_add_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(ADDSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_sub_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(SUBSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_mul_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(MULSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_div_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(DIVSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

/*
void OvfOp(string op)(ref CodeGenCtx ctx, IRInstr instr)
{
    auto OVF = new Label("OVF");

    ctx.as.getWord(ECX, instr.args[0].localIdx);
    ctx.as.getWord(EDX, instr.args[1].localIdx);

    static if (op == "add")
        ctx.as.instr(ADD, ECX, EDX);
    static if (op == "sub")
        ctx.as.instr(SUB, ECX, EDX);
    static if (op == "mul")
        ctx.as.instr(IMUL, ECX, EDX);

    ctx.as.instr(JO, OVF);

    // Set the output
    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.INT32);

    // If the target block isn't in the block list, jump to it
    if (!ctx.hasNextNode || ctx.nextBlock != instr.target)
        ctx.as.jump(ctx, instr.target);

    // *** The trace will continue at the target block ***

    // Out of line jump to the overflow target
    ctx.ol.addInstr(OVF);
    ctx.ol.jump(ctx, instr.excTarget);
}

alias OvfOp!("add") gen_add_i32_ovf;
alias OvfOp!("sub") gen_sub_i32_ovf;
alias OvfOp!("mul") gen_mul_i32_ovf;
*/

void CmpOp(string type, string op)(ref CodeGenCtx ctx, IRInstr instr)
{
    X86Reg regA;
    X86Reg regB;

    static if (type == "i8")
    {
        regA = CL;
        regB = DL;
    }
    static if (type == "i32")
    {
        regA = ECX;
        regB = EDX;
    }
    static if (type == "i64")
    {
        regA = RCX;
        regB = RDX;
    }

    ctx.as.getWord(regA, instr.args[0].localIdx);
    ctx.as.getWord(regB, instr.args[1].localIdx);

    ctx.as.instr(CMP, regA, regB);

    ctx.as.instr(MOV, RAX, cast(int8_t)FALSE.int64Val);
    ctx.as.instr(MOV, RCX, cast(int8_t)TRUE.int64Val);

    static if (op == "eq")
        ctx.as.instr(CMOVE, RAX, RCX);
    static if (op == "ne")
        ctx.as.instr(CMOVNE, RAX, RCX);
    static if (op == "lt")
        ctx.as.instr(CMOVL, RAX, RCX);
    static if (op == "le")
        ctx.as.instr(CMOVLE, RAX, RCX);
    static if (op == "gt")
        ctx.as.instr(CMOVG, RAX, RCX);
    static if (op == "ge")
        ctx.as.instr(CMOVGE, RAX, RCX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

alias CmpOp!("i8" , "eq") gen_eq_i8;
alias CmpOp!("i32", "lt") gen_lt_i32;
alias CmpOp!("i32", "ge") gen_ge_i32;
alias CmpOp!("i32", "ne") gen_ne_i32;
alias CmpOp!("i8" , "eq") gen_eq_const;
alias CmpOp!("i64", "eq") gen_eq_refptr;
alias CmpOp!("i64", "ne") gen_ne_refptr;

void LoadOp(size_t memSize, Type typeTag)(ref CodeGenCtx ctx, IRInstr instr)
{
    // Pointer
    ctx.as.getWord(RCX, instr.args[0].localIdx);

    // Offset
    ctx.as.getWord(RDX, instr.args[1].localIdx);

    X86Reg dstReg;
    static if (memSize == 8)
        dstReg = AL;
    static if (memSize == 16)
        dstReg = AX;
    static if (memSize == 32)
        dstReg = EAX;
    static if (memSize == 64)
        dstReg = RAX;

    static if (memSize == 8)
        ctx.as.instr(MOV, RAX, 0);
    ctx.as.instr(MOV, dstReg, new X86Mem(memSize, RCX, 0, RDX));

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, typeTag);
}

alias LoadOp!(8 , Type.INT32) gen_load_u8;
//alias LoadOp!(uint16, Type.INT32) gen_load_u16;
alias LoadOp!(32, Type.INT32) gen_load_u32;
alias LoadOp!(64, Type.INT32) gen_load_u64;
alias LoadOp!(64, Type.FLOAT) gen_load_f64;
alias LoadOp!(64, Type.REFPTR) gen_load_refptr;
//alias LoadOp!(rawptr, Type.RAWPTR) gen_load_rawptr;
//alias LoadOp!(IRFunction, Type.FUNPTR) gen_load_funptr;

void gen_jump(ref CodeGenCtx ctx, IRInstr instr)
{
    // Jump to the target block
    auto blockLabel = ctx.getBlockLabel(instr.target);
    ctx.as.instr(JMP, blockLabel);
}

void gen_if_true(ref CodeGenCtx ctx, IRInstr instr)
{
    // Compare wsp[a0] to the true value
    ctx.as.getWord(AL, instr.args[0].localIdx);
    ctx.as.instr(CMP, AL, TRUE.int8Val);

    X86OpPtr jumpOp;
    IRBlock fTarget;
    IRBlock sTarget;

    if (instr.target.execCount > instr.excTarget.execCount)
    {
        fTarget = instr.target;
        sTarget = instr.excTarget;
        jumpOp = JNE;
    }
    else
    {
        fTarget = instr.excTarget;
        sTarget = instr.target;
        jumpOp = JE;
    }

    // Get the fast target label last so the fast target is
    // more likely to get generated first (LIFO stack)
    auto sLabel = ctx.getBlockLabel(sTarget);
    auto fLabel = ctx.getBlockLabel(fTarget);

    ctx.as.instr(jumpOp, sLabel);
    ctx.as.instr(JMP, fLabel);
}

void gen_get_global(ref CodeGenCtx ctx, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[1].int32Val;

    // If no property index is cached, used the interpreter function
    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, instr);
        return;
    }

    auto AFTER_CMP  = new Label("PROP_AFTER_CMP");
    auto AFTER_WORD = new Label("PROP_AFTER_WORD");
    auto AFTER_TYPE = new Label("PROP_AFTER_TYPE");
    auto GET_PROP = new Label("PROP_GET_PROP");
    auto GET_OFS  = new Label("PROP_GET_OFS");

    //
    // Fast path
    //
    ctx.as.addInstr(GET_PROP);

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(R12, interpReg);

    // Compare the object size to the cached size
    ctx.as.getField(EDX, R12, 4, obj_ofs_cap(interp.globalObj));
    ctx.as.instr(CMP, EDX, 0x7FFFFFFF);
    ctx.as.addInstr(AFTER_CMP);
    ctx.as.instr(JNE, GET_OFS);

    // Get the word and type from the object
    ctx.as.instr(MOV, RDI, new X86Mem(64, R12, 0x7FFFFFFF));
    ctx.as.addInstr(AFTER_WORD);
    ctx.as.instr(MOV, SIL, new X86Mem( 8, R12, 0x7FFFFFFF));
    ctx.as.addInstr(AFTER_TYPE);

    ctx.as.setWord(instr.outSlot, RDI);
    ctx.as.setType(instr.outSlot, SIL);

    //
    // Slow path: update the cached offset
    //
    ctx.ol.addInstr(GET_OFS);

    // Update the cached object size
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_CMP, -4), EDX);

    // Get the word offset
    ctx.ol.instr(MOV, RDI, R12);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_word);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_WORD, -4), EAX);

    // Get the type offset
    ctx.ol.instr(MOV, RDI, R12);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_type);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_TYPE, -4), EAX);

    // Jump back to the get prop logic
    ctx.ol.instr(JMP, GET_PROP);
}

void gen_set_global(ref CodeGenCtx ctx, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[2].int32Val;

    // If no property index is cached, used the interpreter function
    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, instr);
        return;
    }

    auto AFTER_CMP  = new Label("PROP_AFTER_CMP");
    auto AFTER_WORD = new Label("PROP_AFTER_WORD");
    auto AFTER_TYPE = new Label("PROP_AFTER_TYPE");
    auto SET_PROP = new Label("PROP_SET_PROP");
    auto GET_OFS  = new Label("PROP_GET_OFS");

    //
    // Fast path
    //
    ctx.as.addInstr(SET_PROP);

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(R12, interpReg);

    // Compare the object size to the cached size
    ctx.as.getField(EDX, R12, 4, obj_ofs_cap(interp.globalObj));
    ctx.as.instr(CMP, EDX, 0x7FFFFFFF);
    ctx.as.addInstr(AFTER_CMP);
    ctx.as.instr(JNE, GET_OFS);

    ctx.as.getWord(RDI, instr.args[1].localIdx);
    ctx.as.getType(SIL, instr.args[1].localIdx);

    // Set the word and type on the object
    ctx.as.instr(MOV, new X86Mem(64, R12, 0x7FFFFFFF), RDI);
    ctx.as.addInstr(AFTER_WORD);
    ctx.as.instr(MOV, new X86Mem( 8, R12, 0x7FFFFFFF), SIL);
    ctx.as.addInstr(AFTER_TYPE);

    //
    // Slow path: update the cached offset
    //
    ctx.ol.addInstr(GET_OFS);

    // Update the cached object size
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_CMP, -4), EDX);

    // Get the word offset
    ctx.ol.instr(MOV, RDI, R12);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_word);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_WORD, -4), EAX);

    // Get the type offset
    ctx.ol.instr(MOV, RDI, R12);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_type);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_TYPE, -4), EAX);

    // Jump back to the get prop logic
    ctx.ol.instr(JMP, SET_PROP);
}

void gen_call(ref CodeGenCtx ctx, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;
    auto numArgs = instr.args.length - 2;

    // Generate an entry point for the call continuation
    ctx.getEntryPoint(instr.target);

    // Call the interpreter call instruction
    //defaultFn(ctx.as, ctx, instr);

    // Find the most called callee function
    uint64_t maxCount = 0;
    IRFunction maxCallee = null;
    foreach (callee, count; ctx.fun.callCounts[instr])
    {
        if (count > maxCount)
        {
            maxCallee = callee;
            maxCount = count;
        }
    }

    // Get the callee function
    auto fun = maxCallee;
    assert (fun.entryBlock !is null);

    // If the argument count doesn't match
    if (numArgs != fun.numParams)
    {
        // Call the interpreter call instruction
        defaultFn(ctx.as, ctx, instr);
        return;
    }

    // Label for the bailout to interpreter cases
    auto bailout = new Label("CALL_BAILOUT");

    auto AFTER_CLOS  = new Label("CALL_AFTER_CLOS");
    auto AFTER_OFS = new Label("CALL_AFTER_OFS");
    auto GET_FPTR = new Label("CALL_GET_FPTR");
    auto GET_OFS = new Label("CALL_GET_OFS");

    //
    // Fast path
    //
    ctx.as.addInstr(GET_FPTR);

    // Get the closure word off the stack
    ctx.as.getWord(RCX, closIdx);

    // Compare the closure pointer to the cached pointer
    ctx.as.instr(MOV, RAX, 0x7FFFFFFFFFFFFFFF);
    ctx.as.addInstr(AFTER_CLOS);
    ctx.as.instr(CMP, RCX, RAX);
    ctx.as.instr(JNE, GET_OFS);

    // Get the function pointer from the closure object
    ctx.as.instr(MOV, RDI, new X86Mem(64, RCX, 0x7FFFFFFF));
    ctx.as.addInstr(AFTER_OFS);

    //
    // Slow path: update the cached function pointer offset (out of line)
    //
    ctx.ol.addInstr(GET_OFS);

    // Update the cached closure poiter
    ctx.ol.instr(MOV, new X86IPRel(64, AFTER_CLOS, -8), RCX);

    // Get the function pointer offset
    ctx.ol.instr(MOV, RDI, RCX);
    ctx.ol.ptr(RAX, &clos_ofs_fptr);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_OFS, -4), EAX);

    // Jump back to the fast path logic
    ctx.ol.instr(JMP, GET_FPTR);

    //
    // Function call logic
    //

    // If this is not the closure we expect, bailout to the interpreter
    ctx.as.ptr(RSI, fun);
    ctx.as.instr(CMP, RDI, RSI);
    ctx.as.instr(JNE, bailout);

    auto numPush = fun.numLocals;
    auto numVars = fun.numLocals - NUM_HIDDEN_ARGS - fun.numParams;

    //writefln("numPush: %s, numVars: %s", numPush, numVars);

    // Push space for the callee arguments and locals
    ctx.as.instr(SUB, wspReg, 8 * numPush);
    ctx.as.instr(SUB, tspReg, numPush);

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        //auto argSlot = instr.args[$-(1+i)].localIdx + (argDiff + i);
        auto argSlot = instr.args[$-(1+i)].localIdx;

        ctx.as.getWord(RDI, argSlot + numPush); 
        ctx.as.getType(SIL, argSlot + numPush);

        auto dstIdx = (numArgs - i - 1) + numVars + NUM_HIDDEN_ARGS;

        ctx.as.setWord(cast(LocalIdx)dstIdx, RDI);
        ctx.as.setType(cast(LocalIdx)dstIdx, SIL);
    }

    // Write the argument count
    ctx.as.setWord(cast(LocalIdx)(numVars + 3), cast(int32_t)numArgs);
    ctx.as.setType(cast(LocalIdx)(numVars + 3), Type.INT32);

    // Copy the "this" argument
    ctx.as.getWord(RDI, thisIdx + numPush);
    ctx.as.getType(SIL, thisIdx + numPush);
    ctx.as.setWord(cast(LocalIdx)(numVars + 2), RDI);
    ctx.as.setType(cast(LocalIdx)(numVars + 2), SIL);

    // Write the closure argument
    ctx.as.setWord(cast(LocalIdx)(numVars + 1), RCX);
    ctx.as.setType(cast(LocalIdx)(numVars + 1), Type.REFPTR);

    // Write the return address (caller instruction)
    ctx.as.ptr(RAX, instr);
    ctx.as.setWord(cast(LocalIdx)(numVars + 0), RAX);
    ctx.as.setType(cast(LocalIdx)(numVars + 0), Type.INSPTR);

    // Jump to the callee entry point
    ctx.as.jump(ctx, fun.entryBlock);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(bailout);

    // Call the interpreter call instruction
    // Fallback to interpreter execution
    defaultFn(ctx.ol, ctx, instr);
}

void gen_ret(ref CodeGenCtx ctx, IRInstr instr)
{
    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.block.fun.raSlot;
    auto argcSlot  = instr.block.fun.argcSlot;
    auto thisSlot  = instr.block.fun.thisSlot;
    auto numParams = instr.block.fun.params.length;
    auto numLocals = instr.block.fun.numLocals;

    // Call the interpreter return instruction
    defaultFn(ctx.as, ctx, instr);




    // TODO: caller guessing?

    /*
    IRInstr callInstr = (ctx.callStack.length > 0)? ctx.callStack[$-1]:null;

    // If the call instruction is unknown or is not a regular call
    if (callInstr is null || callInstr.opcode != &ir.ir.CALL)
    {
        //writefln("interp return");

        // Call the interpreter return instruction
        defaultFn(ctx.as, ctx, instr);
        ctx.endTrace = true;
        return;
    }

    //writefln("optimized return");

    // Get the argument count
    auto argCount = callInstr.args.length - 2;

    // Compute the actual number of extra arguments to pop
    size_t extraArgs = (argCount > numParams)? (argCount - numParams):0;

    // Compute the number of stack slots to pop
    auto numPop = numLocals + extraArgs;

    // If the call instruction has an output slot
    if (callInstr.outSlot != NULL_LOCAL)
    {
        // Get the return value
        ctx.as.getWord(RDI, retSlot);
        ctx.as.getType(SIL, retSlot);
    }

    // Pop all local stack slots and arguments
    ctx.as.instr(ADD, wspReg, numPop * 8);
    ctx.as.instr(ADD, tspReg, numPop);

    // If the call instruction has an output slot
    if (callInstr.outSlot != NULL_LOCAL)
    {
        // Set the return value
        ctx.as.setWord(callInstr.outSlot, RDI);
        ctx.as.setType(callInstr.outSlot, SIL);
    }

    // If the trace stops here, jump to the call continuation
    if (!ctx.hasNextNode)
        ctx.as.jump(ctx, callInstr.target);

    // *** The trace will continue in line at the call continuation block ***
    */
}

void gen_get_global_obj(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getMember!("Interp", "globalObj")(RAX, interpReg);
    
    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.REFPTR);
}

void defaultFn(Assembler as, ref CodeGenCtx ctx, IRInstr instr)
{
    // Get the function corresponding to this instruction
    // alias void function(Interp interp, IRInstr instr) OpFn;
    // RDI: first argument (interp)
    // RSI: second argument (instr)
    auto opFn = instr.opcode.opFn;

    // Move the interpreter pointer into the first argument
    as.instr(MOV, cargRegs[0], interpReg);
    
    // Load a pointer to the instruction in the second argument
    as.ptr(cargRegs[1], instr);

    // Set the interpreter's IP
    // Only necessary if we may branch or allocate
    if (instr.opcode.isBranch || instr.opcode.mayGC)
    {
        as.setMember!("Interp", "ip")(interpReg, cargRegs[1]);
    }

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(interpReg, wspReg);
    as.setMember!("Interp", "tsp")(interpReg, tspReg);

    // Call the op function
    as.ptr(scratchRegs[0], opFn);
    as.instr(jit.encodings.CALL, scratchRegs[0]);

    // If this is a branch instruction
    if (instr.opcode.isBranch == true)
    {
        // Reload the stack pointers, the instruction may have changed them
        as.getMember!("Interp", "wsp")(wspReg, interpReg);
        as.getMember!("Interp", "tsp")(tspReg, interpReg);

        // Bailout to the interpreter
        as.instr(JMP, ctx.bailLabel);

        if (opts.jit_dumpinfo)
            writefln("interpreter bailout");
    }
}

alias void function(ref CodeGenCtx ctx, IRInstr instr) CodeGenFn;

CodeGenFn[Opcode*] codeGenFns;

static this()
{
    codeGenFns[&SET_TRUE]       = &gen_set_true;
    codeGenFns[&SET_FALSE]      = &gen_set_false;
    codeGenFns[&SET_UNDEF]      = &gen_set_undef;
    codeGenFns[&SET_MISSING]    = &gen_set_missing;
    codeGenFns[&SET_NULL]       = &gen_set_null;
    codeGenFns[&SET_INT32]      = &gen_set_int32;
    codeGenFns[&SET_STR]        = &gen_set_str;

    /*
    codeGenFns[&MOVE]           = &gen_move;
    */

    codeGenFns[&IS_CONST]       = &gen_is_const;
    codeGenFns[&IS_REFPTR]      = &gen_is_refptr;
    codeGenFns[&IS_INT32]       = &gen_is_int32;
    codeGenFns[&IS_FLOAT]       = &gen_is_float;

    /*
    codeGenFns[&I32_TO_F64]     = &gen_i32_to_f64;
    codeGenFns[&F64_TO_I32]     = &gen_f64_to_i32;
    */

    codeGenFns[&ADD_I32]        = &gen_add_i32;
    codeGenFns[&MUL_I32]        = &gen_mul_i32;
    codeGenFns[&AND_I32]        = &gen_and_i32;

    /*
    codeGenFns[&ADD_F64]        = &gen_add_f64;
    codeGenFns[&SUB_F64]        = &gen_sub_f64;
    codeGenFns[&MUL_F64]        = &gen_mul_f64;
    codeGenFns[&DIV_F64]        = &gen_div_f64;

    codeGenFns[&ADD_I32_OVF]    = &gen_add_i32_ovf;
    codeGenFns[&SUB_I32_OVF]    = &gen_sub_i32_ovf;
    codeGenFns[&MUL_I32_OVF]    = &gen_mul_i32_ovf;

    codeGenFns[&EQ_I8]          = &gen_eq_i8;
    codeGenFns[&LT_I32]         = &gen_lt_i32;
    codeGenFns[&GE_I32]         = &gen_ge_i32;
    codeGenFns[&NE_I32]         = &gen_ne_i32;
    codeGenFns[&EQ_CONST]       = &gen_eq_const;
    codeGenFns[&EQ_REFPTR]      = &gen_eq_refptr;
    codeGenFns[&NE_REFPTR]      = &gen_ne_refptr;

    codeGenFns[&LOAD_U8]        = &gen_load_u8;
    codeGenFns[&LOAD_U32]       = &gen_load_u32;
    codeGenFns[&LOAD_U64]       = &gen_load_u64;
    codeGenFns[&LOAD_F64]       = &gen_load_f64;
    codeGenFns[&LOAD_REFPTR]    = &gen_load_refptr;
    */

    codeGenFns[&JUMP]           = &gen_jump;

    codeGenFns[&IF_TRUE]        = &gen_if_true;

    codeGenFns[&ir.ir.CALL]     = &gen_call;
    codeGenFns[&ir.ir.RET]      = &gen_ret;

    codeGenFns[&GET_GLOBAL]     = &gen_get_global;
    codeGenFns[&SET_GLOBAL]     = &gen_set_global;

    codeGenFns[&GET_GLOBAL_OBJ] = &gen_get_global_obj;
}

