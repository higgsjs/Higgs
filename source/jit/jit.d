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
import interp.interp;
import interp.layout;
import interp.object;
import interp.string;
import jit.codeblock;
import jit.assembler;
import jit.x86;
import jit.encodings;
import jit.trace;

/**
Compile a machine code trace starting at a given block
*/
extern (C) Trace compTrace(Interp interp, TraceNode traceNode)
{
    writefln("compiling trace in %s", traceNode.block.fun.getName());

    // Create a trace object
    auto trace = new Trace();

    // Assembler to write code into
    auto as = new Assembler();

    // Assembler for out of line code (slow paths)
    auto ol = new Assembler();

    // Label at the trace join point (exported)
    auto joinLabel = new Label("trace_join", true);

    // Label at the end of the block
    auto exitLabel = new Label("trace_exit");

    // Create a code generation context
    auto ctx = CodeGenCtx(
        trace,
        interp, 
        as, 
        ol, 
        joinLabel, 
        exitLabel
    );





    // Assemble the block list
    size_t stackDepth = 0;
    while (traceNode !is null)
    {
        auto block = traceNode.block;

        //writefln("%s\n", block.getName());
        //writefln("%s\n", block.toString());

        ctx.blockList ~= block;

        auto branch = block.lastInstr;

        if (branch.opcode.isCall)
            stackDepth++;

        if (branch.opcode == &ir.ir.RET)
        {
            if (stackDepth == 0)
            {
                writefln("stopping at return");
                break;
            }

            stackDepth--;
        }

        traceNode = traceNode.getMostVisited();
    }







    // Align SP to a multiple of 16 bytes
    as.instr(SUB, RSP, 8);

    // Save the GP registers
    as.instr(PUSH, RBX);
    as.instr(PUSH, RBP);
    as.instr(PUSH, R12);
    as.instr(PUSH, R13);
    as.instr(PUSH, R14);
    as.instr(PUSH, R15);

    // Store a pointer to the interpreter in R15
    as.ptr(R15, interp);

    // Load the stack pointers into RBX and RBP
    as.getMember!("Interp", "wsp")(RBX, R15);
    as.getMember!("Interp", "tsp")(RBP, R15);

    // Join point of the tracelet
    as.comment("Fast trace-trace join point");
    as.addInstr(joinLabel);

    // For each block in the list
    BLOCK_LOOP:
    for (ctx.blockIdx = 0; ctx.blockIdx < ctx.blockList.length; ++ctx.blockIdx)
    {
        auto curBlock = ctx.blockList[ctx.blockIdx];

        //writefln("%s (%s)", curBlock.toString(), curBlock.fun.getName());

        // If the trace jumps back into itself
        if (ctx.blockIdx > 0 && curBlock is ctx.blockList[0])
        {
            writefln("inserting jump to self (%s/%s) *", ctx.blockIdx+1, ctx.blockList.length);
            ctx.as.instr(JMP, ctx.joinLabel);
            break;
        }

        // For each instruction of the block
        INSTR_LOOP:
        for (auto instr = curBlock.firstInstr; instr !is null; instr = instr.next)
        {
            auto opcode = instr.opcode;

            as.comment(instr.toString());

            // If there is a codegen function for this opcode
            if (opcode in codeGenFns)
            {
                // Call the code generation function for the opcode
                codeGenFns[opcode](ctx, instr);
            }
            else
            {
                // Use the default code generation function
                defaultFn(as, ctx, instr);
                //writefln("using default for: %s (%s)", instr.toString(), instr.block.fun.getName());
            }

            // If a code generation function requested the trace
            // compilation be stopped
            if (ctx.endTrace)
            {
                break BLOCK_LOOP;
            }

            // If we know the instruction will definitely leave 
            // this block, stop the block compilation
            if (opcode.isBranch)
            {
                break INSTR_LOOP;
            }
        }
    }

    // Block end, exit of tracelet
    as.comment("Trace exit to interpreter");
    as.addInstr(exitLabel);

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(R15, RBX);
    as.setMember!("Interp", "tsp")(R15, RBP);

    // Restore the GP registers
    as.instr(POP, R15);
    as.instr(POP, R14);
    as.instr(POP, R13);
    as.instr(POP, R12);
    as.instr(POP, RBP);
    as.instr(POP, RBX);

    // Pop the stack alignment padding
    as.instr(ADD, RSP, 8);

    // Return to the interpreter
    as.instr(jit.encodings.RET);

    // Append the out of line code to the rest
    as.comment("Out of line code");
    as.append(ol);

    //writefln("assembling");

    // Assemble the machine code
    auto codeBlock = as.assemble();

    //writefln("assembled");

    if (opts.dumpasm)
    {
        writefln(
            "%s\nblock length: %s bytes\n", 
            as.toString(true),
            codeBlock.length
        );
    }

    writefln("blocks compiled: %s", ctx.blockIdx);

    // Set the code block and code pointers
    trace.codeBlock = codeBlock;
    trace.entryFn = cast(EntryFn)codeBlock.getAddress();
    trace.joinPoint = codeBlock.getExportAddr("trace_join");

    //writefln("trace entry fn: %s", trace.entryFn);

    // Set the trace pointer and join point on the first block
    auto firstBlock = ctx.blockList[0];
    firstBlock.trace = trace;
    firstBlock.joinPoint = trace.joinPoint;

    //writefln("returning trace");

    // Return a pointer to the trace object
    return trace;
}

