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
import std.typecons;
import options;
import ir.ir;
import ir.livevars;
import interp.interp;
import interp.layout;
import interp.object;
import interp.string;
import interp.gc;
import jit.codeblock;
import jit.x86;
import jit.moves;
import jit.ops;

/// R15: interpreter object pointer (C callee-save) 
alias R15 interpReg;

/// R14: word stack pointer (C callee-save)
alias R14 wspReg;

/// R13: type stack pointer (C callee-save)
alias R13 tspReg;

// RSP: C stack pointer (used for C calls only)
alias RSP cspReg;

/// C argument registers
immutable X86Reg[] cargRegs = [RDI, RSI, RDX, RCX, R8, R9];

/// C fp argument registers
immutable X86Reg[] cfpArgRegs = [XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7];

/// RAX: scratch register, C return value
/// RDI: scratch register, first C argument register
/// RSI: scratch register, second C argument register
immutable X86Reg[] scrRegs = [RAX, RDI, RSI];

/// RCX, RBX, RBP, R8-R12: 9 allocatable registers
immutable X86Reg[] allocRegs = [RCX, RDX, RBX, RBP, R8, R9, R10, R11, R12];

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

    /// Associated interpreter object
    Interp interp;

    /// Function this code belongs to
    IRFunction fun;

    this(Interp interp, IRFunction fun)
    {
        this.interp = interp;
        this.fun = fun;
    }
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
    this(CodeGenCtx ctx)
    {
        this.ctx = ctx;

        // All registers are initially free
        gpRegMap.length = 16;
        for (size_t i = 0; i < gpRegMap.length; ++i)
            gpRegMap[i] = null;
    }

    /// Copy constructor
    this(CodeGenState that)
    {
        // TODO
        this.ctx = that.ctx;
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

        // TODO
        /*
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
        */

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

        // TODO
        /*
        // Get the current alloc flags for the argument
        auto flags = allocState.get(dstVal, 0);
        */

        // If the argument is a known constant
        if (/*flags & RA_CONST ||*/ dstVal is null)
        {
            auto word = getWord(value);

            if (numBits is 8)
                return X86Opnd(word.int8Val);
            if (numBits is 32)
                return X86Opnd(word.int32Val);
            return X86Opnd(getWord(value).int64Val);
        }

        /*
        // If the argument already is in a general-purpose register
        if (flags & RA_GPREG)
        {
            auto regNo = flags & RA_REG_MASK;
            return new X86Reg(X86Reg.GP, regNo, numBits);
        }
        */

        // Return the stack operand for the argument
        return X86Opnd(numBits, wspReg, 8 * dstVal.outSlot);
    }

    /**
    Get the word operand for an instruction argument,
    allocating a register when possible.
    - If tmpReg is supplied, memory operands will be loaded in the tmpReg
    - If acceptImm is false, constant operants will be loaded into tmpReg
    - If loadVal is false, memory operands will not be loaded
    */
    X86Opnd getWordOpnd(
        CodeBlock as,
        IRInstr instr, 
        size_t argIdx,
        size_t numBits,
        X86Opnd tmpReg = X86Opnd.NONE,
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

        /*
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
        */

        // Get the current operand for the argument value
        auto curOpnd = getWordOpnd(argVal, numBits);

        // If the argument is already in a register
        if (curOpnd.isReg)
        {
            return curOpnd;
        }

        // If the operand is immediate
        if (curOpnd.isImm)
        {
            if (acceptImm && curOpnd.imm.immSize <= 32)
            {
                return curOpnd;
            }

            assert (
                !tmpReg.isNone,
                "immediates not accepted but no tmpReg supplied:\n" ~
                instr.toString()
            );

            if (tmpReg.isGPR)
            {
                as.mov(tmpReg.reg, curOpnd.imm);
                return tmpReg;
            }

            if (tmpReg.isXMM)
            {
                // FIXME
                assert (false);
                /*
                auto cstLabel = ctx.ol.label("FP_CONST");
                ctx.ol.addInstr(new IntData(immOpnd.imm, 64));
                as.instr(MOVQ, tmpReg, new X86IPRel(64, cstLabel));
                return tmpReg;
                */
            }            

            assert (
                false,
                "unhandled immediate"
            );
        }

        // If the operand is a memory location
        if (curOpnd.isMem)
        {
            // TODO: only allocate a register if more than one use?            

            // TODO
            // Try to allocate a register for the operand
            auto opnd = /*loadVal? allocReg():*/curOpnd;

            // If the register allocation failed but a temp reg was supplied
            if (opnd.isMem && !tmpReg.isNone)
            {
                if (tmpReg.isXMM)
                    as.movsd(tmpReg, curOpnd);
                else
                    as.mov(tmpReg, curOpnd);

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
        if (dstVal is null /*|| typeKnown(value) is true*/)
        {
            return X86Opnd(getType(value));
        }

        return X86Opnd(8, tspReg, dstVal.outSlot);
    }

    /**
    Get an x86 operand for the type of an instruction argument
    */
    X86Opnd getTypeOpnd(
        CodeBlock as,
        IRInstr instr,
        size_t argIdx,
        X86Opnd tmpReg8 = X86Opnd.NONE,
        bool acceptImm = false
    ) const
    {
        assert (instr !is null);

        assert (
            argIdx < instr.numArgs,
            "invalid argument index"
        );

        // Get an operand for the argument value
        auto argVal = instr.getArg(argIdx);
        auto curOpnd = getTypeOpnd(argVal);

        if (acceptImm is true && curOpnd.isImm)
        {
            return curOpnd;
        }

        if (!tmpReg8.isNone)
        {
            assert (tmpReg8.reg.size is 8);
            as.mov(tmpReg8, curOpnd);
            return tmpReg8;
        }

        return curOpnd;
    }

    /// Get the operand for an instruction's output
    X86Opnd getOutOpnd(
        CodeBlock as, 
        IRInstr instr, 
        uint16_t numBits
    )
    {
        assert (instr !is null);

        auto opnd = getWordOpnd(instr, numBits);
        assert (opnd.isMem);
        return opnd;

        // TODO
        /*
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
        */
    }

    /// Get the word value for a known constant local
    Word getWord(IRValue value) const
    {
        assert (value !is null);

        auto dstValue = cast(IRDstValue)value;

        if (dstValue is null)
            return value.cstValue.word;

        // TODO
        assert (false);
        /*
        auto allocSt = allocState[dstValue];
        auto typeSt = typeState[dstValue];

        assert (allocSt & RA_CONST);

        if (typeSt & TF_BOOL_TRUE)
            return TRUE;
        else if (typeSt & TF_BOOL_FALSE)
            return FALSE;
        else
            assert (false, "unknown constant");
        */
    }

    /// Get the known type of a value
    Type getType(IRValue value) const
    {
        assert (value !is null);

        auto dstValue = cast(IRDstValue)value;

        if (dstValue is null)
            return value.cstValue.type;

        // TODO
        assert (false);
        /*
        auto typeState = typeState.get(dstValue, 0);

        assert (
            typeState & TF_KNOWN,
            "type is unknown"
        );

        return cast(Type)(typeState & TF_TYPE_MASK);
        */
    }

    /// Write the output type for an instruction's output to the type stack
    void setOutType(CodeBlock as, IRInstr instr, X86Reg typeReg)
    {
        assert (
            instr !is null,
            "null instruction"
        );

        // TODO
        // Mark the type value as unknown
        //typeState.remove(instr);

        // Write the type to the type stack
        as.mov(X86Opnd(8, tspReg, instr.outSlot), X86Opnd(typeReg));

        // TODO
        // If the output is mapped to a register, write a 0 value
        // to the word stack to avoid invalid references
        //if (allocState.get(instr, 0) & RA_GPREG)
        //    as.instr(MOV, new X86Mem(64, wspReg, 8 * instr.outSlot), 0);
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
    uint32_t startIdx = uint32_t.max;
}

/// Version reference tuple
alias Tuple!(size_t, "pos", BlockVersion, "ver") VersionRef;

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

/// Branch test type enum
enum BranchTest
{
    ILT,
    ILE,
    IGT,
    IGE,
    IEQ,
    INE,
    FLT,
    FLE,
    FGT,
    FGE,
    FEQ,
    FNE,
    NONE
}

/**
Compiled block version instance
*/
class VersionInst : BlockVersion
{
    /// Final branch test type
    BranchTest branchTest = BranchTest.NONE;

    /// Branch test operands
    X86Opnd testOpnds[2];

    // Target block versions (may be stubs)
    BlockVersion targets[MAX_TARGETS];

    /// Inner code length
    uint32_t codeLen;

    /// Move code indices
    uint32_t moveIdx[MAX_TARGETS];

    /// Move code length
    uint32_t moveLen[MAX_TARGETS];

    this(IRBlock block, CodeGenState state)
    {
        this.block = block;
        this.state = state;
    }

    /// Get a pointer to the executable code for this block
    auto getCodePtr(CodeBlock cb)
    {
        return cb.getAddress(startIdx);
    }

    /// Set the parameters for the final branch
    void setBranch(
        BranchTest test,
        X86Opnd opnd0,
        X86Opnd opnd1,
        BlockVersion target0,
        BlockVersion target1
    )
    {
        assert (targets[0] is null);

        branchTest = test;
        testOpnds[0] = opnd0;
        testOpnds[1] = opnd1;
        targets[0] = target0;
        targets[1] = target1;
    }
}

/**
Get a label for a given block and incoming state
*/
BlockVersion getBlockVersion(
    IRBlock block, 
    CodeGenState state,
    bool noStub,
    BlockVersion[]* compQueue
)
{
    auto interp = state.ctx.interp;

    // Get the list of versions for this block
    auto versions = interp.versionMap.get(block, []);

    // Best version found
    BlockVersion bestVer;
    size_t bestDiff = size_t.max;

    // For each successor version available
    foreach (ver; versions)
    {
        // Compute the difference with the incoming state
        auto diff = state.diff(ver.state);

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
        if (bestDiff < size_t.max)
        {
            // Return the best match found
            return bestVer;
        }

        //writeln("producing general version for: ", block.getName);

        // Strip the state of all known types and constants
        auto genState = new CodeGenState(state);

        // TODO
        /*        
        genState.typeState = genState.typeState.init;
        foreach (val, allocSt; genState.allocState)
            if (allocSt & RA_CONST)
                genState.allocState[val] = RA_STACK;
        */

        // Ensure that the general version matches
        assert(state.diff(genState) !is size_t.max);

        state = genState;
    }
    
    //writeln("best ver diff: ", bestDiff, " (", versions.length, ")");

    // Create a new block version object using the predecessor's state
    BlockVersion ver = (
        noStub? 
        new VersionInst(block, state):
        new VersionStub(block, state)
    );

    // Add the new version to the list for this block
    interp.versionMap[block] ~= ver;

    // Queue the new version to be compiled
    *compQueue ~= ver;

    // Return the newly created block version
    return ver;
}

/**
Generate moves for a given branch edge transition
*/
BlockVersion genBranchEdge(
    CodeBlock as,
    BranchEdge branch,
    CodeGenState predState,
    bool noStub,
    BlockVersion[]* compQueue 
)
{
    auto liveInfo = predState.ctx.fun.liveInfo;

    // Copy the predecessor state
    auto succState = new CodeGenState(predState);

    // Remove information about values dead at
    // the beginning of the successor block
    succState.removeDead(liveInfo, branch.target);

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

        /*
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
        */
    }

    // Get a version of the successor matching the incoming state
    auto succVer = getBlockVersion(
        branch.target, 
        succState, 
        noStub, 
        compQueue
    );
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
    */

    // Execute the moves
    execMoves(as, moveList, scrRegs[0], scrRegs[1]);

    // Return the successor block version
    return succVer;
}

/**
Compile a basic block version
*/
void compile(bool unitFn)(BlockVersion startVer)
{
    writeln("entering compile");

    assert (startVer !is null);

    auto state = startVer.state;
    assert (state.ctx !is null);
    auto interp = state.ctx.interp;
    assert (interp !is null);
    auto fun = state.ctx.fun;
    assert (fun !is null);

    auto as = interp.execHeap;
    assert (as !is null);

    // Add the version to the compilation queue
    BlockVersion[] compQueue = [startVer];

    // List of references to block versions
    VersionRef[] refList;

    // Until the compilation queue is empty
    while (compQueue.length > 0)
    {
        // Get a version to compile from the queue
        auto ver = compQueue.front;
        compQueue.popFront();

        // Note the code start index for this version
        static if (unitFn is false)
           ver.startIdx = cast(uint32_t)as.getWritePos();

        // If this is a version stub
        if (auto stub = cast(VersionStub)ver)
        {
            writeln("compiling stub");

            // Insert the label for this block in the out of line code
            as.comment("Block stub for " ~ stub.block.getName());

            // TODO: properly spill registers, GC may be run during JIT

            as.pushRegs();

            // Call the JIT compile function,
            // passing it a pointer to the stub
            auto compileFn = &compileStub;
            as.ptr(RAX, compileFn);
            as.ptr(cargRegs[0], stub);
            as.call(X86Opnd(RAX));

            as.popRegs();

            // Jump to the compiled stub
            as.jmp(X86Opnd(RAX));
        }
        else
        {
            writeln("compiling instance");

            auto inst = cast(VersionInst)ver;
            assert (inst !is null);

            // For each instruction of the block
            for (auto instr = ver.block.firstInstr; instr !is null; instr = instr.next)
            {
                writeln("compiling instr: ", instr.toString());

                as.comment(instr.toString());
                //as.printStr(instr.toString());

                auto opcode = instr.opcode;
                assert (opcode !is null);

                assert (
                    opcode.genFn !is null,
                    "no codegen function for \"" ~ instr.toString() ~ "\""
                );

                // Call the code generation function for the opcode
                opcode.genFn(
                    inst,
                    state, 
                    as,
                    &compQueue,
                    instr
                );

                // If we know the instruction will definitely leave 
                // this block, stop the block compilation
                if (opcode.isBranch)
                    break;
            }

            // Link block-internal labels
            as.linkLabels();
        }

        // TODO
        //if (opts.jit_dumpasm)
        {
           writeln(as.toString);
        }
    }

    // Link the version references
    auto startPos = as.getWritePos();
    foreach (refr; refList)
    {
        as.setWritePos(refr.pos);
        assert (refr.ver.startIdx !is size_t.max);
        auto offset = refr.ver.startIdx - (refr.pos + 4);
        as.writeInt(offset, 32);
    }
    as.setWritePos(startPos);

    writeln("leaving compile");
}

/**
Compile a block version instance for a stub
*/
extern (C) const (ubyte*) compileStub(VersionStub stub)
{
    writeln("entering compileStub");

    auto interp = stub.state.ctx.interp;
    auto execHeap = interp.execHeap;

    assert (stub.startIdx !is size_t.max);
    assert (stub.inst is null);

    // Create a version instance object for this stub
    // and set the instance pointer for the stub
    stub.inst = new VersionInst(stub.block, stub.state);

    // Compile the version instance
    compile!false(stub.inst);

    // Write a relative 32-bit jump to the stub instance over the stub
    auto startPos = execHeap.getWritePos();
    execHeap.setWritePos(stub.startIdx);
    execHeap.writeByte(0xE9);
    auto offset = stub.inst.startIdx - (execHeap.getWritePos + 4);
    execHeap.writeInt(offset, 32);
    execHeap.setWritePos(startPos);

    writeln("leaving compileStub");

    // Return the address of the instance
    return stub.inst.getCodePtr(execHeap);
}

/// Unit function entry point
alias extern (C) void function() EntryFn;

/**
Compile an entry point for a unit-level function
*/
EntryFn compileUnit(Interp interp, IRFunction fun)
{
    assert (fun.isUnit);

    auto as = interp.execHeap;

    // Create a version instance object for the function entry
    auto entryInst = new VersionInst(
        fun.entryBlock, 
        new CodeGenState(
            new CodeGenCtx(
                interp,
                fun
            )
        )
    );

    // Note the code start index for this version
    entryInst.startIdx = cast(uint32_t)as.getWritePos();

    // Align SP to a multiple of 16 bytes
    as.sub(X86Opnd(RSP), X86Opnd(8));

    // Save the callee-save GP registers
    as.push(RBX);
    as.push(RBP);
    as.push(R12);
    as.push(R13);
    as.push(R14);
    as.push(R15);

    // Load a pointer to the interpreter object
    as.ptr(interpReg, interp);

    // Load the stack pointers into RBX and RBP
    as.getMember!("Interp.wsp")(wspReg, interpReg);
    as.getMember!("Interp.tsp")(tspReg, interpReg);

    // Compile the unit entry version
    compile!true(entryInst);

    // Return a pointer to the entry block version's code
    return cast(EntryFn)entryInst.getCodePtr(interp.execHeap);
}

/// Load a pointer constant into a register
void ptr(TPtr)(CodeBlock as, X86Reg dstReg, TPtr ptr)
{
    as.mov(X86Opnd(dstReg), X86Opnd(X86Imm(cast(void*)ptr)));
}

/// Increment a global JIT stat counter variable
void incStatCnt(CodeBlock as, ulong* pCntVar, X86Reg scrReg)
{
    if (!opts.stats)
        return;

    as.ptr(scrReg, pCntVar);

    as.inc(X86Opnd(8 * ulong.sizeof, RAX));
}

void getField(CodeBlock as, X86Reg dstReg, X86Reg baseReg, size_t fSize, size_t fOffset)
{
    as.mov(X86Opnd(dstReg), X86Opnd(8*fSize, baseReg, cast(int32_t)fOffset));
}

void setField(CodeBlock as, X86Reg baseReg, size_t fSize, size_t fOffset, X86Reg srcReg)
{
    as.mov(X86Opnd(8*fSize, baseReg, cast(int32_t)fOffset), X86Opnd(srcReg));
}

void getMember(string fName)(CodeBlock as, X86Reg dstReg, X86Reg baseReg)
{
    mixin("auto fSize = " ~ fName ~ ".sizeof;");
    mixin("auto fOffset = " ~ fName ~ ".offsetof;");

    return as.getField(dstReg, baseReg, fSize, fOffset);
}

void setMember(string fName)(CodeBlock as, X86Reg baseReg, X86Reg srcReg)
{
    mixin("auto fSize = " ~ fName ~ ".sizeof;");
    mixin("auto fOffset = " ~ fName ~ ".offsetof;");

    return as.setField(baseReg, fSize, fOffset, srcReg);
}

/*
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
void pushRegs(CodeBlock as)
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
void popRegs(CodeBlock as)
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

    as.instr(MOV, cargRegs[2].reg(8), typeOpnd);
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

void printUint(CodeBlock as, X86Opnd opnd)
{
    as.pushRegs();

    as.mov(X86Opnd(cargRegs[0]), opnd);

    // Call the print function
    alias extern (C) void function(uint64_t) PrintUintFn;
    PrintUintFn printUintFn = &printUint;
    as.ptr(RAX, printUintFn);
    as.call(X86Opnd(RAX));

    as.popRegs();
}

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

