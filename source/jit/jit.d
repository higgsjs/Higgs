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
import std.datetime;
import std.string;
import std.array;
import std.stdint;
import std.conv;
import std.algorithm;
import options;
import ir.ir;
import ir.livevars;
import ir.typeprop;
import interp.interp;
import interp.layout;
import interp.object;
import interp.string;
import interp.gc;
import jit.codeblock;
import jit.assembler;
import jit.x86;
import jit.encodings;
import jit.peephole;
import jit.regalloc;
import jit.moves;
import jit.ops;
import jit.inlining;
import util.bitset;

/// Block execution count at which a function should be compiled
const JIT_COMPILE_COUNT = 800;

/// Block execution count at which a function should inline callees
const JIT_INLINE_COUNT = 400;

/**
Compile a function to machine code
*/
void compFun(Interp interp, IRFunction fun)
{
    auto startTimeUsecs = Clock.currAppTick().usecs();

    if (opts.jit_dumpinfo)
    {
        writefln(
            "compiling function %s", 
            fun.getName()
        );
    }

    /*
    // If inlining is not disabled and this is the first compilation
    if (!opts.jit_noinline && fun.jitCount is 0)
    {
        // Run the inlining pass on this function
        inlinePass(interp, fun);
    }
    */

    // If the IR should be output
    if (opts.jit_dumpir)
    {
        writeln(fun);
    }

    // If the type propagation analysis is enabled
    TypeMap typeMap;
    if (opts.jit_typeprop)
    {
        typeMap = typeProp(fun, true);
    }

    // Run a live variable analysis on the function
    auto liveInfo = new LiveInfo(fun);

    // Assign a register mapping to each temporary
    auto regMapping = mapRegs(fun, liveInfo);

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

    // Map of call instructions to continuation block labels
    Label[RAEntry] callContMap;

    /// Get a label for a given block and incoming state
    auto getBlockVersion = delegate BlockVersion(
        IRBlock block, 
        CodeGenState predState
    )
    {
        // Get the list of versions for this block
        auto versions = versionMap.get(block, []);

        // Best version found
        BlockVersion bestVer;
        size_t bestDiff = size_t.max;

        // For each successor version available
        foreach (ver; versions)
        {
            // Compute the difference with the predecessor state
            auto diff = predState.diff(ver.state);

            // If this is a perfect match, return it
            if (diff is 0)
                return ver;

            // Update the best version found
            if (diff < bestDiff)
            {
                bestDiff = diff;
                bestVer = ver;
            }
        }

        // If the block version cap is hit
        if (versions.length >= opts.jit_maxvers)
        {            
            //writeln("block cap hit in: ", fun.getName, " by ", block.getName);
            //writeln(fun);

            /*
            foreach (ver; versions)
            {
                writeln(block.getName);

                foreach (val, ts; ver.state.typeState)
                {
                    if (ts & TF_KNOWN)
                    {
                        auto type = cast(Type)(ts & TF_TYPE_MASK);
                        writeln("  ", val.getName, " => ", type);
                    }
                }
            }
            */

            // If a compatible match was found
            if (bestDiff !is size_t.max)
            {
                // Return the best match found
                return bestVer;
            }

            //writeln("producing general version for: ", block.getName);

            // Strip the state of all known types and constants
            auto genState = new CodeGenState(predState);
            genState.typeState = genState.typeState.init;
            foreach (val, allocSt; genState.allocState)
                if (allocSt & RA_CONST)
                    genState.allocState[val] = RA_STACK;

            // Ensure that the general version matches
            assert(predState.diff(genState) !is size_t.max);

            predState = genState;
        }
        
        //writeln("best ver diff: ", bestDiff, " (", versions.length, ")");

        // Create a label for this new version of the block
        auto label = new Label(block.getName().toUpper());

        // Create a new block version object using the predecessor's state
        BlockVersion ver = { block, predState, label };

        // Add the new version to the list for this block
        versionMap[block] ~= ver;

        //writefln("%s num versions: %s", block.getName(), versionMap[block].length);

        // Queue the new version to be compiled
        workList ~= ver;

        // Increment the total number of versions
        numVersions++;

        // Return the newly created block version
        return ver;
    };

    /// Get a label for a given branch edge transition
    auto genBranchEdge = delegate void(
        Assembler as,
        Label edgeLabel,
        BranchDesc branch, 
        CodeGenState predState
    )
    {
        // Copy the predecessor state
        auto succState = new CodeGenState(predState);

        // Remove information about values dead at
        // the beginning of the successor block
        succState.removeDead(liveInfo, branch.succ);

        // Map each successor phi node on the stack or in its register
        // in a way that best matches the predecessor state
        for (auto phi = branch.succ.firstPhi; phi !is null; phi = phi.next)
        {
            if (branch.pred is null || phi.hasNoUses)
                continue;

            // Get the phi argument
            auto arg = branch.getPhiArg(phi);
            assert (
                arg !is null, 
                "missing phi argument for:\n" ~
                phi.toString() ~
                "\nin block:\n" ~
                phi.block.toString()
            );

            // Get the register the phi is mapped to
            auto phiReg = regMapping[phi];
            assert (phiReg !is null);

            // If value mapped to reg isn't live, use reg
            // Note: we are querying succState here because the
            // register might be used by a phi node we just mapped
            auto regVal = succState.gpRegMap[phiReg.regNo];

            // Map the phi node to its register or stack location
            TFState allocSt;
            if (regVal is null || regVal is phi)
            {
                allocSt = RA_GPREG | phiReg.regNo;
                succState.gpRegMap[phiReg.regNo] = phi;
            }
            else
            {
                allocSt = RA_STACK;
            }
            succState.allocState[phi] = allocSt;

            // If the type of the phi argument is known
            if (succState.typeKnown(arg))
            {
                auto type = succState.getType(arg);
                auto onStack = allocSt & RA_STACK;

                // Mark the type as known
                succState.typeState[phi] = TF_KNOWN | (onStack? TF_SYNC:0) | type;
            }
            else
            {
                // The phi type is unknown
                succState.typeState.remove(phi);
            }
        }

        // Get a version of the successor matching the incoming state
        auto succVer = getBlockVersion(branch.succ, succState);
        succState = succVer.state;

        // List of moves to transition to the successor state
        Move[] moveList;

        /*
        writeln();
        writeln(branch.succ);
        */

        // For each value in the successor state
        foreach (succVal, succAS; succState.allocState)
        {
            auto succPhi = (
                (branch.pred !is null && succVal.block is branch.succ)?
                cast(PhiNode)succVal:null
            );
            auto predVal = (
                succPhi?
                branch.getPhiArg(succPhi):succVal
            );
            assert (succVal !is null);
            assert (predVal !is null);

            if (succPhi)
                as.comment(succPhi.getName ~ " = phi " ~ predVal.getName);
            else
                as.comment("move " ~ succVal.getName);

            // Get the source and destination operands for the arg word
            X86Opnd srcWordOpnd = predState.getWordOpnd(predVal, 64);
            X86Opnd dstWordOpnd = succState.getWordOpnd(succVal, 64);

            if (srcWordOpnd != dstWordOpnd)
                moveList ~= Move(dstWordOpnd, srcWordOpnd);

            // Get the source and destination operands for the phi type
            X86Opnd srcTypeOpnd = predState.getTypeOpnd(predVal);
            X86Opnd dstTypeOpnd = succState.getTypeOpnd(succVal);

            if (srcTypeOpnd != dstTypeOpnd)
                moveList ~= Move(dstTypeOpnd, srcTypeOpnd);

            // Get the predecessor and successor type states
            auto predTS = predState.typeState.get(cast(IRDstValue)predVal, 0);
            auto succTS = succState.typeState.get(succVal, 0);

            // Get the predecessor allocation state
            auto predAS = predState.allocState.get(cast(IRDstValue)predVal, 0);

            // If the successor value is a phi node
            if (succPhi)
            {
                /*
                if (fun.getName == "anon(121E6)")
                    as.printStr(succPhi.toString);
                */

                // If the phi is on the stack and the type is known,
                // write the type to the stack to keep it in sync
                if ((succAS & RA_STACK) && (succTS & TF_KNOWN))
                {
                    assert (succTS & TF_SYNC);
                    moveList ~= Move(new X86Mem(8, tspReg, succPhi.outSlot), srcTypeOpnd);
                }

                // If the phi is in a register and the type is unknown,
                // write 0 on the stack to avoid invalid references
                if (!(succAS & RA_STACK) && !(succTS & TF_KNOWN))
                {
                    moveList ~= Move(new X86Mem(64, wspReg, 8 * succPhi.outSlot), new X86Imm(0));
                }
            }
            else
            {
                // If the value wasn't before in a register, now is, and the type is unknown
                // write 0 on the stack to avoid invalid references
                if ((predTS & TF_KNOWN) && !(predTS & TF_SYNC) && (succAS & RA_GPREG) && !(succTS & TF_KNOWN))
                {
                    moveList ~= Move(new X86Mem(64, wspReg, 8 * succVal.outSlot), new X86Imm(0));
                }

                // If the type was not in sync in the predecessor and is now
                // in sync in the successor, write the type to the type stack
                if (!(predTS & TF_SYNC) && (succTS & TF_SYNC))
                {
                    moveList ~= Move(new X86Mem(8, tspReg, succVal.outSlot), srcTypeOpnd);
                }
            }
        }

        // Insert the branch edge label, if any
        if (edgeLabel !is null)
            as.addInstr(edgeLabel);

        // Execute the moves
        execMoves(as, moveList, scrRegs64[0], scrRegs64[1]);

        // Jump to the block label
        as.instr(JMP, succVer.label);
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
        auto fastLabel = new Label("ENTRY_FAST_" ~ block.getName().toUpper(), true);
        genBranchEdge(
            ol,
            fastLabel,
            new BranchDesc(null, block), 
            new CodeGenState(fun)
        );

        // Store the label for the fast entry point
        fastEntryMap[block] = fastLabel;

        return entryLabel;
    };

    /// Generate the call continuation for a given call instruction
    auto genCallCont = delegate RAEntry(
        IRInstr callInstr,
        CodeGenState callState
    )
    {
        assert (
            callInstr.opcode is &ir.ops.CALL ||
            callInstr.opcode is &ir.ops.CALL_PRIM
        );

        // Create an exported label for the continuation
        auto contLabel = new Label(
            "CONT_" ~ callInstr.block.getName.toUpper ~
            "_" ~ to!string(callContMap.length),
            true
        );

        // Generate the branch edge to the continuation block
        genBranchEdge(
            ol,
            contLabel,
            callInstr.getTarget(0), 
            //new CodeGenState(fun)
            new CodeGenState(callState)
        );

        // Create a new RAEntry object for this continuation
        auto raObject = new RAEntry;
        raObject.callInstr = callInstr;
        raObject.opcode = callInstr.opcode;
        raObject.outSlot = callInstr.outSlot;
        raObject.targets[0] = callInstr.getTarget(0);
        raObject.targets[1] = callInstr.getTarget(1);

        fun.jitRAs ~= raObject;

        // Add the label to the continuation map
        callContMap[raObject] = contLabel;

        return raObject;
    };

    // Create a code generation context
    auto ctx = new CodeGenCtx(
        interp,
        fun,
        as, 
        ol, 
        bailLabel,
        liveInfo,
        typeMap,
        regMapping,
        genBranchEdge,
        genCallCont
    );

    // Create an entry point for the function
    as.comment("Fast entry point for function " ~ fun.getName);
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
            writefln("compiling block: %s (execCount=%s)", block.getName(), block.execCount);
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
            state.spillRegs(
                ol,
                delegate bool(IRDstValue value)
                {
                    if (block.firstInstr.hasArg(value))
                        return true;

                    if (ctx.liveInfo.liveAfter(value, block.firstInstr))
                        return true;

                    return false;
                }
            );
           
            // Label for the stub visit counter
            auto STUB_CTR = new Label("STUB_CTR");

            // Set the interpreter target to the stub block
            ol.ptr(scrRegs64[0], block);
            ol.setMember!("Interp", "target")(interpReg, scrRegs64[0]);

            // Invalidate the compiled code for this function
            ol.ptr(cargRegs[0], block);
            ol.ptr(scrRegs64[0], &visitStub);
            ol.instr(jit.encodings.CALL, scrRegs64[0]);
            
            // Bailout to the interpreter
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

            //as.printStr(instr.toString());
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

    //writeln("assembling");

    // Assemble the machine code
    auto codeBlock = as.assemble();

    //writeln("assembled");

    // Store the CodeBlock pointer on the compiled function
    fun.codeBlock = codeBlock;

    // Increment the JIT compilation count for this function
    fun.jitCount++;

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

    // For each call instruction in the continuation map
    foreach (raObject, label; callContMap)
    {
        assert (raObject.targets[0] !is null);

        // Set the JIT continuation entry point
        raObject.jitCont = codeBlock.getExportAddr(label.name);
    }

    if (opts.jit_dumpasm)
    {
        writefln("%s\n", as.toString(true));
    }

    if (opts.jit_dumpinfo)
    {
        writeln("function: ", fun.getName);
        writefln("machine code bytes: %s", codeBlock.length);
        writefln("num locals: %s", fun.numLocals);
        writefln("num blocks: %s", versionMap.length);
        writefln("num versions: %s", numVersions);
        writefln("");
    }

    // Update the compilation time stat
    auto endTimeUsecs = Clock.currAppTick().usecs();
    stats.compTimeUsecs += endTimeUsecs - startTimeUsecs;

    // Update the machine code size stat
    stats.machineCodeBytes += codeBlock.length;

    // Update the block and version stats
    stats.numBlocks += versionMap.length;
    stats.numVersions += numVersions;
    foreach (block, versions; versionMap)
    {
        auto numVers = min(versions.length, opts.jit_maxvers);
        stats.numVerBlocks[numVers]++;
    }
}