/**
Code generation context
*/
struct CodeGenCtx
{
    /// Trace object
    Trace trace;

    /// Interpreter object
    Interp interp;

    /// Assembler into which to generate code
    Assembler as;

    /// Assembler for out of line code
    Assembler ol;

    /// Trace join label
    Label joinLabel;

    /// Trace exit label
    Label exitLabel;

    /// List of basic blocks chained in this trace
    IRBlock[] blockList;

    /// Current block index in the block list
    size_t blockIdx = 0;

    /// Array of call instructions on the stack
    IRInstr[] callStack;

    /// Flag to end the trace compilation
    bool endTrace = false;
}

void comment(Assembler as, string str)
{
    if (!opts.dumpasm)
        return;

    as.addInstr(new Comment(str));
}

void ptr(TPtr)(Assembler as, X86Reg destReg, TPtr ptr)
{
    as.instr(MOV, destReg, new X86Imm(cast(void*)ptr));
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
        as.instr(MOV, dstReg, new X86Mem(dstReg.size, RBX, 8 * idx));
    else if (dstReg.type == X86Reg.XMM)
        as.instr(MOVSD, dstReg, new X86Mem(64, RBX, 8 * idx));
    else
        assert (false, "unsupported register type");
}

/// Read from the type stack
void getType(Assembler as, X86Reg dstReg, LocalIdx idx)
{
    as.instr(MOV, dstReg, new X86Mem(8, RBP, idx));
}

/// Write to the word stack
void setWord(Assembler as, LocalIdx idx, X86Reg srcReg)
{
    if (srcReg.type == X86Reg.GP)
        as.instr(MOV, new X86Mem(64, RBX, 8 * idx), srcReg);
    else if (srcReg.type == X86Reg.XMM)
        as.instr(MOVSD, new X86Mem(64, RBX, 8 * idx), srcReg);
    else
        assert (false, "unsupported register type");
}

// Write a constant to the word type
void setWord(Assembler as, LocalIdx idx, int32_t imm)
{
    as.instr(MOV, new X86Mem(64, RBX, 8 * idx), imm);
}

/// Write to the type stack
void setType(Assembler as, LocalIdx idx, X86Reg srcReg)
{
    as.instr(MOV, new X86Mem(8, RBP, idx), srcReg);
}

/// Write a constant to the type stack
void setType(Assembler as, LocalIdx idx, Type type)
{
    as.instr(MOV, new X86Mem(8, RBP, idx), type);
}

void jump(Assembler as, CodeGenCtx ctx, IRBlock target)
{
    auto interpJump = new Label("interp_jump");

    // TODO: directly patch a jump to the trace join point if found
    // mov rax, ptr
    // mov [rip - k], rax

    // Get a pointer to the branch target
    as.ptr(RAX, target);

    // If there is a trace join point, jump to it directly
    as.getMember!("IRBlock", "joinPoint")(RCX, RAX);
    as.instr(CMP, RCX, 0);
    as.instr(JE, interpJump);
    as.instr(JMP, RCX);
    
    // Make the interpreter jump to the target
    as.addInstr(interpJump);
    as.setMember!("Interp", "target")(R15, RAX);
    as.instr(JMP, ctx.exitLabel);
}

