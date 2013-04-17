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
import jit.ops;
import util.bitset;

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

    // Total number of block versions
    size_t numVersions = 0;

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

        // Increment the total number of versions
        numVersions++;

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
        auto blockLabel = getBlockLabel(block, new CodeGenState(fun));

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
        liveSets,
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

            // Spill the registers live at the beginning of this block
            auto liveSet = ctx.liveSets[block.firstInstr];
            state.spillRegs(
                ol,
                delegate bool(size_t regNo, LocalIdx localIdx)
                {
                    if (block.firstInstr.hasArg(localIdx))
                        return true;

                    if (liveSet.has(localIdx))
                        return true;

                    return false;
                }
            );

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
        writefln("num blocks: %s", versionMap.length);
        writefln("num versions: %s", numVersions);
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

/// Register allocation state
alias uint8_t RAState;
const RAState RA_DEAD = 0;
const RAState RA_STACK = (1 << 7);
const RAState RA_GPREG = (1 << 6);
const RAState RA_REG_MASK = (0x0F);

// Type flag state
alias uint8_t TFState;
const TFState TF_TYPE_KNOWN = (1 << 7);
const TFState TF_TYPE_SYNC = (1 << 6);
const TFState TF_TYPE_MASK = (0x1F);

/**
Code generation state
*/
class CodeGenState
{
    /// Register allocation state (per-local)
    RAState[] allocState;

    /// Map of general-purpose registers to locals
    /// This is NULL_LOCAL if a register is free
    LocalIdx[] gpRegMap;

    /// TODO: type flags
    // Implement only once versioning/regalloc working

    /// Type information state, type flags (per-local)
    TFState[] typeState;

    /// Constructor for a default/entry code generation state
    this(IRFunction fun)
    {
        allocState.length = fun.numLocals;

        // All arguments are initially on the stack, other
        // values are dead until they are written
        for (size_t i = 0; i < allocState.length; ++i)
        {
            if (i < fun.numLocals - (fun.numLocals + NUM_HIDDEN_ARGS))
                allocState[i] = RA_STACK;
            else
                allocState[i] = RA_DEAD;
        }

        // All registers are initially free
        gpRegMap.length = 16;
        for (size_t i = 0; i < gpRegMap.length; ++i)
            gpRegMap[i] = NULL_LOCAL;

        // No type info is initially known
        typeState.length = fun.numLocals;
        for (size_t i = 0; i < typeState.length; ++i)
            typeState[i] = 0;
    }

    /// Copy constructor
    this(CodeGenState that)
    {
        this.allocState = that.allocState.dup;
        this.gpRegMap = that.gpRegMap.dup;
        this.typeState = that.typeState.dup;
    }

    /// Produce a string representation of the state
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

        if (this.typeState != that.typeState)
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
            "argument is neither in a register nor on the stack \n" ~
            "argSlot: " ~ to!string(argSlot) ~ "\n" ~
            "fun: " ~ instr.block.fun.getName() ~ "\n" ~
            instr.block.toString()

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

            // If the value is live, spill it
            if (ctx.liveSets[instr].has(regSlot) == true)
                spillReg(as, reg.regNo);
            else
                allocState[regSlot] = RA_DEAD;
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

            // If the value is live, spill it
            if (ctx.liveSets[instr].has(regSlot) == true)
                spillReg(as, reg.regNo);
            else
                allocState[regSlot] = RA_DEAD;
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

        assert (
            (type & TF_TYPE_MASK) == type,
            "type mask corrupts type tag"
        );

        auto localIdx = instr.outSlot;




        // Get the previous type state
        auto prevState = typeState[localIdx];

        // Check if the type is still in sync
        auto inSync = (
            (prevState & TF_TYPE_SYNC) &&
            (prevState & TF_TYPE_KNOWN) &&
            ((prevState & TF_TYPE_MASK) == type)
        );

        // Set the type known flag and update the type
        typeState[localIdx] = TF_TYPE_KNOWN | (inSync? TF_TYPE_SYNC:0) | type;






        // FIXME:
        // Create a memory operand to access the type stack
        auto memOpnd = new X86Mem(8, tspReg, instr.outSlot);

        // FIXME:
        // Write the type to the type stack
        as.instr(MOV, memOpnd, type);

        // FIXME: temporary until type info is integrated
        if (allocState[instr.outSlot] & RA_GPREG)
            as.instr(MOV, new X86Mem(64, wspReg, 8 * instr.outSlot), 0);
    }

    /// Spill test function
    alias bool delegate(size_t regNo, LocalIdx localIdx) SpillTestFn;

    /**
    Spill registers to the stack
    */
    void spillRegs(Assembler as, SpillTestFn spillTest = null)
    {
        // For each general-purpose register
        foreach (regNo, localIdx; gpRegMap)
        {
            // If nothing is mapped to this register, skip it
            if (localIdx is NULL_LOCAL)
                continue;

            // If the value should be spilled, spill it
            if (spillTest is null || spillTest(regNo, localIdx) == true)
                spillReg(as, regNo);
        }
    }

    /// Spill a specific register to the stack
    void spillReg(Assembler as, size_t regNo)
    {
        // Get the slot mapped to this register
        auto regSlot = gpRegMap[regNo];

        // If no value is mapped to this register, stop
        if (regSlot is NULL_LOCAL)
            return;

        auto mem = new X86Mem(64, wspReg, 8 * regSlot);
        auto reg = new X86Reg(X86Reg.GP, cast(uint8_t)regNo, 64);

        //writefln("spilling: %s (%s)", regSlot, reg);

        // Spill the value currently in the register
        as.comment("Spilling $" ~ to!string(regSlot));
        as.instr(MOV, mem, reg);

        // Mark the value as being on the stack
        allocState[regSlot] = RA_STACK;

        // Mark the register as free
        gpRegMap[regNo] = NULL_LOCAL;
    }

    /// Mark a value as being stored on the stack
    void valOnStack(LocalIdx localIdx)
    {
        allocState[localIdx] = RA_STACK;
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

    /// Per-instruction live sets
    BitSet[IRInstr] liveSets;

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
        BitSet[IRInstr] liveSets,
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
        this.liveSets = liveSets;
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
    ctx.ol.instr(JMP, ctx.bailLabel);
}

void jump(Assembler as, CodeGenCtx ctx, CodeGenState st, X86Reg targetReg)
{
    assert (targetReg != scrRegs64[1]);

    auto INTERP_JUMP = new Label("INTERP_JUMP");

    // If a JIT entry point exists, jump to it directly
    as.getMember!("IRBlock", "jitEntry")(scrRegs64[1], targetReg);
    as.instr(CMP, scrRegs64[1], 0);
    as.instr(JE, INTERP_JUMP);
    as.instr(JMP, scrRegs64[1]);

    // Make the interpreter jump to the target and bailout
    ctx.ol.addInstr(INTERP_JUMP);
    ctx.ol.setMember!("Interp", "target")(interpReg, targetReg);
    ctx.ol.instr(JMP, ctx.bailLabel);
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
    as.pushRegs();

    as.instr(MOV, RDI, reg);
    as.ptr(RAX, &jit.jit.printUint);
    as.instr(jit.encodings.CALL, RAX);

    as.popRegs();
}

/**
Print an unsigned integer value. Callable from the JIT
*/
extern (C) void printUint(uint64_t v)
{
    writefln("%s", v);
}

