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
import ir.inlining;
import util.bitset;

/// Block execution count at which a function should be compiled
const JIT_COMPILE_COUNT = 1000;

/// Where a function is on the call stack
enum StackPos
{
    NOT,
    TOP,
    DEEP
}

/**
Test if a function is on the interpreter stack
*/
StackPos funOnStack(Interp interp, IRFunction fun)
{
    size_t maxDepth = size_t.max;

    auto visitFrame = delegate void(
        IRFunction curFun, 
        Word* wsp, 
        Type* tsp, 
        size_t depth,
        size_t frameSize,
        IRInstr callInstr
    )
    {
        if (curFun is fun)
            if (depth > maxDepth || maxDepth == size_t.max)
                maxDepth = depth;
    };

    interp.visitStack(visitFrame);

    if (maxDepth == size_t.max)
        return StackPos.NOT;
    else if (maxDepth == 0)
        return StackPos.TOP;
    else
        return StackPos.DEEP;
}

/**
Selectively inline callees into a function
*/
void inlinePass(Interp interp, IRFunction fun)
{
    // Test if and where this function is on the call stack
    auto stackPos = funOnStack(interp, fun);

    // Don't inline if the function is deep on the stack
    if (stackPos is StackPos.DEEP)
        return;

    // Get the number of locals before inlining
    auto numLocals = fun.numLocals;

    // FIXME
    return;

    /*
    //writeln(fun.toString());

    // For each block of the function
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        // If this block was never executed, skip it
        if (block.execCount == 0)
            continue;

        // Get the last instruction of the block
        auto lastInstr = block.lastInstr;

        // If this is is not a call instruction, skip it
        if (lastInstr.opcode != &ir.ir.CALL)
            continue;

        // If there is not exactly one callee, skip it
        if (fun.callCounts[lastInstr].length != 1)
            continue;

        // Get the callee
        auto callee = fun.callCounts[lastInstr].keys[0];

        // If this combination is not inlinable, skip it
        if (inlinable(lastInstr, callee) is false)
            continue;

        if (opts.jit_dumpinfo)
        {
            writefln(
                "inlining %s into %s",
                callee.getName(),
                lastInstr.block.fun.getName()
            );
        }

        // Inline the callee
        inlineCall(lastInstr, callee);

        //writefln("inlined");
        //writeln(fun.toString());
    }

    // If the function is on top of the stack
    if (stackPos is StackPos.TOP)
    {
        //writefln("rearranging stack frame");

        // Add space for the new locals to the stack frame
        auto numAdded = fun.numLocals - numLocals;
        interp.push(numAdded);
    }

    //
    // TODO: stack frame compaction
    // will depend on liveness info, current IP (who's live now)
    // live values get mapped to new slots
    // will need to use a virtual dst frame to avoid collisions
    //
    //writefln("inlinePass done");
    */
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

    // If inlining is not disabled
    if (!opts.jit_noinline)
    {
        // Run the inlining pass on this function
        inlinePass(interp, fun);
    }

    // FIXME
    BitSet[IRInstr] liveSets;

    // Run a live variable analysis on the function
    auto liveQueryFn = compLiveVars(fun);

    // Assign a register mapping to each temporary
    auto regMapping = mapRegs(fun, liveQueryFn);

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

            // FIXME
            /*
            // Spill the registers live at the beginning of this block
            auto liveSet = ctx.liveSets[block.firstInstr];
            state.spillRegs(
                ol,
                delegate bool(LocalIdx localIdx)
                {
                    if (block.firstInstr.hasArg(localIdx))
                        return true;

                    if (liveSet.has(localIdx))
                        return true;

                    return false;
                }
            );
            */

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

        //as.printStr(block.getName() ~ " (" ~ fun.getName() ~ ")\n");

        // For each instruction of the block
        INSTR_LOOP:
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            auto opcode = instr.opcode;

            as.comment(instr.toString());

            //as.printStr(instr.toString() ~ "\n");
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

    // If ASM optimizations are not disabled
    if (!opts.jit_noasmopts)
    {
        // Perform peephole optimizations on the generated code
        optAsm(as);
    }

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
        writefln("num locals: %s", fun.numLocals);
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
const RAState RA_STACK = (1 << 7);
const RAState RA_GPREG = (1 << 6);
const RAState RA_CONST = (1 << 5);
const RAState RA_REG_MASK = (0x0F);

// Type flag state
alias uint8_t TFState;
const TFState TF_KNOWN = (1 << 7);
const TFState TF_SYNC = (1 << 6);
const TFState TF_BOOL_TRUE = (1 << 5);
const TFState TF_BOOL_FALSE = (1 << 4);
const TFState TF_TYPE_MASK = (0xF);

/**
Code generation state
*/
class CodeGenState
{
    /// Type information state, type flags (per-value)
    private TFState[IRDstValue] typeState;

    /// Register allocation state (per-value)
    private RAState[IRDstValue] allocState;

    /// Map of general-purpose registers to values
    /// This is NULL_LOCAL if a register is free
    private IRDstValue[] gpRegMap;

    /// Constructor for a default/entry code generation state
    this(IRFunction fun)
    {
        // TODO: mark argument values as initially on the stack
        // allocState[i] = RA_STACK;

        // All registers are initially free
        gpRegMap.length = 16;
        for (size_t i = 0; i < gpRegMap.length; ++i)
            gpRegMap[i] = null;
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

        foreach (regNo, value; gpRegMap)
        {
            if (value is null)
                continue;

            auto reg = new X86Reg(X86Reg.GP, regNo, 64);

            output ~= reg.toString() ~ " => $" ~ value.toString();
        }

        return output;
    }

    /// Equality comparison operator
    override bool opEquals(Object o)
    {
        auto that = cast(CodeGenState)o;
        assert (that !is null);

        // FIXME: need to remove dead values for this to work

        if (this.typeState != that.typeState)
            return false;

        if (this.allocState != that.allocState)
            return false;

        if (this.gpRegMap != that.gpRegMap)
            return false;

        return true;
    }

    // FIXME
    /*
    /// Get the word operand for an instruction argument
    X86Opnd getWordOpnd(
        CodeGenCtx ctx, 
        Assembler as, 
        IRInstr instr, 
        size_t argIdx, 
        uint16_t numBits, 

        //bool loadVal = true,


        X86Reg tmpReg = null,


        bool acceptImm = false
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

        X86Opnd immOpnd = null;

        // If the value is a constant
        if (flags & RA_CONST)
        {
            immOpnd = new X86Imm(getWord(argSlot).int64Val);

            // If we can accept immediate operands
            if (acceptImm)
                return immOpnd;
        }

        // If the argument already is in a general-purpose register
        if (flags & RA_GPREG)
        {
            auto regNo = flags & RA_REG_MASK;
            return new X86Reg(X86Reg.GP, regNo, numBits);
        }

        // If a temporary register is specified
        if (tmpReg !is null)
        {
            // Move the current value into the temporary register
            if (immOpnd)
            {
                as.instr(MOV, tmpReg, immOpnd);
            }
            else
            {
                as.instr(
                    (tmpReg.type == X86Reg.XMM)? MOVSD:MOV, 
                    tmpReg, 
                    new X86Mem(numBits, wspReg, 8 * argSlot)
                );
            }

            return tmpReg;
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
                    // Map the argument to its stack location
                    allocState[argSlot] = RA_STACK;
                    auto opnd = new X86Mem(numBits, wspReg, 8 * argSlot);

                    // If constant, move the constant value into the operand
                    if (immOpnd)
                        as.instr(MOV, new X86Mem(64, wspReg, 8 * argSlot), immOpnd);

                    return opnd;
                }
            }

            // If the currently mapped value is live, spill it
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
        auto opnd = new X86Reg(X86Reg.GP, reg.regNo, numBits);

        // If constant, move the constant value into the operand
        if (immOpnd)
            as.instr(MOV, new X86Reg(X86Reg.GP, reg.regNo, 32), immOpnd);

        return opnd;
    }
    */

    // FIXME
    /*
    /// Get an x86 operand for the type of a value
    X86Opnd getTypeOpnd(
        Assembler as,
        IRInstr instr,
        size_t argIdx,
        X86Reg tmpReg8 = null
    ) const
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

        if (typeKnown(argSlot))
        {
            return new X86Imm(getType(argSlot));
        }

        auto memLoc = new X86Mem(8, tspReg, argSlot);

        if (tmpReg8 !is null)
        {
            as.instr(MOV, tmpReg8, memLoc);
            return tmpReg8;
        }

        return memLoc;
    }
    */

    // FIXME
    /*
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
    */

    /// Set the output of an instruction to a known boolean value
    void setOutBool(IRInstr instr, bool val)
    {
        assert (
            instr.outSlot != NULL_LOCAL,
            "instruction has no output slot"
        );

        auto localIdx = instr.outSlot;

        // Mark this as being a known constant
        allocState[instr] = RA_CONST;

        // Set the output type
        setOutType(null, instr, Type.CONST);

        // Store the boolean constant in the type flags
        typeState[instr] |= val? TF_BOOL_TRUE:TF_BOOL_FALSE;
    }

    /// Test if a constant word value is known for a given value
    bool wordKnown(IRDstValue value) const
    {
        return (allocState[value] & RA_CONST) != 0;
    }

    /// Get the word value for a known constant local
    Word getWord(IRDstValue value)
    {
        auto allocSt = allocState[value];
        auto typeSt = typeState[value];

        assert (allocSt & RA_CONST);

        if (typeSt & TF_BOOL_TRUE)
            return TRUE;
        else if (typeSt & TF_BOOL_FALSE)
            return FALSE;
        else
            assert (false, "unknown constant");
    }

    /// Set the output type value for an instruction's output
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
        auto prevState = typeState.get(instr, 0);

        // Check if the type is still in sync
        auto inSync = (
            (prevState & TF_SYNC) &&
            (prevState & TF_KNOWN) &&
            ((prevState & TF_TYPE_MASK) == type)
        );

        // Set the type known flag and update the type
        typeState[instr] = TF_KNOWN | (inSync? TF_SYNC:0) | type;

        // If the output operand is on the stack
        if (allocState.get(instr, 0) & RA_STACK)
        {
            // Write the type value to the type stack
            as.instr(MOV, new X86Mem(8, tspReg, instr.outSlot), type);

            // Mark the type as in sync, so we don't spill the type later
            typeState[instr] |= TF_SYNC;
        }
    }

    /// Write the output type for an instruction's output to the type stack
    void setOutType(Assembler as, IRInstr instr, X86Reg typeReg)
    {
        // Mark the type value as unknown
        typeState.remove(instr);

        // Write the type to the type stack
        auto memOpnd = new X86Mem(8, tspReg, instr.outSlot);
        as.instr(MOV, memOpnd, typeReg);

        // If the output is mapped to a register, write a 0 value
        // to the word stack to avoid invalid references
        if (allocState.get(instr, 0) & RA_GPREG)
            as.instr(MOV, new X86Mem(64, wspReg, 8 * instr.outSlot), 0);
    }

    /// Test if a constant type is known for a given local
    bool typeKnown(IRDstValue value) const
    {
        return (value in typeState) !is null;
    }

    /// Get the known type of a value
    Type getType(IRDstValue value) const
    {
        auto typeState = typeState.get(value, 0);

        assert (
            typeState & TF_KNOWN,
            "type is unknown"
        );

        return cast(Type)(typeState & TF_TYPE_MASK);
    }

    /// Mark a value as being stored on the stack
    void valOnStack(IRDstValue value)
    {
        // Mark the value as being on the stack
        allocState[value] = RA_STACK;

        // Mark the type of this value as unknown
        typeState.remove(value);
    }

    // FIXME: make this use values instead of LocalIdx
    /// Spill test function
    alias bool delegate(LocalIdx localIdx) SpillTestFn;

    /**
    Spill registers to the stack
    */
    void spillRegs(Assembler as, SpillTestFn spillTest = null)
    {
        // FIXME

        /*
        // For each general-purpose register
        foreach (regNo, localIdx; gpRegMap)
        {
            // If nothing is mapped to this register, skip it
            if (localIdx is NULL_LOCAL)
                continue;

            // If the value should be spilled, spill it
            if (spillTest is null || spillTest(localIdx) == true)
                spillReg(as, regNo);
        }

        //writefln("spilling consts");

        // For each local
        foreach (LocalIdx localIdx, allocSt; allocState)
        {
            // If this is a known constant
            if (allocSt & RA_CONST)          
            {
                // If the value should be spilled
                if (spillTest is null || spillTest(localIdx) == true)
                {
                    // Spill the constant value to the stack
                    as.comment("Spilling constant value of $" ~to!string(localIdx));
                    auto word = getWord(localIdx);
                    as.setWord(localIdx, word.int32Val);

                    auto typeSt = typeState[localIdx];
                    assert (typeSt & TF_KNOWN);

                    // If the type flags are not in sync
                    if (!(typeSt & TF_SYNC))
                    {
                        // Write the type tag to the type stack
                        as.comment("Spilling type for $" ~to!string(localIdx));
                        auto type = cast(Type)(typeSt & TF_TYPE_MASK);
                        as.setType(localIdx, type);
                    }
                }
            }
        }
        */

        //writefln("done spilling consts");
    }

    /// Spill a specific register to the stack
    void spillReg(Assembler as, size_t regNo)
    {

        // FIXME

        /*
        // Get the slot mapped to this register
        auto regSlot = gpRegMap[regNo];

        // If no value is mapped to this register, stop
        if (regSlot is NULL_LOCAL)
            return;

        auto mem = new X86Mem(64, wspReg, 8 * regSlot);
        auto reg = new X86Reg(X86Reg.GP, regNo, 64);

        //writefln("spilling: %s (%s)", regSlot, reg);

        // Spill the value currently in the register
        as.comment("Spilling $" ~ to!string(regSlot));
        as.instr(MOV, mem, reg);

        // Mark the value as being on the stack
        allocState[regSlot] = RA_STACK;

        // Mark the register as free
        gpRegMap[regNo] = NULL_LOCAL;

        // Get the type state for this local
        auto typeSt = typeState[regSlot];

        // If the type is known but not in sync
        if ((typeSt & TF_KNOWN) && !(typeSt & TF_SYNC))
        {
            // Write the type tag to the type stack
            as.comment("Spilling type for $" ~to!string(regSlot));
            auto type = typeSt & TF_TYPE_MASK;
            auto memOpnd = new X86Mem(8, tspReg, cast(LocalIdx)regSlot);
            as.instr(MOV, memOpnd, type);

            // The type state is now in sync
            typeState[regSlot] |= TF_SYNC;
        }
        */


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

void comment(Assembler as, lazy string str)
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
void getWord(Assembler as, X86Reg dstReg, int32_t idx)
{
    if (dstReg.type == X86Reg.GP)
        as.instr(MOV, dstReg, new X86Mem(dstReg.size, wspReg, 8 * idx));
    else if (dstReg.type == X86Reg.XMM)
        as.instr(MOVSD, dstReg, new X86Mem(64, wspReg, 8 * idx));
    else
        assert (false, "unsupported register type");
}

/// Read from the type stack
void getType(Assembler as, X86Reg dstReg, int32_t idx)
{
    as.instr(MOV, dstReg, new X86Mem(8, tspReg, idx));
}

/// Write to the word stack
void setWord(Assembler as, int32_t idx, X86Opnd src)
{
    auto memOpnd = new X86Mem(64, wspReg, 8 * idx);

    if (auto srcReg = cast(X86Reg)src)
    {
        if (srcReg.type == X86Reg.GP)
            as.instr(MOV, memOpnd, srcReg);
        else if (srcReg.type == X86Reg.XMM)
            as.instr(MOVSD, memOpnd, srcReg);
        else
            assert (false, "unsupported register type");
    }
    else if (auto srcImm = cast(X86Imm)src)
    {
        as.instr(MOV, memOpnd, srcImm);
    }
    else
    {
        assert (false, "unsupported src operand type");
    }
}

// Write a constant to the word type
void setWord(Assembler as, int32_t idx, int32_t imm)
{
    as.instr(MOV, new X86Mem(64, wspReg, 8 * idx), imm);
}

/// Write to the type stack
void setType(Assembler as, int32_t idx, X86Opnd srcOpnd)
{
    as.instr(MOV, new X86Mem(8, tspReg, idx), srcOpnd);
}

/// Write a constant to the type stack
void setType(Assembler as, int32_t idx, Type type)
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

    as.instr(MOV, cargRegs[0], reg);

    alias extern (C) void function(uint64_t) PrintUintFn;
    PrintUintFn printUintFn = &printUint;

    as.ptr(RAX, printUintFn);
    as.instr(jit.encodings.CALL, RAX);

    as.popRegs();
}

void printStr(Assembler as, string str)
{
    as.pushRegs();

    auto STR_DATA = new Label("STR_DATA");
    auto AFTER_STR = new Label("AFTER_STR");

    as.instr(JMP, AFTER_STR);

    as.addInstr(STR_DATA);
    foreach (chIdx, ch; str)
        as.addInstr(new IntData(cast(uint)ch, 8));    
    as.addInstr(new IntData(0, 8));

    as.addInstr(AFTER_STR);

    as.instr(LEA, cargRegs[0], new X86IPRel(8, STR_DATA));

    alias extern (C) void function(char*) PrintStrFn;
    PrintStrFn printStrFn = &printStr;

    as.ptr(scrRegs64[0], printStrFn);
    as.instr(jit.encodings.CALL, scrRegs64[0]);

    as.popRegs();
}

/**
Print an unsigned integer value. Callable from the JIT
*/
extern (C) void printUint(uint64_t v)
{
    writefln("%s", v);
}

/**
Print a C string value. Callable from the JIT
*/
extern (C) void printStr(char* pStr)
{
    printf("%s", pStr);
}