void jump(Assembler as, CodeGenCtx ctx, X86Reg targetAddr)
{
    assert (targetAddr != RCX);

    auto interpJump = new Label("interp_jump");

    // If there is a trace join point, jump to it directly
    as.getMember!("IRBlock", "joinPoint")(RCX, targetAddr);
    as.instr(CMP, RCX, 0);
    as.instr(JE, interpJump);
    as.instr(JMP, RCX);
    
    // Make the interpreter jump to the target
    as.addInstr(interpJump);
    as.setMember!("Interp", "target")(R15, targetAddr);
    as.instr(JMP, ctx.exitLabel);
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

    ctx.as.getMember!("Interp", "wLinkTable")(RCX, R15);
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
    ctx.as.instr(CVTSI2SD, XMM0, new X86Mem(32, RBX, instr.args[0].localIdx * 8));

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_f64_to_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // Cast to int64 and truncate to int32 (to match JS semantics)
    ctx.as.instr(CVTSD2SI, RAX, new X86Mem(64, RBX, instr.args[0].localIdx * 8));
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

void OvfOp(string op)(ref CodeGenCtx ctx, IRInstr instr)
{
    auto ovf = new Label("ovf");

    ctx.as.getWord(ECX, instr.args[0].localIdx);
    ctx.as.getWord(EDX, instr.args[1].localIdx);

    static if (op == "add")
        ctx.as.instr(ADD, ECX, EDX);
    static if (op == "mul")
        ctx.as.instr(IMUL, ECX, EDX);

    ctx.as.instr(JO, ovf);

    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.INT32);

    // Add the normal target to the block list if it isn't there already
    if (ctx.blockIdx + 1 >= ctx.blockList.length)
        ctx.blockList ~= instr.target;

    //ctx.as.jump(ctx, instr.target);

    // Out of line jump to the overflow target
    ctx.ol.addInstr(ovf);
    ctx.ol.jump(ctx, instr.excTarget);
}

alias OvfOp!("add") gen_add_i32_ovf;
alias OvfOp!("mul") gen_mul_i32_ovf;

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

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

alias CmpOp!("i32", "lt") gen_lt_i32;

alias CmpOp!("i64", "eq") gen_eq_refptr;
alias CmpOp!("i64", "ne") gen_ne_refptr;

alias CmpOp!("i8", "eq") gen_eq_const;

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

    ctx.as.instr(MOV, dstReg, new X86Mem(memSize, RCX, 0, RDX));

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, typeTag);
}

//alias LoadOp!(uint8, Type.INT32) op_load_u8;
//alias LoadOp!(uint16, Type.INT32) op_load_u16;
alias LoadOp!(32, Type.INT32) gen_load_u32;
//alias LoadOp!(uint64, Type.INT32) op_load_u64;
alias LoadOp!(64, Type.FLOAT) gen_load_f64;
alias LoadOp!(64, Type.REFPTR) gen_load_refptr;
//alias LoadOp!(rawptr, Type.RAWPTR) op_load_rawptr;
//alias LoadOp!(IRFunction, Type.FUNPTR) op_load_funptr;

void gen_jump(ref CodeGenCtx ctx, IRInstr instr)
{
    // Add the jump target to the block list if it isn't there already
    if (ctx.blockIdx + 1 >= ctx.blockList.length)
        ctx.blockList ~= instr.target;

    //ctx.as.jump(ctx, instr.target);
}

