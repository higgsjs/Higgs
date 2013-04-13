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
import std.conv;
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
const JIT_COMPILE_COUNT = 1000;

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

    // Work list of block versions to be compiled
    BlockVersion[] workList;

    // Map of blocks to lists of available versions
    BlockVersion[][IRBlock] versionMap;

    // Map of blocks to exported entry point labels
    Label[IRBlock] entryMap;
    Label[IRBlock] fastEntryMap;

    /// Get a label for a given basic block
    auto getBlockLabel = delegate Label(IRBlock block, CodeGenState state)
    {
        // Get the list of versions for this block
        auto versions = versionMap.get(block, []);

        // For each available version of this block
        foreach (ver; versions)
        {
            // If the state matches, return the label for this version
            if (ver.state == state)
                return ver.label;
        }

        // Create a label for this version of the block
        auto label = new Label(block.getName().toUpper());

        // Create a new block version object
        BlockVersion ver = { block, new CodeGenState(state), label };

        // Add the new version to the list for this block
        versionMap[block] ~= ver;

        //writefln("%s num versions: %s", block.getName(), versionMap[block].length);

        // Queue the new version to be compiled
        workList ~= ver;

        // Return the label for this version
        return label;
    };

    /// Get an entry point label for a given basic block
    auto getEntryPoint = delegate Label(IRBlock block)
    {
        // If there is already an entry label for this block, return it
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

        // Request a version of the block that accepts the
        // default state where all locals are on the stack
        auto blockLabel = getBlockLabel(block, new CodeGenState(fun.numLocals));

        // Jump to the target block
        ol.instr(JMP, blockLabel);

        // For the fast entry point, use the block label directly
        blockLabel.exported = true;
        fastEntryMap[block] = blockLabel;

        return entryLabel;
    };

    // Create a code generation context
    auto ctx = new CodeGenCtx(
        interp,
        fun,
        as, 
        ol, 
        bailLabel,
        regMapping,
        getBlockLabel,
        getEntryPoint
    );

    // Create an entry point for the function
    getEntryPoint(fun.entryBlock);

    // Until the work list is empty
    BLOCK_LOOP:
    while (workList.length > 0)
    {
        // Remove a block version from the work list
        auto ver = workList[$-1];
        workList.popBack();
        auto block = ver.block;
        auto label = ver.label;

        // Create a copy of the state to avoid corrupting the block entry state
        auto state = new CodeGenState(ver.state);

        if (opts.jit_dumpinfo)
        {
            writefln("compiling block: %s", block.getName());
            //writefln("compiling block: %s", block.toString());
            //writeln(state);
        }

        // If this block was never executed
        if (block.execCount == 0)
        {
            if (opts.jit_dumpinfo)
                writefln("producing stub");
            
            // Insert the label for this block in the out of line code
            ol.comment("Block stub for " ~ block.getName());
            ol.addInstr(label);

            // Spill the registers
            state.spillRegs(ol);

            // Invalidate the compiled code for this function
            ol.ptr(cargRegs[0], block);
            ol.ptr(scrRegs64[0], &visitStub);
            ol.instr(jit.encodings.CALL, scrRegs64[0]);

            // Bailout to the interpreter and jump to the block
            ol.ptr(scrRegs64[0], block);
            ol.setMember!("Interp", "target")(interpReg, scrRegs64[0]);
            ol.instr(JMP, bailLabel);

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
        as.addInstr(label);

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
                codeGenFns[opcode](ctx, state, instr);
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
                defaultFn(as, ctx, state, instr);
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

alias uint8_t RAFlags;
const RAFlags RA_STACK = (1 << 7);
const RAFlags RA_GPREG = (1 << 6);
const RAFlags RA_REG_MASK = (0x0F);

/**
Code generation state
*/
class CodeGenState
{
    /// Register allocation state (per-local flags)
    RAFlags[] allocState;

    /// Map of general-purpose registers to locals
    /// This is NULL_LOCAL if a register is free
    LocalIdx[] gpRegMap;

    /// TODO: type flags
    // Implement only once versioning/regalloc working

    /// Constructor for a default/entry code generation state
    this(size_t numLocals)
    {
        // All values are initially on the stack
        allocState.length = numLocals;
        for (size_t i = 0; i < allocState.length; ++i)
            allocState[i] = RA_STACK;

        // All registers are initially free
        gpRegMap.length = 16;
        for (size_t i  = 0; i < gpRegMap.length; ++i)
            gpRegMap[i] = NULL_LOCAL;
    }

    /// Copy constructor
    this(CodeGenState that)
    {
        this.allocState = that.allocState.dup;
        this.gpRegMap = that.gpRegMap.dup;
    }

    override string toString()
    {
        auto output = "";

        foreach (regNo, localIdx; gpRegMap)
        {
            if (localIdx is NULL_LOCAL)
                continue;

            auto reg = new X86Reg(X86Reg.GP, cast(uint8_t)regNo, 64);

            output ~= reg.toString() ~ " => $" ~ to!string(localIdx);
        }

        return output;
    }

    /// Equality comparison operator
    override bool opEquals(Object o)
    {
        auto that = cast(CodeGenState)o;
        assert (that !is null);

        if (this.allocState != that.allocState)
            return false;

        if (this.gpRegMap != that.gpRegMap)
            return false;

        return true;
    }

    /// Get the operand for an instruction argument
    X86Opnd getArgOpnd(
        CodeGenCtx ctx, 
        Assembler as, 
        IRInstr instr, 
        size_t argIdx, 
        uint16_t numBits, 
        bool loadVal = true
    )
    {
        assert (
            argIdx < instr.args.length,
            "invalid argument index"
        );

        assert (
            instr.opcode.getArgType(argIdx) == OpArg.LOCAL,
            "argument type is not local"
        );

        auto argSlot = instr.args[argIdx].localIdx;
        auto flags = allocState[argSlot];

        // If the argument already is in a general-purpose register
        if (flags & RA_GPREG)
        {
            auto regNo = flags & RA_REG_MASK;
            return new X86Reg(X86Reg.GP, cast(uint8_t)regNo, cast(uint16_t)numBits);
        }

        assert (
            flags & RA_STACK, 
            "argument is neither in a register nor on the stack"
        );

        // If the value shouldn't be loaded into a register
        if (loadVal == false)
        {
            // Return a memory operand of the right size
            return new X86Mem(numBits, wspReg, 8 * argSlot);
        }

        // Get the assigned register for the argument
        auto reg = ctx.regMapping[argSlot];

        // Get the slot mapped to this register
        auto regSlot = gpRegMap[reg.regNo];

        // If the register is mapped to a value
        if (regSlot !is NULL_LOCAL)
        {
            // If the mapped slot belongs to another instruction argument
            foreach (otherIdx, arg; instr.args)
            {
                if (otherIdx != argIdx && 
                    instr.opcode.getArgType(otherIdx) == OpArg.LOCAL &&
                    arg.localIdx == regSlot)
                {
                    writefln("got overlap");

                    // Map the argument to its stack location
                    allocState[argSlot] = RA_STACK;
                    return new X86Mem(numBits, wspReg, 8 * argSlot);
                }
            }

            // Spill the value currently in the register
            as.instr(MOV, new X86Mem(64, wspReg, 8 * regSlot), reg);
            allocState[regSlot] = RA_STACK;
        }

        // Load the argument into the register
        as.instr(MOV, reg, new X86Mem(64, wspReg, 8 * argSlot));

        // Map the argument to the register
        allocState[argSlot] = RA_GPREG | reg.regNo;
        gpRegMap[reg.regNo] = argSlot;
        return new X86Reg(X86Reg.GP, reg.regNo, numBits);
    }

    /// Get the operand for an instruction's output
    X86Opnd getOutOpnd(
        CodeGenCtx ctx, 
        Assembler as, 
        IRInstr instr, 
        uint16_t numBits
    )
    {
        assert (
            instr.outSlot != NULL_LOCAL,
            "instruction has no output slot"
        );

        // Get the assigned register for the out slot
        auto reg = ctx.regMapping[instr.outSlot];

        // Get the slot mapped to this register
        auto regSlot = gpRegMap[reg.regNo];

        // If another slot is using the register
        if (regSlot !is NULL_LOCAL && regSlot !is instr.outSlot)
        {
            // If an instruction argument is using this slot
            foreach (argIdx, arg; instr.args)
            {
                if (instr.opcode.getArgType(argIdx) == OpArg.LOCAL &&
                    arg.localIdx == regSlot)
                {
                    // Map the output slot to its stack location
                    allocState[instr.outSlot] = RA_STACK;
                    return new X86Mem(numBits, wspReg, 8 * instr.outSlot);
                }
            }

            // Spill the value currently in the register
            as.instr(MOV, new X86Mem(64, wspReg, 8 * regSlot), reg);
            allocState[regSlot] = RA_STACK;
        }

        // Map the output slot to the register
        allocState[instr.outSlot] = RA_GPREG | reg.regNo;
        gpRegMap[reg.regNo] = instr.outSlot;
        return new X86Reg(X86Reg.GP, reg.regNo, numBits);
    }

    // TODO: arg type access

    // Set the output type value for an instruction's output
    void setOutType(Assembler as, IRInstr instr, Type type)
    {
        assert (
            instr.outSlot != NULL_LOCAL,
            "instruction has no output slot"
        );

        // Create a memory operand to access the type stack
        auto memOpnd = new X86Mem(8, tspReg, instr.outSlot);

        // Write the type to the type stack
        as.instr(MOV, memOpnd, type);
    }

    /**
    Spill all registers to the stack
    */
    void spillRegs(Assembler as)
    {
        foreach (regNo, localIdx; gpRegMap)
        {
            if (localIdx is NULL_LOCAL)
                continue;

            auto mem = new X86Mem(64, wspReg, 8 * localIdx);
            auto reg = new X86Reg(X86Reg.GP, cast(uint8_t)regNo, 64);

            // Spill the value currently in the register
            as.instr(MOV, mem, reg);

            // Mark the value as being on the stack
            allocState[localIdx] = RA_STACK;

            // Mark the register as free
            gpRegMap[regNo] = NULL_LOCAL;
        }

        foreach (localIdx, flags; allocState)
        {
            assert (
                flags == RA_STACK, 
                "value not on stack after spill " ~ to!string(flags)
            );
        }
    }

    /// Get the register to which a local is mapped, if any
    X86Reg getReg(LocalIdx localIdx)
    {
        auto flags = allocState[localIdx];

        if (flags & RA_GPREG)
            return new X86Reg(X86Reg.GP, flags & RA_REG_MASK, 64);

        return null;
    }
}

/**
Basic block version
*/
struct BlockVersion
{
    /// Basic block
    IRBlock block;

    /// Associated state
    CodeGenState state;

    /// Jump label
    Label label;
}

/**
Code generation context
*/
class CodeGenCtx
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

    /// Register mapping (slots->regs)
    RegMapping regMapping;

    /// Function to get the label for a given block
    Label delegate(IRBlock, CodeGenState) getBlockLabel;

    /// Function to generate an entry point for a given block
    Label delegate(IRBlock) getEntryPoint;

    this(
        Interp interp,
        IRFunction fun,
        Assembler as,
        Assembler ol,
        Label bailLabel,
        RegMapping regMapping,
        Label delegate(IRBlock, CodeGenState) getBlockLabel,
        Label delegate(IRBlock) getEntryPoint,
    )
    {
        this.interp = interp;
        this.fun = fun;
        this.as = as;
        this.ol = ol;
        this.bailLabel = bailLabel;
        this.regMapping = regMapping;
        this.getBlockLabel = getBlockLabel;
        this.getEntryPoint = getEntryPoint;
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

void jump(Assembler as, CodeGenCtx ctx, CodeGenState st, IRBlock target)
{
    auto INTERP_JUMP = new Label("INTERP_JUMP");

    // Get a pointer to the branch target
    as.ptr(scrRegs64[0], target);

    // If a JIT entry point exists, jump to it directly
    as.getMember!("IRBlock", "jitEntry")(scrRegs64[1], scrRegs64[0]);
    as.instr(CMP, scrRegs64[1], 0);
    as.instr(JE, INTERP_JUMP);
    as.instr(JMP, scrRegs64[1]);

    // Make the interpreter jump to the target
    ctx.ol.addInstr(INTERP_JUMP);
    ctx.ol.setMember!("Interp", "target")(interpReg, scrRegs64[0]);
    ctx.ol.bail(ctx, st);
}

/// Bailout to the interpreter
void bail(Assembler as, CodeGenCtx ctx, CodeGenState st)
{
    // Spill the registers
    st.spillRegs(as);

    // Bailout to the interpreter
    as.instr(JMP, ctx.bailLabel);
}

/// Save caller-save registers on the stack before a C call
void pushRegs(Assembler as)
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
}

/// Restore caller-save registers from the after before a C call
void popRegs(Assembler as)
{
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

void gen_set_true(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, TRUE.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_false(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, FALSE.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_undef(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{  
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, UNDEF.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_missing(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, MISSING.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_null(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, NULL.int8Val);
    st.setOutType(ctx.as, instr, Type.REFPTR);
}

void gen_set_int32(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 32);
    ctx.as.instr(MOV, outOpnd, instr.args[0].int32Val);
    st.setOutType(ctx.as, instr, Type.INT32);
}

void gen_set_str(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto linkIdx = instr.args[1].linkIdx;

    assert (
        linkIdx !is NULL_LINK,
        "link not allocated for set_str"
    );

    ctx.as.getMember!("Interp", "wLinkTable")(scrRegs64[0], interpReg);
    ctx.as.instr(MOV, scrRegs64[0], new X86Mem(64, scrRegs64[0], 8 * linkIdx));

    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, scrRegs64[0]);
    st.setOutType(ctx.as, instr, Type.REFPTR);
}

void gen_move(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, 64);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    ctx.as.instr(MOV, opndOut, opnd0);

    // TODO: change when type info integrated?
    ctx.as.getType(scrRegs8[0], instr.args[0].localIdx);
    ctx.as.setType(instr.outSlot, scrRegs8[0]);
}

void IsTypeOp(Type type)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // TODO: change one type tags are accounted for in state
    // Get the type value
    ctx.as.getType(scrRegs8[0], instr.args[0].localIdx);

    // Compare against the tested type
    ctx.as.instr(CMP, scrRegs8[0], type);

    ctx.as.instr(MOV, scrRegs64[0], FALSE.int64Val);
    ctx.as.instr(MOV, scrRegs64[1], TRUE.int64Val);
    ctx.as.instr(CMOVE, scrRegs64[0], scrRegs64[1]);

    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, scrRegs64[0]);

    st.setOutType(ctx.as, instr, Type.CONST);
}

alias IsTypeOp!(Type.CONST) gen_is_const;
alias IsTypeOp!(Type.REFPTR) gen_is_refptr;
alias IsTypeOp!(Type.INT32) gen_is_int32;
alias IsTypeOp!(Type.FLOAT) gen_is_float;

/*
void gen_i32_to_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.instr(CVTSI2SD, XMM0, new X86Mem(32, wspReg, instr.args[0].localIdx * 8));

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_f64_to_i32(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Cast to int64 and truncate to int32 (to match JS semantics)
    ctx.as.instr(CVTSD2SI, RAX, new X86Mem(64, wspReg, instr.args[0].localIdx * 8));
    ctx.as.instr(MOV, ECX, EAX);

    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}
*/

void RMMOp(string op, size_t numBits, Type typeTag)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // The register allocator should ensure that at
    // least one input is a register operand
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, numBits);
    auto opnd1 = st.getArgOpnd(ctx, ctx.as, instr, 1, numBits);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, numBits);

    X86OpPtr opPtr = null;
    static if (op == "add")
        opPtr = ADD;
    static if (op == "sub")
        opPtr = SUB;
    static if (op == "imul")
        opPtr = IMUL;
    static if (op == "and")
        opPtr = AND;
    assert (opPtr !is null);

    if (opnd0 == opndOut)
    {
        ctx.as.instr(opPtr, opndOut, opnd1);
    }

    else if (opnd1 == opndOut)
    {
        ctx.as.instr(opPtr, opndOut, opnd0);
    }

    else if (opPtr == IMUL && cast(X86Mem)opndOut)
    {
        // IMUL does not support memory operands as output
        auto scrReg0 = new X86Reg(X86Reg.GP, scrRegs64[0].regNo, numBits);
        ctx.as.instr(MOV, scrReg0, opnd0);
        ctx.as.instr(opPtr, scrReg0, opnd1);
        ctx.as.instr(MOV, opndOut, scrReg0);
    }

    else
    {
        // Neither input operand is the output
        ctx.as.instr(MOV, opndOut, opnd0);
        ctx.as.instr(opPtr, opndOut, opnd1);
    }

    st.setOutType(ctx.as, instr, typeTag);
}

