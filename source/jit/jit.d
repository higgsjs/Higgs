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
import interp.interp;
import interp.layout;
import interp.object;
import interp.string;
import interp.gc;
import jit.assembler;
import jit.x86;
import jit.moves;
import jit.ops;

/**
Context in which code is being compiled
*/
class CodeGenCtx
{
    /// Parent context (if inlined)
    CodeGenCtx parent = null;

    /// Call site inlined at (if inlined)
    IRInstr inlineSite = null;

    /// Number of extra locals (if inlined)
    size_t extraLocals = 0;

    /// Function this code belongs to
    IRFunction fun;

    /// Associated interpreter object
    Interp interp;
}




// TODO: use a struct with methods for this?
// TODO: combine allocMap + typeMap? Might be simpler!


/// Register allocation information value
alias uint16_t AllocState;
const AllocState RA_STACK = (1 << 7);
const AllocState RA_GPREG = (1 << 6);
const AllocState RA_CONST = (1 << 5);
const AllocState RA_REG_MASK = (0x0F);

// TODO: revise
// Type information value
alias uint16_t TypeState;
const TypeState TF_KNOWN = (1 << 7);
const TypeState TF_SYNC = (1 << 6);
const TypeState TF_BOOL_TRUE = (1 << 5);
const TypeState TF_BOOL_FALSE = (1 << 4);
const TypeState TF_TYPE_MASK = (0xF);





/**
Current code generation state. This includes register
allocation state and known type information.
*/
class CodeGenState
{
    /// Code generation context object
    CodeGenCtx ctx;

    // TODO: use X86Opnd directly for this? That would be bigger
    /// Live value to register/slot mapping
    private AllocState[IRDstValue] allocMap;

    // Live value to known type info mapping
    private TypeState[IRDstValue] typeMap;

    /// Map of general-purpose registers to values
    /// The value is null if a register is free
    private IRDstValue[] gpRegMap;

    /// Map of stack slots to values
    private IRDstValue[LocalIdx] slotMap;

    // TODO
    /// List of delayed value writes

    // TODO
    /// List of delayed type tag writes

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
        // TODO
        this.allocMap = that.allocMap.dup;
        this.typeMap = that.typeMap.dup;
        this.gpRegMap = that.gpRegMap.dup;
        this.slotMap = that.slotMap.dup;
    }

    /**
    Remove information about values dead at the beginning of
    a given block
    */
    void removeDead(LiveInfo liveInfo, IRBlock block)
    {
        // TODO
        /*
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
        */
    }
}

/**
Base class for basic block versions
*/
abstract class BlockVersion
{
    /// Maximum number of branch targets
    static const size_t MAX_TARGETS = 2;

    // Associated block
    IRBlock block;

    /// Code generation state at block entry
    CodeGenState state;

    /// Starting index in the executable code block
    size_t startIdx = size_t.max;
}

/**
Stubbed block version
*/
class VersionStub : BlockVersion
{
    // Compiled instance (initially null, non-null if stub patched)
    VersionInst inst = null;

    this(IRBlock block, CodeGenState state)
    {
        this.block = block;
        this.state = state;
    }
}

/**
Compiled block version instance
*/
class VersionInst : BlockVersion
{
    // TODO: final branch descriptors (see Assembler object)
    //branch descs, move code idxs

    // TODO: move code idxs

    // TODO: target BlockVersions
    BlockVersion targets[MAX_TARGETS];

    this(IRBlock block, CodeGenState state)
    {
        this.block = block;
        this.state = state;
    }

    /// Get a pointer to the executable code for this block
    auto getCodePtr(ExecBlock cb)
    {
        return cb.getAddress(startIdx);
    }
}

/**
Get a label for a given block and incoming state
*/
BlockVersion getBlockVersion(
    IRBlock block, 
    CodeGenState state, 
    bool noStub
)
{
    auto interp = state.ctx.interp;

    /*
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
        //writeln("block cap hit: ", versions.length);

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
    */

    // TODO
    return null;
}

/**
Generate moves for a given branch edge transition
*/
void genBranchEdge(
    //Assembler as,
    //Label edgeLabel,
    BranchEdge branch, 
    CodeGenState predState,
    bool noStub
)
{
    auto liveInfo = predState.ctx.fun.liveInfo;

    // Copy the predecessor state
    auto succState = new CodeGenState(predState);

    // Remove information about values dead at
    // the beginning of the successor block
    succState.removeDead(liveInfo, branch.target);

    /*
    // Map each successor phi node on the stack or in its register
    // in a way that best matches the predecessor state
    for (auto phi = branch.target.firstPhi; phi !is null; phi = phi.next)
    {
        if (branch.branch is null || phi.hasNoUses)
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
    */

    // Get a version of the successor matching the incoming state
    auto succVer = getBlockVersion(branch.target, succState, noStub);
    succState = succVer.state;

    // List of moves to transition to the successor state
    Move[] moveList;

    /*
    // For each value in the successor state
    foreach (succVal, succAS; succState.allocState)
    {
        auto succPhi = (
            (branch.branch !is null && succVal.block is branch.target)?
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

    // Execute the moves
    execMoves(as, moveList, scrRegs64[0], scrRegs64[1]);
    */
}

/**
Compile a basic block version instance
*/
extern (C) const (ubyte*) compile(IRBlock block, CodeGenState state)
{
    auto interp = state.ctx.interp;
    auto fun = state.ctx.fun;

    // Create a version instance for the first version to compile
    VersionInst startInst = new VersionInst(block, state);

    // Add the version to the compilation queue
    VersionInst[] compQueue = [startInst];

    // Until the compilation queue is empty
    while (compQueue.length > 0)
    {






        // TODO: finalize blocks into execHeap as they are compiled
        //interp.execHeap
    }

    // Return the address of the first version compiled
    return startInst.getCodePtr(/*TODO*/null);
}









/*
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
*/

/// Save caller-save registers on the stack before a C call
void pushRegs(ASMBlock as)
{
    as.push(RAX);
    as.push(RCX);
    as.push(RDX);
    as.push(RSI);
    as.push(RDI);
    as.push(R8);
    as.push(R9);
    as.push(R10);
    as.push(R11);
    as.push(R11);
}

/// Restore caller-save registers from the after before a C call
void popRegs(ASMBlock as)
{
    as.pop(R11);
    as.pop(R11);
    as.pop(R10);
    as.pop(R9);
    as.pop(R8);
    as.pop(RDI);
    as.pop(RSI);
    as.pop(RDX);
    as.pop(RCX);
    as.pop(RAX);
}

/*
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
*/

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

/*
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
*/

/**
Print an unsigned integer value. Callable from the JIT
*/
extern (C) void printUint(uint64_t v)
{
    writefln("%s", v);
}

/*
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
*/

/**
Print a C string value. Callable from the JIT
*/
extern (C) void printStr(char* pStr)
{
    printf("%s\n", pStr);
}