void gen_if_true(ref CodeGenCtx ctx, IRInstr instr)
{
    auto ifTrue = new Label("if_true");
    auto ifFalse = new Label("if_false");

    // AL = wsp[a0]
    ctx.as.getWord(AL, instr.args[0].localIdx);
    ctx.as.instr(CMP, AL, TRUE.int8Val);
  


    // TODO: side-exit, sub-trace when count exceeded



    // If we already determined a likely branch target
    if (ctx.blockIdx + 1 < ctx.blockList.length)
    {
        auto inTarget = ctx.blockList[ctx.blockIdx + 1];

        if (inTarget == instr.target)
        {
            // If false, branch out of line
            ctx.as.instr(JNE, ifFalse);

            // The false branch is out of line
            ctx.ol.addInstr(ifFalse);
            ctx.ol.jump(ctx, instr.excTarget);
        }
        else
        {
            // If true, branch out of line
            ctx.as.instr(JE, ifTrue);

            // The true branch is out of line
            ctx.ol.addInstr(ifTrue);
            ctx.ol.jump(ctx, instr.target);
        }

        return;
    }





    // If false, jump
    ctx.as.instr(JNE, ifFalse);

    ctx.as.addInstr(ifTrue);
    ctx.as.jump(ctx, instr.target);

    ctx.as.addInstr(ifFalse);
    ctx.as.jump(ctx, instr.excTarget);







    /*
    auto extTrue = new Label("ext_true");
    auto extFalse = new Label("ext_false");

    auto jumpTrue = new Label("jump_true");
    auto jumpFalse = new Label("jump_false");

    // True/false counter operands
    auto ctrOpndT = new X86Mem(64, RDX, Trace.counters.offsetof);
    auto ctrOpndF = new X86Mem(64, RDX, Trace.counters.offsetof + 8);

    // Set the trace pointer in RDX
    ctx.as.ptr(RDX, ctx.trace);

    // If false, jump to the false label
    ctx.as.instr(JNE, ifFalse);

    //
    // If true
    //
    ctx.as.instr(INC, ctrOpndT);
    ctx.as.instr(CMP, ctrOpndT, BRANCH_EXTEND_COUNT);
    ctx.as.instr(JE, extTrue);

    ctx.as.addInstr(jumpTrue);
    ctx.as.jump(ctx, instr.target);

    //
    // If false
    //
    ctx.as.addInstr(ifFalse);

    ctx.as.instr(INC, ctrOpndF);
    ctx.as.instr(CMP, ctrOpndF, BRANCH_EXTEND_COUNT);
    ctx.as.instr(JE, extFalse);

    ctx.as.addInstr(jumpFalse);
    ctx.as.jump(ctx, instr.excTarget);

    //
    // Extend the true branch (out of line)
    //
    ctx.ol.addInstr(extTrue);

    ctx.as.instr(CMP, ctrOpndF, BRANCH_EXTEND_COUNT / BRANCH_EXTEND_RATIO);
    ctx.as.instr(JG, jumpTrue);

    ctx.ol.instr(MOV, RDI, R15);
    ctx.ol.ptr(RSI, instr.target);
    ctx.ol.ptr(RAX, &compTrace);
    ctx.ol.instr(jit.encodings.CALL, RAX);

    ctx.ol.instr(JMP, jumpTrue);

    //
    // Extend the false branch (out of line)
    //
    ctx.ol.addInstr(extFalse);

    ctx.as.instr(CMP, ctrOpndT, BRANCH_EXTEND_COUNT / BRANCH_EXTEND_RATIO);
    ctx.as.instr(JG, jumpFalse);

    ctx.ol.instr(MOV, RDI, R15);
    ctx.ol.ptr(RSI, instr.excTarget);
    ctx.ol.ptr(RAX, &compTrace);
    ctx.ol.instr(jit.encodings.CALL, RAX);

    ctx.ol.instr(JMP, jumpFalse);
    */


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
    ctx.as.getMember!("Interp", "globalObj")(R12, R15);

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
    ctx.as.getMember!("Interp", "globalObj")(R12, R15);

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
    // Label for the bailout to interpreter cases
    auto bailout = new Label("call_bailout");

    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;
    auto numArgs = instr.args.length - 2;

    // Try to find the function we are calling
    refptr closPtr = null;    
    for (auto curInstr = instr.prev; curInstr !is null; curInstr = curInstr.prev)
    {
        // If we are calling a global function
        if (curInstr.outSlot == closIdx && curInstr.opcode == &GET_GLOBAL)
        {
            auto propStr = getString(ctx.interp, curInstr.args[0].stringVal);

            // Lookup the global function
            ValuePair val = getProp(
                ctx.interp,
                ctx.interp.globalObj,
                propStr
            );

            if (val.type == Type.REFPTR && valIsLayout(val.word, LAYOUT_CLOS))
                closPtr = val.word.ptrVal;

            break;
        }
    }

    // If the global closure was not found
    if (closPtr is null)
    {
        // Call the interpreter call instruction
        defaultFn(ctx.as, ctx, instr);
        ctx.endTrace = true;
        return;
    }

    // Get a pointer to the IR function
    auto fun = cast(IRFunction)clos_get_fptr(closPtr);

    // If the function is not compiled or the argument count doesn't match
    if (fun.entryBlock is null || numArgs != fun.numParams)
    {
        // Call the interpreter call instruction
        defaultFn(ctx.as, ctx, instr);
        ctx.endTrace = true;
        return;
    }

    //writefln("%s\n  %s %s %s", instr.block.toString(), fun.getName(), fun.numParams, numArgs);

    // Get the closure word
    ctx.as.getWord(RCX, closIdx);

    // If this is not the closure we expect, bailout to the interpreter
    ctx.as.ptr(RAX, closPtr);
    ctx.as.instr(CMP, RAX, RCX);
    ctx.as.instr(JNE, bailout);

    auto numPush = fun.numLocals;
    auto numVars = fun.numLocals - NUM_HIDDEN_ARGS - fun.numParams;

    //writefln("numPush: %s, numVars: %s", numPush, numVars);

    // Push space for the callee arguments and locals
    ctx.as.instr(SUB, RBX, 8 * numPush);
    ctx.as.instr(SUB, RBP, numPush);

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto argSlot = instr.args[$-(1+i)].localIdx /*+ (argDiff + i)*/;

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

    // TODO: evaluate when this is acceptable
    // Add the jump target to the block list if it isn't there already
    if (ctx.blockIdx + 1 >= ctx.blockList.length)
        ctx.blockList ~= fun.entryBlock;

    // Add the call instruction to the pseudo call stack
    ctx.callStack ~= instr;

    // Jump to the function entry
    //ctx.as.ptr(RAX, fun.entryBlock);
    //ctx.as.jump(ctx, RAX);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(bailout);

    // Call the interpreter call instruction
    // Fallback to interpreter execution
    defaultFn(ctx.ol, ctx, instr);

    // Exit the trace
    ctx.ol.instr(JMP, ctx.exitLabel);
}