alias RMMOp!("add" , 32, Type.INT32) gen_add_i32;
alias RMMOp!("imul", 32, Type.INT32) gen_mul_i32;
alias RMMOp!("and" , 32, Type.INT32) gen_and_i32;

/*
void gen_add_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(ADDSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_sub_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(SUBSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_mul_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(MULSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_div_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(DIVSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}
*/

/*
void OvfOp(string op)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
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

void CmpOp(string op, size_t numBits)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, numBits);
    auto opnd1 = st.getArgOpnd(ctx, ctx.as, instr, 1, numBits);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 32);

    // Compare the inputs
    ctx.as.instr(CMP, opnd0, opnd1);

    ctx.as.instr(MOV, scrRegs16[0], FALSE.int8Val);
    ctx.as.instr(MOV, scrRegs16[1], TRUE.int8Val);

    X86OpPtr cmovOp = null;
    static if (op == "eq")
        cmovOp = CMOVE;
    static if (op == "ne")
        cmovOp = CMOVNE;
    static if (op == "lt")
        cmovOp = CMOVL;
    static if (op == "le")
        cmovOp = CMOVLE;
    static if (op == "gt")
        cmovOp = CMOVG;
    static if (op == "ge")
        cmovOp = CMOVGE;

    ctx.as.instr(cmovOp, scrRegs32[0], scrRegs32[1]);

    ctx.as.instr(MOV, opndOut, scrRegs32[0]);

    st.setOutType(ctx.as, instr, Type.CONST);
}

alias CmpOp!("eq", 8) gen_eq_i8;
alias CmpOp!("lt", 32) gen_lt_i32;
//alias CmpOp!("i32", "ge") gen_ge_i32;
//alias CmpOp!("i32", "ne") gen_ne_i32;
alias CmpOp!("eq", 8) gen_eq_const;
//alias CmpOp!("i64", "eq") gen_eq_refptr;
//alias CmpOp!("i64", "ne") gen_ne_refptr;

void LoadOp(size_t memSize, Type typeTag)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, 64);
    auto opnd1 = st.getArgOpnd(ctx, ctx.as, instr, 1, 32);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    X86Reg opnd0Reg = cast(X86Reg)opnd0;

    // Zero extend the offset input into a scratch register
    X86Reg opnd1Reg = scrRegs64[0];
    ctx.as.instr(MOV, scrRegs32[0], opnd1);

    assert (
        opnd0Reg && opnd1Reg, 
        "both inputs must be in registers"
    );

    X86OpPtr loadOp;
    static if (memSize == 8 || memSize == 16)
        loadOp = MOVZX;
    else
        loadOp = MOV;

    // If the output operand is a memory location
    if (cast(X86Mem)opndOut || memSize == 32)    
    {
        uint16_t scrSize = (memSize == 32)? 32:64;
        auto scrReg64 = scrRegs64[1];
        auto scrReg = new X86Reg(X86Reg.GP, scrReg64.regNo, scrSize);
        auto memOpnd = new X86Mem(memSize, opnd0Reg, 0, opnd1Reg);

        // Load to a scratch register and then move to the output
        ctx.as.instr(loadOp, scrReg, memOpnd);
        ctx.as.instr(MOV, opndOut, scrReg64);
    }
    else
    {
        // Load to the output register directly
        ctx.as.instr(loadOp, opndOut, new X86Mem(memSize, opnd0Reg, 0, opnd1Reg));
    }

    // Set the output type tag
    st.setOutType(ctx.as, instr, typeTag);
}

alias LoadOp!(8 , Type.INT32) gen_load_u8;
//alias LoadOp!(uint16, Type.INT32) gen_load_u16;
alias LoadOp!(32, Type.INT32) gen_load_u32;
alias LoadOp!(64, Type.INT32) gen_load_u64;
//alias LoadOp!(64, Type.FLOAT) gen_load_f64;
alias LoadOp!(64, Type.REFPTR) gen_load_refptr;
//alias LoadOp!(rawptr, Type.RAWPTR) gen_load_rawptr;
//alias LoadOp!(IRFunction, Type.FUNPTR) gen_load_funptr;

void gen_jump(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Jump to the target block
    auto blockLabel = ctx.getBlockLabel(instr.target, st);
    ctx.as.instr(JMP, blockLabel);
}

void gen_if_true(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Compare the argument to the true value
    auto argOpnd = st.getArgOpnd(ctx, ctx.as, instr, 0, 8);
    ctx.as.instr(CMP, argOpnd, TRUE.int8Val);

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
    auto sLabel = ctx.getBlockLabel(sTarget, st);
    auto fLabel = ctx.getBlockLabel(fTarget, st);

    ctx.as.instr(jumpOp, sLabel);
    ctx.as.instr(JMP, fLabel);
}

void gen_get_global(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[1].int32Val;

    // If no property index is cached, use the interpreter function
    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    auto AFTER_CMP  = new Label("PROP_AFTER_CMP");
    auto AFTER_WORD = new Label("PROP_AFTER_WORD");
    auto AFTER_TYPE = new Label("PROP_AFTER_TYPE");
    auto GET_PROP = new Label("PROP_GET_PROP");
    auto GET_OFS  = new Label("PROP_GET_OFS");

    // Allocate the output operand
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);

    //
    // Fast path
    //
    ctx.as.addInstr(GET_PROP);

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(scrRegs64[0], interpReg);

    // Compare the object size to the cached size
    ctx.as.getField(scrRegs32[1], scrRegs64[0], 4, obj_ofs_cap(interp.globalObj));
    ctx.as.instr(CMP, scrRegs32[1], 0x7FFFFFFF);
    ctx.as.addInstr(AFTER_CMP);
    ctx.as.instr(JNE, GET_OFS);

    // Get the word and type from the object
    ctx.as.instr(MOV, scrRegs64[2], new X86Mem(64, scrRegs64[0], 0x7FFFFFFF));
    ctx.as.addInstr(AFTER_WORD);
    ctx.as.instr(MOV, scrRegs8[3] , new X86Mem(8 , scrRegs64[0], 0x7FFFFFFF));
    ctx.as.addInstr(AFTER_TYPE);

    // Move the word to the output operand
    ctx.as.instr(MOV, outOpnd, scrRegs64[2]);

    // TODO: change when integrating type knowledge
    ctx.as.setType(instr.outSlot, scrRegs8[3]);

    //
    // Slow path: update the cached offset
    //
    ctx.ol.addInstr(GET_OFS);

    // Update the cached object size
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_CMP, -4), scrRegs32[1]);

    // Get the word offset
    ctx.ol.pushRegs();
    ctx.ol.instr(MOV, RDI, scrRegs64[0]);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_word);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_WORD, -4), EAX);
    ctx.ol.popRegs();

    // Get the type offset
    ctx.ol.pushRegs();
    ctx.ol.instr(MOV, RDI, scrRegs64[0]);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_type);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_TYPE, -4), EAX);
    ctx.ol.popRegs();

    // Read the property
    ctx.ol.instr(JMP, GET_PROP);
}

void gen_set_global(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[2].int32Val;

    // If no property index is cached, used the interpreter function
    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    auto AFTER_CMP  = new Label("PROP_AFTER_CMP");
    auto AFTER_WORD = new Label("PROP_AFTER_WORD");
    auto AFTER_TYPE = new Label("PROP_AFTER_TYPE");
    auto SET_PROP = new Label("PROP_SET_PROP");
    auto GET_OFS  = new Label("PROP_GET_OFS");

    // Allocate the input operand
    auto argOpnd = st.getArgOpnd(ctx, ctx.as, instr, 1, 64);

    //
    // Fast path
    //
    ctx.as.addInstr(SET_PROP);

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(scrRegs64[0], interpReg);

    // Compare the object size to the cached size
    ctx.as.getField(scrRegs32[1], scrRegs64[0], 4, obj_ofs_cap(interp.globalObj));
    ctx.as.instr(CMP, scrRegs32[1], 0x7FFFFFFF);
    ctx.as.addInstr(AFTER_CMP);
    ctx.as.instr(JNE, GET_OFS);

    // Move the input operand to a scratch register
    ctx.as.instr(MOV, scrRegs64[2], argOpnd);

    // TODO: change when integrating type knowledge
    ctx.as.getType(scrRegs8[3], instr.args[1].localIdx);

    // Set the word and type from the object
    ctx.as.instr(MOV, new X86Mem(64, scrRegs64[0], 0x7FFFFFFF), scrRegs64[2]);
    ctx.as.addInstr(AFTER_WORD);
    ctx.as.instr(MOV, new X86Mem(8 , scrRegs64[0], 0x7FFFFFFF), scrRegs8[3]);
    ctx.as.addInstr(AFTER_TYPE);

    //
    // Slow path: update the cached offset
    //
    ctx.ol.addInstr(GET_OFS);

    // Update the cached object size
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_CMP, -4), scrRegs32[1]);

    // Get the word offset
    ctx.ol.pushRegs();
    ctx.ol.instr(MOV, RDI, scrRegs64[0]);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_word);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_WORD, -4), EAX);
    ctx.ol.popRegs();

    // Get the type offset
    ctx.ol.pushRegs();
    ctx.ol.instr(MOV, RDI, scrRegs64[0]);
    ctx.ol.instr(MOV, RSI, propIdx);
    ctx.ol.ptr(RAX, &obj_ofs_type);
    ctx.ol.instr(jit.encodings.CALL, RAX);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_TYPE, -4), EAX);
    ctx.ol.popRegs();

    // Read the property
    ctx.ol.instr(JMP, SET_PROP);
}

void gen_call(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;
    auto numArgs = instr.args.length - 2;

    // Generate an entry point for the call continuation
    ctx.getEntryPoint(instr.target);

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
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    // Get the argument registers before spilling
    X86Reg[] argRegs;
    argRegs.length = numArgs;
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto argSlot = instr.args[$-(1+i)].localIdx;
        argRegs[i] = st.getReg(argSlot);
    }

    // Spill the registers
    st.spillRegs(ctx.as);

    // Label for the bailout to interpreter cases
    auto BAILOUT = new Label("CALL_BAILOUT");

    auto AFTER_CLOS = new Label("CALL_AFTER_CLOS");
    auto AFTER_OFS = new Label("CALL_AFTER_OFS");
    auto GET_FPTR = new Label("CALL_GET_FPTR");
    auto GET_OFS = new Label("CALL_GET_OFS");

    //
    // Fast path
    //
    ctx.as.addInstr(GET_FPTR);

    // Get the closure word off the stack
    ctx.as.getWord(scrRegs64[0], closIdx);

    // Compare the closure pointer to the cached pointer
    ctx.as.instr(MOV, scrRegs64[1], 0x7FFFFFFFFFFFFFFF);
    ctx.as.addInstr(AFTER_CLOS);
    ctx.as.instr(CMP, scrRegs64[0], scrRegs64[1]);
    ctx.as.instr(JNE, GET_OFS);

    // Get the function pointer from the closure object
    ctx.as.instr(MOV, scrRegs64[2], new X86Mem(64, scrRegs64[0], 0x7FFFFFFF));
    ctx.as.addInstr(AFTER_OFS);

    //
    // Slow path: update the cached function pointer offset (out of line)
    //
    ctx.ol.addInstr(GET_OFS);

    // Update the cached closure poiter
    ctx.ol.instr(MOV, new X86IPRel(64, AFTER_CLOS, -8), scrRegs64[0]);

    // Get the function pointer offset
    ctx.ol.pushRegs();
    ctx.ol.instr(MOV, RDI, scrRegs64[0]);
    ctx.ol.ptr(scrRegs64[0], &clos_ofs_fptr);
    ctx.ol.instr(jit.encodings.CALL, scrRegs64[0]);
    ctx.ol.instr(MOV, new X86IPRel(32, AFTER_OFS, -4), EAX);
    ctx.ol.popRegs();

    // Use the interpreter call instruction this time
    ctx.ol.instr(JMP, BAILOUT);

    //
    // Function call logic
    //

    // If this is not the closure we expect, bailout to the interpreter
    ctx.as.ptr(scrRegs64[3], fun);
    ctx.as.instr(CMP, scrRegs64[2], scrRegs64[3]);
    ctx.as.instr(JNE, BAILOUT);

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
        auto dstIdx = (numArgs - i - 1) + numVars + NUM_HIDDEN_ARGS;

        // If this argument is in a register
        if (argRegs[i] !is null)
        {
            //writefln("arg reg: %s %s", argRegs[i], i);
            ctx.as.setWord(cast(LocalIdx)dstIdx, argRegs[i]);
        }
        else
        {
            ctx.as.getWord(scrRegs64[3], argSlot + numPush); 
            ctx.as.setWord(cast(LocalIdx)dstIdx, scrRegs64[3]);
        }

        ctx.as.getType(scrRegs8[3], argSlot + numPush);
        ctx.as.setType(cast(LocalIdx)dstIdx, scrRegs8[3]);
    }

    // Write the argument count
    ctx.as.setWord(cast(LocalIdx)(numVars + 3), cast(int32_t)numArgs);
    ctx.as.setType(cast(LocalIdx)(numVars + 3), Type.INT32);

    // Copy the "this" argument
    ctx.as.getWord(scrRegs64[2], thisIdx + numPush);
    ctx.as.getType(scrRegs8[3], thisIdx + numPush);
    ctx.as.setWord(cast(LocalIdx)(numVars + 2), scrRegs64[2]);
    ctx.as.setType(cast(LocalIdx)(numVars + 2), scrRegs8[3]);

    // Write the closure argument
    ctx.as.setWord(cast(LocalIdx)(numVars + 1), scrRegs64[0]);
    ctx.as.setType(cast(LocalIdx)(numVars + 1), Type.REFPTR);

    // Write the return address (caller instruction)
    ctx.as.ptr(scrRegs64[3], instr);
    ctx.as.setWord(cast(LocalIdx)(numVars + 0), scrRegs64[3]);
    ctx.as.setType(cast(LocalIdx)(numVars + 0), Type.INSPTR);

    // Jump to the callee entry point
    ctx.as.jump(ctx, st, fun.entryBlock);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(BAILOUT);

    // Call the interpreter call instruction
    // Fallback to interpreter execution
    defaultFn(ctx.ol, ctx, st, instr);
}

void gen_ret(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.block.fun.raSlot;
    auto argcSlot  = instr.block.fun.argcSlot;
    auto thisSlot  = instr.block.fun.thisSlot;
    auto numParams = instr.block.fun.params.length;
    auto numLocals = instr.block.fun.numLocals;

    // Call the interpreter return instruction
    defaultFn(ctx.as, ctx, st, instr);

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

void gen_get_global_obj(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Get the output operand. This must be a 
    // register since it's the only operand.
    auto opndOut = cast(X86Reg)st.getOutOpnd(ctx, ctx.as, instr, 64);
    assert (opndOut !is null, "output is not a register");

    ctx.as.getMember!("Interp", "globalObj")(opndOut, interpReg);

    st.setOutType(ctx.as, instr, Type.REFPTR);
}

void defaultFn(Assembler as, CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Get the function corresponding to this instruction
    // alias void function(Interp interp, IRInstr instr) OpFn;
    // RDI: first argument (interp)
    // RSI: second argument (instr)
    auto opFn = instr.opcode.opFn;

    // Spill all registers
    st.spillRegs(as);

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
    as.ptr(scrRegs64[0], opFn);
    as.instr(jit.encodings.CALL, scrRegs64[0]);

    // If this is a branch instruction
    if (instr.opcode.isBranch == true)
    {
        // Reload the stack pointers, the instruction may have changed them
        as.getMember!("Interp", "wsp")(wspReg, interpReg);
        as.getMember!("Interp", "tsp")(tspReg, interpReg);

        // Bailout to the interpreter
        as.bail(ctx, st);

        if (opts.jit_dumpinfo)
            writefln("interpreter bailout");
    }
}

alias void function(CodeGenCtx ctx, CodeGenState st, IRInstr instr) CodeGenFn;

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
    */

    codeGenFns[&EQ_I8]          = &gen_eq_i8;
    codeGenFns[&LT_I32]         = &gen_lt_i32;
    //codeGenFns[&GE_I32]         = &gen_ge_i32;
    //codeGenFns[&NE_I32]         = &gen_ne_i32;
    codeGenFns[&EQ_CONST]       = &gen_eq_const;
    //codeGenFns[&EQ_REFPTR]      = &gen_eq_refptr;
    //codeGenFns[&NE_REFPTR]      = &gen_ne_refptr;

    codeGenFns[&LOAD_U8]        = &gen_load_u8;
    codeGenFns[&LOAD_U32]       = &gen_load_u32;
    codeGenFns[&LOAD_U64]       = &gen_load_u64;
    //codeGenFns[&LOAD_F64]       = &gen_load_f64;
    codeGenFns[&LOAD_REFPTR]    = &gen_load_refptr;

    codeGenFns[&JUMP]           = &gen_jump;

    codeGenFns[&IF_TRUE]        = &gen_if_true;

    codeGenFns[&ir.ir.CALL]     = &gen_call;
    codeGenFns[&ir.ir.RET]      = &gen_ret;

    codeGenFns[&GET_GLOBAL]     = &gen_get_global;
    codeGenFns[&SET_GLOBAL]     = &gen_set_global;

    codeGenFns[&GET_GLOBAL_OBJ] = &gen_get_global_obj;
}