/**
Visit a stub (uncompiled) basic block
*/
extern (C) void visitStub(IRBlock stubBlock)
{
    auto fun = stubBlock.fun;

    if (opts.jit_dumpinfo)
        writefln("invalidating stub in %s", fun.getName());

    // Remove entry points for this function
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        block.entryFn = null;
        block.jitEntry = null;
    }

    // Invalidate the JIT continuation points
    foreach (raObject; fun.jitRAs)
    {
        raObject.jitCont = null;
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
    /// The value is null if a register is free
    private IRDstValue[] gpRegMap;

    /// Constructor for a default/entry code generation state
    this(IRFunction fun)
    {
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

        if ((this.typeState is null && that.typeState !is null) ||
            (this.typeState !is null && that.typeState is null) ||
            (this.typeState != that.typeState))
            return false;

        if ((this.allocState is null && that.allocState !is null) ||
            (this.allocState !is null && that.allocState is null) ||
            (this.allocState != that.allocState))
            return false;

        if (this.gpRegMap != that.gpRegMap)
            return false;

        return true;
    }

    /**
    Compute the difference (similarity) between this state and another
    - If states are identical, 0 will be returned
    - If states are incompatible, size_t.max will be returned
    */
    size_t diff(CodeGenState succ)
    {
        auto pred = this;

        // Difference (penalty) sum
        size_t diff = 0;

        // For each value in the predecessor alloc state map
        foreach (value, allocSt; pred.allocState)
        {
            // If this value is not in the successor state,
            // mark it as on the stack in the successor state
            if (value !in succ.allocState)
                succ.allocState[value] = RA_STACK;
        }

        // For each value in the successor alloc state map
        foreach (value, allocSt; succ.allocState)
        {
            auto predAS = pred.allocState.get(value, 0);
            auto succAS = succ.allocState.get(value, 0);

            // If the alloc states match perfectly, no penalty
            if (predAS is succAS)
                continue;

            // If the successor has this value as a known constant, mismatch
            if (succAS & RA_CONST)
                return size_t.max;

            // Add a penalty for the mismatched alloc state
            diff += 1;
        }

        // For each value in the predecessor type state map
        foreach (value, allocSt; pred.typeState)
        {
            // If this value is not in the successor state,
            // add an entry for it in the successor state
            if (value !in succ.typeState)
                succ.typeState[value] = 0;
        }

        // For each value in the successor type state map
        foreach (value, allocSt; succ.typeState)
        {
            auto predTS = pred.typeState.get(value, 0);
            auto succTS = succ.typeState.get(value, 0);

            // If the type states match perfectly, no penalty
            if (predTS is succTS)
                continue;

            // If the successor has a known type
            if (succTS & TF_KNOWN)
            {
                // If the predecessor has no known type, mismatch
                if (!(predTS & TF_KNOWN))
                    return size_t.max;

                auto predType = predTS & TF_TYPE_MASK;
                auto succType = succTS & TF_TYPE_MASK;

                // If the known types do not match, mismatch
                if (predType !is succType)
                    return size_t.max;

                // If the type sync flags do not match, add a penalty
                if ((predTS & TF_SYNC) !is (succTS & TF_SYNC))
                    diff += 1;
            }
            else 
            {
                // If the predecessor has a known type, transitioning
                // would lose us this known type
                if (predTS & TF_KNOWN)
                    diff += 1;
            }
        }

        // Return the total difference
        return diff;
    }

    /**
    Get an operand for any IR value without allocating a register.
    */
    X86Opnd getWordOpnd(IRValue value, size_t numBits)
    {
        assert (
            value !is null, 
            "cannot get operand for null value"
        );

        auto dstVal = cast(IRDstValue)value;

        // Get the current alloc flags for the argument
        auto flags = allocState.get(dstVal, 0);

        // If the argument is a known constant
        if (flags & RA_CONST || dstVal is null)
        {
            auto word = getWord(value);

            if (numBits is 8)
                return new X86Imm(word.int8Val);
            if (numBits is 32)
                return new X86Imm(word.int32Val);
            return new X86Imm(getWord(value).int64Val);
        }

        // If the argument already is in a general-purpose register
        if (flags & RA_GPREG)
        {
            auto regNo = flags & RA_REG_MASK;
            return new X86Reg(X86Reg.GP, regNo, numBits);
        }

        // Return the stack operand for the argument
        return new X86Mem(numBits, wspReg, 8 * dstVal.outSlot);
    }

    /**
    Get the word operand for an instruction argument,
    allocating a register when possible.
    - If tmpReg is supplied, memory operands will be loaded in the tmpReg
    - If acceptImm is false, constant operants will be loaded into tmpReg
    - If loadVal is false, memory operands will not be loaded
    */
    X86Opnd getWordOpnd(
        CodeGenCtx ctx, 
        Assembler as, 
        IRInstr instr, 
        size_t argIdx,
        size_t numBits,
        X86Reg tmpReg = null,
        bool acceptImm = false,
        bool loadVal = true
    )
    {
        assert (instr !is null);

        assert (
            argIdx < instr.numArgs,
            "invalid argument index"
        );

        // Get the IR value for the argument
        auto argVal = instr.getArg(argIdx);
        auto dstVal = cast(IRDstValue)argVal;

        /// Allocate a register for the argument
        X86Opnd allocReg()
        {
            assert (
                dstVal !is null,
                "cannot allocate register for constant IR value: " ~
                argVal.toString()
            );

            // Get the assigned register for the argument
            auto reg = ctx.regMapping[dstVal];

            // Get the value mapped to this register
            auto regVal = gpRegMap[reg.regNo];

            // If the register is mapped to a value
            if (regVal !is null)
            {
                // If the mapped slot belongs to another instruction argument
                for (size_t otherIdx = 0; otherIdx < instr.numArgs; ++otherIdx)
                {
                    if (otherIdx != argIdx && regVal is instr.getArg(otherIdx))
                    {
                        // Map the argument to its stack location
                        allocState[dstVal] = RA_STACK;
                        return new X86Mem(numBits, wspReg, 8 * dstVal.outSlot);
                    }
                }

                // If the currently mapped value is live, spill it
                if (ctx.liveInfo.liveAfter(regVal, instr))
                    spillReg(as, reg.regNo);
                else
                    allocState.remove(regVal);
            }

            // Load the value into the register 
            // note: all 64 bits of it, not just the requested bits
            as.instr(MOV, reg, getWordOpnd(argVal, 64));

            // Map the argument to the register
            allocState[dstVal] = RA_GPREG | reg.regNo;
            gpRegMap[reg.regNo] = dstVal;
            return new X86Reg(X86Reg.GP, reg.regNo, numBits);
        }

        // Get the current operand for the argument value
        auto curOpnd = getWordOpnd(argVal, numBits);

        // If the argument is already in a register
        if (auto regOpnd = cast(X86Reg)curOpnd)
        {
            return regOpnd;
        }

        // If the operand is immediate
        if (auto immOpnd = cast(X86Imm)curOpnd)
        {
            if (acceptImm && immOpnd.immSize <= 32)
            {
                return immOpnd;
            }

            assert (
                tmpReg !is null,
                "immediates not accepted but no tmpReg supplied:\n" ~
                instr.toString()
            );

            if (tmpReg.type is X86Reg.GP)
            {
                as.instr(MOV, tmpReg, immOpnd);
                return tmpReg;
            }

            if (tmpReg.type is X86Reg.XMM)
            {
                auto cstLabel = ctx.ol.label("FP_CONST");
                ctx.ol.addInstr(new IntData(immOpnd.imm, 64));
                as.instr(MOVQ, tmpReg, new X86IPRel(64, cstLabel));
                return tmpReg;
            }            

            assert (
                false,
                "unhandled immediate"
            );
        }

        // If the operand is a memory location
        if (auto memOpnd = cast(X86Mem)curOpnd)
        {
            // TODO: only allocate a register if more than one use?            

            // Try to allocate a register for the operand
            auto opnd = loadVal? allocReg():curOpnd;

            // If the register allocation failed but a temp reg was supplied
            if (cast(X86Mem)opnd && tmpReg !is null)
            {
                as.instr(
                    (tmpReg.type == X86Reg.XMM)? MOVSD:MOV, 
                    tmpReg, 
                    curOpnd
                );

                return tmpReg;
            }

            // Return the allocated operand
            return opnd;
        }

        assert (false, "invalid cur opnd type");
    }

    /**
    Get an x86 operand for the type of any IR value
    */
    X86Opnd getTypeOpnd(IRValue value) const
    {
        assert (value !is null);

        auto dstVal = cast(IRDstValue)value;

        // If the value is an IR constant or has a known type
        if (dstVal is null || typeKnown(value) is true)
        {
            return new X86Imm(getType(value));
        }

        return new X86Mem(8, tspReg, dstVal.outSlot);
    }

    /**
    Get an x86 operand for the type of an instruction argument
    */
    X86Opnd getTypeOpnd(
        Assembler as,
        IRInstr instr,
        size_t argIdx,
        X86Reg tmpReg8 = null,
        bool acceptImm = false
    ) const
    {
        assert (instr !is null);

        assert (
            argIdx < instr.numArgs,
            "invalid argument index"
        );

        auto argVal = instr.getArg(argIdx);

        // Get an operand for the argument value
        auto curOpnd = getTypeOpnd(argVal);

        if (acceptImm is true)
        {
            if (cast(X86Imm)curOpnd)
                return curOpnd;
        }

        if (tmpReg8 !is null)
        {
            as.instr(MOV, tmpReg8, curOpnd);
            return tmpReg8;
        }

        return curOpnd;
    }

    /// Get the operand for an instruction's output
    X86Opnd getOutOpnd(
        CodeGenCtx ctx, 
        Assembler as, 
        IRInstr instr, 
        uint16_t numBits
    )
    {
        assert (instr !is null);

        assert (
            instr in ctx.regMapping,
            "no reg mapping for instr:\n" ~ 
            instr.toString() ~
            (instr.hasNoUses? " (no uses)":"")
        );

        // Get the assigned register for this instruction
        auto reg = ctx.regMapping[instr];

        // Get the value mapped to this register
        auto regVal = gpRegMap[reg.regNo];

        // If another slot is using the register
        if (regVal !is null && regVal !is instr)
        {
            // If an instruction argument is using this slot
            for (size_t argIdx = 0; argIdx < instr.numArgs; ++argIdx)
            {
                if (regVal is instr.getArg(argIdx))
                {
                    // Map the output slot to its stack location
                    allocState[instr] = RA_STACK;
                    return new X86Mem(numBits, wspReg, 8 * instr.outSlot);
                }
            }

            // If the value is live, spill it
            if (ctx.liveInfo.liveAfter(regVal, instr) is true)
                spillReg(as, reg.regNo);
            else
                allocState.remove(regVal);
        }

        // Map the instruction to the register
        allocState[instr] = RA_GPREG | reg.regNo;
        gpRegMap[reg.regNo] = instr;
        return new X86Reg(X86Reg.GP, reg.regNo, numBits);
    }

    /// Set the output of an instruction to a known boolean value
    void setOutBool(IRInstr instr, bool val)
    {
        assert (instr !is null);

        // Mark this as being a known constant
        allocState[instr] = RA_CONST;

        // Set the output type
        setOutType(null, instr, Type.CONST);

        // Store the boolean constant in the type flags
        typeState[instr] |= val? TF_BOOL_TRUE:TF_BOOL_FALSE;
    }

    /// Test if a constant word value is known for a given value
    bool wordKnown(IRValue value) const
    {
        assert (value !is null);

        auto dstValue = cast(IRDstValue)value;

        if (dstValue is null)
            return true;

        return (allocState.get(dstValue, 0) & RA_CONST) != 0;
    }

    /// Get the word value for a known constant local
    Word getWord(IRValue value)
    {
        assert (value !is null);

        auto dstValue = cast(IRDstValue)value;

        if (dstValue is null)
            return value.cstValue.word;

        auto allocSt = allocState[dstValue];
        auto typeSt = typeState[dstValue];

        assert (allocSt & RA_CONST);

        if (typeSt & TF_BOOL_TRUE)
            return TRUE;
        else if (typeSt & TF_BOOL_FALSE)
            return FALSE;
        else
            assert (false, "unknown constant");
    }

    /// Set a known type for a given value
    void setKnownType(IRDstValue value, Type type)
    {
        assert (
            (type & TF_TYPE_MASK) == type,
            "type mask corrupts type tag"
        );

        auto prevState = typeState.get(value, 0);

        assert (
            (prevState & TF_KNOWN) == 0,
            "cannot set known type, type already known"
        );

        // Set the type known flag and update the type
        typeState[value] = TF_KNOWN | TF_SYNC | type;
    }

    /// Set the output type value for an instruction's output
    void setOutType(Assembler as, IRInstr instr, Type type)
    {
        assert (
            instr !is null,
            "null instruction"
        );

        assert (
            (type & TF_TYPE_MASK) == type,
            "type mask corrupts type tag"
        );

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
        assert (
            instr !is null,
            "null instruction"
        );

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
    bool typeKnown(IRValue value) const
    {
        assert (value !is null);

        auto dstValue = cast(IRDstValue)value;

        if (dstValue is null)
            return true;

        return (typeState.get(dstValue, 0) & TF_KNOWN) != 0;
    }

    /// Get the known type of a value
    Type getType(IRValue value) const
    {
        assert (value !is null);

        auto dstValue = cast(IRDstValue)value;

        if (dstValue is null)
            return value.cstValue.type;

        auto typeState = typeState.get(dstValue, 0);

        assert (
            typeState & TF_KNOWN,
            "type is unknown"
        );

        return cast(Type)(typeState & TF_TYPE_MASK);
    }

    /// Mark a value as being stored on the stack
    void valOnStack(IRDstValue value)
    {
        assert (value !is null);

        // Get the current allocation state for this value
        auto allocSt = allocState.get(value, 0);

        // If the value is currently mapped to a register
        if (allocSt & RA_GPREG)
        {
            writeln("marking reg free");

            // Mark the register as free
            auto regNo = allocSt & RA_REG_MASK;
            gpRegMap[regNo] = null;
        }

        // Mark the value as being on the stack
        allocState[value] = RA_STACK;

        // Mark the type of this value as unknown
        typeState.remove(value);
    }

    /// Spill test function
    alias bool delegate(IRDstValue value) SpillTestFn;

    /**
    Spill registers to the stack
    */
    void spillRegs(Assembler as, SpillTestFn spillTest = null)
    {
        // For each general-purpose register
        foreach (regNo, value; gpRegMap)
        {
            // If nothing is mapped to this register, skip it
            if (value is null)
                continue;

            // If the value should be spilled, spill it
            if (spillTest is null || spillTest(value) == true)
                spillReg(as, regNo);
        }

        //writefln("spilling consts");

        // For each value
        foreach (value, allocSt; allocState)
        {
            // If this is a known constant
            if (allocSt & RA_CONST)          
            {
                // If the value should be spilled
                if (spillTest is null || spillTest(value) == true)
                {
                    // Spill the constant value to the stack
                    as.comment("Spilling constant value of " ~ value.toString());

                    auto word = getWord(value);
                    as.setWord(value.outSlot, word.int32Val);

                    auto typeSt = typeState.get(value, 0);
                    assert (typeSt & TF_KNOWN);

                    // If the type flags are not in sync
                    if (!(typeSt & TF_SYNC))
                    {
                        // Write the type tag to the type stack
                        as.comment("Spilling type for " ~ value.toString());
                        auto type = cast(Type)(typeSt & TF_TYPE_MASK);
                        as.setType(value.outSlot, type);
                    }
                }
            }
        }

        //writefln("done spilling consts");
    }

    /// Spill a specific register to the stack
    void spillReg(Assembler as, size_t regNo)
    {
        // Get the value mapped to this register
        auto regVal = gpRegMap[regNo];

        // If no value is mapped to this register, stop
        if (regVal is null)
            return;

        assert (
            allocState.get(regVal, 0) & RA_GPREG,
            "value not mapped to reg to be spilled"
        );

        auto mem = new X86Mem(64, wspReg, 8 * regVal.outSlot);
        auto reg = new X86Reg(X86Reg.GP, regNo, 64);

        //writefln("spilling: %s (%s)", regVal.toString(), reg);

        // Spill the value currently in the register
        as.comment("Spilling " ~ regVal.toString());
        as.instr(MOV, mem, reg);

        // Mark the value as being on the stack
        allocState[regVal] = RA_STACK;

        // Mark the register as free
        gpRegMap[regNo] = null;

        // Get the type state for this local
        auto typeSt = typeState.get(regVal, 0);

        // If the type is known but not in sync
        if ((typeSt & TF_KNOWN) && !(typeSt & TF_SYNC))
        {
            // Write the type tag to the type stack
            as.comment("Spilling type for " ~ regVal.toString());
            auto type = typeSt & TF_TYPE_MASK;
            auto memOpnd = new X86Mem(8, tspReg, regVal.outSlot);
            as.instr(MOV, memOpnd, type);

            // The type state is now in sync
            typeState[regVal] |= TF_SYNC;
        }
    }

    /**
    Remove information about values dead at the beginning of
    a given block
    */
    void removeDead(LiveInfo liveInfo, IRBlock block)
    {
        // For each general-purpose register
        foreach (regNo, value; gpRegMap)
        {
            // If nothing is mapped to this register, skip it
            if (value is null)
                continue;

            // If the value is no longer live, remove it
            if (liveInfo.liveAtEntry(value, block) is false)
            {
                gpRegMap[regNo] = null;
                allocState.remove(value);
                typeState.remove(value);
            }
        }

        // Remove dead values from the alloc state
        foreach (value; allocState.keys)
        {
            if (liveInfo.liveAtEntry(value, block) is false)
                allocState.remove(value);
        }

        // Remove dead values from the type state
        foreach (value; typeState.keys)
        {
            if (liveInfo.liveAtEntry(value, block) is false)
                typeState.remove(value);
        }
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

    /// Liveness information for the function
    LiveInfo liveInfo;

    /// Type analysis results for the function
    TypeMap typeMap;

    /// Register mapping (slots->regs)
    RegMapping regMapping;

    /// Function to get the label for a given branch edge
    alias void delegate(Assembler as, Label edgeLabel, BranchDesc, CodeGenState) BranchEdgeFn;
    BranchEdgeFn genBranchEdge;

    /// Function to generate a call instruction continuation
    alias RAEntry delegate(IRInstr, CodeGenState) CallContFn;
    CallContFn genCallCont;

    this(
        Interp interp,
        IRFunction fun,
        Assembler as,
        Assembler ol,
        Label bailLabel,
        LiveInfo liveInfo,
        TypeMap typeMap,
        RegMapping regMapping,
        BranchEdgeFn genBranchEdge,
        CallContFn genCallCont,
    )
    {
        this.interp = interp;
        this.fun = fun;
        this.as = as;
        this.ol = ol;
        this.bailLabel = bailLabel;
        this.liveInfo = liveInfo;
        this.typeMap = typeMap;
        this.regMapping = regMapping;
        this.genBranchEdge = genBranchEdge;
        this.genCallCont = genCallCont;
    }
}

/// Insert a comment in the assembly code
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
void incStatCnt(Assembler as, ulong* pCntVar, X86Reg scrReg)
{
    if (!opts.stats)
        return;

    as.ptr(scrReg, pCntVar);

    as.instr(INC, new X86Mem(8 * ulong.sizeof, RAX));
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

void checkVal(Assembler as, X86Opnd wordOpnd, X86Opnd typeOpnd, string errorStr)
{
    as.pushRegs();

    auto STR_DATA = new Label("STR_DATA");
    auto AFTER_STR = new Label("AFTER_STR");

    as.instr(JMP, AFTER_STR);
    as.addInstr(STR_DATA);
    foreach (ch; errorStr)
        as.addInstr(new IntData(cast(uint)ch, 8));    
    as.addInstr(new IntData(0, 8));
    as.addInstr(AFTER_STR);

    as.instr(MOV, cargRegs[2].ofSize(8), typeOpnd);
    as.instr(MOV, cargRegs[1], wordOpnd);
    as.instr(MOV, cargRegs[0], interpReg);
    as.instr(LEA, cargRegs[3], new X86IPRel(8, STR_DATA));

    auto checkFn = &checkValFn;
    as.ptr(scrRegs64[0], checkFn);
    as.instr(jit.encodings.CALL, scrRegs64[0]);

    as.popRegs();
}

extern (C) void checkValFn(Interp interp, Word word, Type type, char* errorStr)
{
    if (type != Type.REFPTR)
        return;

    if (interp.inFromSpace(word.ptrVal) is false)
    {
        writefln(
            "pointer not in from-space: %s\n%s",
            word.ptrVal,
            to!string(errorStr)
        );
    }
}

void printUint(Assembler as, X86Opnd opnd)
{
    assert (
        opnd !is null,
        "invalid operand in printUint"
    );

    as.pushRegs();

    as.instr(MOV, cargRegs[0], opnd);

    // Call the print function
    alias extern (C) void function(uint64_t) PrintUintFn;
    PrintUintFn printUintFn = &printUint;
    as.ptr(RAX, printUintFn);
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

void printStr(Assembler as, string str)
{
    as.comment("printStr(\"" ~ str ~ "\")");

    as.pushRegs();

    auto STR_DATA = new Label("STR_DATA");
    auto AFTER_STR = new Label("AFTER_STR");

    as.instr(JMP, AFTER_STR);
    as.addInstr(STR_DATA);
    foreach (ch; str)
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
Print a C string value. Callable from the JIT
*/
extern (C) void printStr(char* pStr)
{
    printf("%s\n", pStr);
}