void gen_ret(ref CodeGenCtx ctx, IRInstr instr)
{
    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.block.fun.raSlot;
    auto argcSlot  = instr.block.fun.argcSlot;
    auto thisSlot  = instr.block.fun.thisSlot;
    auto numParams = instr.block.fun.params.length;
    auto numLocals = instr.block.fun.numLocals;

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
    ctx.as.instr(ADD, RBX, numPop * 8);
    ctx.as.instr(ADD, RBP, numPop);

    // If the call instruction has an output slot
    if (callInstr.outSlot != NULL_LOCAL)
    {
        // Set the return value
        ctx.as.setWord(callInstr.outSlot, RDI);
        ctx.as.setType(callInstr.outSlot, SIL);
    }

    // Continue code generation in the call continuation
    if (ctx.blockIdx + 1 >= ctx.blockList.length)
        ctx.blockList ~= callInstr.target;

    // Remove this call instruction from the pseudo call stack
    ctx.callStack = ctx.callStack[0..$-1];
    

    /*
    // Label for returns from a new instruction
    auto retFromNew = new Label("ret_new");

    // Label for the end of the return logic
    auto retDone = new Label("ret_done");

    // Label for the stack locals popping
    auto popLocals = new Label("ret_pop");

    // Get the return value
    // RDI = wRet
    // SIL = tRet
    ctx.as.getWord(RDI, retSlot);
    ctx.as.getType(SIL, retSlot);

    // RAX = calling instruction
    ctx.as.getWord(RAX, raSlot);

    // RCX = opcode of the calling instruction
    ctx.as.getMember!("IRInstr", "opcode")(RCX, RAX);

    // If opcode == &CALL_NEW, jump to newRet
    ctx.as.ptr(RDX, &CALL_NEW);
    ctx.as.instr(CMP, RCX, RDX);
    ctx.as.instr(JE, retFromNew);

    // Pop the stack locals
    ctx.as.addInstr(popLocals);

    // EDX = number of stack slots to pop
    ctx.as.getWord(EDX, argcSlot);
    ctx.as.instr(SUB, EDX, numParams);
    ctx.as.instr(MOV, ECX, 0);
    ctx.as.instr(CMP, EDX, 0);
    ctx.as.instr(CMOVL, EDX, ECX);
    ctx.as.instr(ADD, EDX, numLocals);

    // Pop all local stack slots and arguments
    ctx.as.instr(ADD, RBP, RDX);
    ctx.as.instr(SHL, RDX, 3);
    ctx.as.instr(ADD, RBX, RDX);

    // ECX = output slot of the calling instruction
    ctx.as.getMember!("IRInstr", "outSlot")(ECX, RAX);

    // If the call instruction has no output slot, we are done
    ctx.as.instr(MOV, EDX, NULL_LOCAL);
    ctx.as.instr(CMP, ECX, EDX);
    ctx.as.instr(JE, retDone);

    // Set the return value
    ctx.as.instr(MOV, X86Opnd( 8, RBP, 0, RCX, 1), SIL);
    ctx.as.instr(MOV, X86Opnd(64, RBX, 0, RCX, 8), RDI);

    // Return done
    ctx.as.addInstr(retDone);

    if (ctx.callStack.length > 0)
    {
        auto callInstr = ctx.callStack[$-1];

        //writefln("returning to %s", callInstr.block.fun.getName());
        //writefln("returning to %s", callInstr.toString());

        if (ctx.blockIdx + 1 >= ctx.trace.blockList.length)
            ctx.trace.blockList ~= callInstr.target;

        ctx.callStack = ctx.callStack[0..$-1];
    }
    else
    {
        //writefln("no return target");

        // RCX = call continuation target
        ctx.as.getMember!("IRInstr", "target")(RDX, RAX);

        // Jump to the call continuation
        ctx.as.jump(ctx, RDX);
    }

    // Return from new case
    ctx.ol.addInstr(retFromNew);

    // If the return value is not undefined, return that value
    ctx.ol.instr(CMP, SIL, Type.CONST);
    ctx.ol.instr(JNE, popLocals);
    ctx.ol.instr(CMP, DIL, cast(int8_t)UNDEF.int32Val);
    ctx.ol.instr(JNE, popLocals);

    // Use the this value as the return value
    ctx.ol.getWord(RDI, thisSlot);
    ctx.ol.getType(SIL, thisSlot);
    ctx.ol.instr(JMP, popLocals);
    */
}

void gen_get_global_obj(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getMember!("Interp", "globalObj")(RAX, R15);
    
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

    // Move the interpreter pointer into RDI
    as.instr(MOV, RDI, R15);
    
    // Load a pointer to the instruction in RSI
    as.ptr(RSI, instr);

    // Set the interpreter's IP
    // Only necessary if we may branch or allocate
    if (instr.opcode.isBranch || instr.opcode.mayGC)
    {
        as.setMember!("Interp", "ip")(RDI, RSI);
    }

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(R15, RBX);
    as.setMember!("Interp", "tsp")(R15, RBP);

    // Call the op function
    as.ptr(RAX, opFn);
    as.instr(jit.encodings.CALL, RAX);

    // Load the stack pointers into RBX and RBP
    // if the instruction may have changed them
    if (instr.opcode.isBranch == true)
    {
        as.getMember!("Interp", "wsp")(RBX, R15);
        as.getMember!("Interp", "tsp")(RBP, R15);
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

    codeGenFns[&MOVE]           = &gen_move;

    codeGenFns[&IS_CONST]       = &gen_is_const;
    codeGenFns[&IS_REFPTR]      = &gen_is_refptr;
    codeGenFns[&IS_INT32]       = &gen_is_int32;
    codeGenFns[&IS_FLOAT]       = &gen_is_float;

    codeGenFns[&I32_TO_F64]     = &gen_i32_to_f64;
    codeGenFns[&F64_TO_I32]     = &gen_f64_to_i32;

    codeGenFns[&ADD_I32]        = &gen_add_i32;
    codeGenFns[&MUL_I32]        = &gen_mul_i32;
    codeGenFns[&AND_I32]        = &gen_and_i32;

    codeGenFns[&ADD_F64]        = &gen_add_f64;
    codeGenFns[&SUB_F64]        = &gen_sub_f64;
    codeGenFns[&MUL_F64]        = &gen_mul_f64;
    codeGenFns[&DIV_F64]        = &gen_div_f64;

    codeGenFns[&ADD_I32_OVF]    = &gen_add_i32_ovf;
    codeGenFns[&MUL_I32_OVF]    = &gen_mul_i32_ovf;

    codeGenFns[&EQ_CONST]       = &gen_eq_const;
    codeGenFns[&EQ_REFPTR]      = &gen_eq_refptr;
    codeGenFns[&NE_REFPTR]      = &gen_ne_refptr;
    codeGenFns[&LT_I32]         = &gen_lt_i32;

    codeGenFns[&LOAD_U32]       = &gen_load_u32;
    codeGenFns[&LOAD_F64]       = &gen_load_f64;
    codeGenFns[&LOAD_REFPTR]    = &gen_load_refptr;

    codeGenFns[&JUMP]           = &gen_jump;

    codeGenFns[&IF_TRUE]        = &gen_if_true;

    codeGenFns[&ir.ir.CALL]     = &gen_call;
    codeGenFns[&ir.ir.RET]      = &gen_ret;

    codeGenFns[&GET_GLOBAL]     = &gen_get_global;
    codeGenFns[&SET_GLOBAL]     = &gen_set_global;

    codeGenFns[&GET_GLOBAL_OBJ] = &gen_get_global_obj;
}

