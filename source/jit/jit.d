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
import std.bitmanip;
import options;
import ir.ir;
import ir.ast;
import ir.livevars;
import runtime.vm;
import runtime.layout;
import runtime.object;
import runtime.string;
import runtime.gc;
import jit.codeblock;
import jit.x86;
import jit.util;
import jit.moves;
import jit.ops;

/// R15: VM object pointer (C callee-save) 
alias R15 vmReg;

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

/// C return value register
alias RAX cretReg;

/// RAX: scratch register, C return value
/// RDI: scratch register, first C argument register
/// RSI: scratch register, second C argument register
immutable X86Reg[] scrRegs = [RAX, RDI, RSI];

/// RCX, RBX, RBP, R8-R12: 9 allocatable registers
immutable X86Reg[] allocRegs = [RCX, RDX, RBX, RBP, R8, R9, R10, R11, R12];

/// Return word register
alias RCX retWordReg;

/// Return type register
alias DL retTypeReg;

/// Minimum heap space required to compile a block (256KB)
const size_t JIT_MIN_BLOCK_SPACE = 1 << 18; 

/**
Type and allocation state of a live value
*/
struct ValState
{
    /// Value kind
    enum Kind
    {
        STACK,
        REG,
        CONST
    }

    /// Bit field for compact encoding
    mixin(bitfields!(

        /// Value kind
        Kind, "kind", 2,

        /// Known type flag
        bool, "knownType", 1,

        /// Type, if known
        Type, "type", 4,

        /// Local index, or register number, or constant value
        int, "val", 25,

        /// Padding bits
        uint, "", 0
    ));

    /// Stack value constructor
    static ValState stack(StackIdx idx)
    {
        ValState val;

        val.kind = Kind.STACK;
        val.knownType = false;
        val.val = cast(int)idx;

        return val;
    }

    /// Register value constructor
    static ValState reg(X86Reg reg)
    {
        ValState val;

        val.kind = Kind.STACK;
        val.knownType = false;
        val.val = reg.regNo;

        return val;
    }

    bool isStack() const { return kind is Kind.STACK; }
    bool isReg() const { return kind is Kind.REG; }
    bool isConst() const { return kind is Kind.CONST; }

    /// Get the stack slot index for this value
    StackIdx stackIdx() const
    {
        assert (isStack);
        return cast(StackIdx)val;
    }

    /// Get a word operand for this value
    X86Opnd getWordOpnd(size_t numBits) const
    {
        switch (kind)
        {
            case Kind.STACK:
            return X86Opnd(numBits, wspReg, cast(int32_t)(Word.sizeof * stackIdx));

            case Kind.REG:
            return X86Reg(X86Reg.GP, val, numBits).opnd;

            // TODO: const kind
            default:
            assert (false);
        }
    }

    /// Get a type operand for this value
    X86Opnd getTypeOpnd() const
    {
        // TODO
        assert (knownType is false);

        return X86Opnd(8, tspReg, cast(int32_t)(Type.sizeof * stackIdx));
    }
}

/**
Current code generation state. This includes register
allocation state and known type information.
*/
class CodeGenState
{
    /// Calling context object
    CallCtx callCtx;

    /// Map of live values to current type/allocation states
    private ValState[IRDstValue] valMap;

    /// Map of general-purpose registers to values
    /// If a register is free, its value is null
    private IRDstValue[] gpRegMap;

    /// Map of stack slots to values
    /// Unmapped slots have no associated value
    private IRDstValue[StackIdx] slotMap;

    // TODO
    /// List of delayed value writes

    // TODO
    /// List of delayed type tag writes

    /// Constructor for a default/entry code generation state
    this(CallCtx callCtx)
    {
        this.callCtx = callCtx;

        // All registers are initially free
        gpRegMap.length = 16;
        for (size_t i = 0; i < gpRegMap.length; ++i)
            gpRegMap[i] = null;
    }

    /// Copy constructor
    this(CodeGenState that)
    {
        this.callCtx = that.callCtx;
        this.valMap = that.valMap.dup;
        this.gpRegMap = that.gpRegMap.dup;
        this.slotMap = that.slotMap.dup;
    }

    /**
    Remove information about values dead at the beginning of
    a given block
    */
    void removeDead(LiveInfo liveInfo, IRBlock block)
    {
        // For each value in the value map
        // Note: a value being mapped to a register/slot does not mean that
        // this register/slot is necessarily mapped to that value in the
        // presence of inlined calls
        foreach (value; valMap.keys)
        {
            // If this value is not from this function, skip it
            if (value.block.fun !is block.fun)
                continue;

            if (liveInfo.liveAtEntry(value, block) is false)
                valMap.remove(value);
        }

        // For each general-purpose register
        foreach (regNo, value; gpRegMap)
        {
            // If nothing is mapped to this register, skip it
            if (value is null)
                continue;

            // If this value is not from this function, skip it
            if (value.block.fun !is block.fun)
                continue;

            // If the value is no longer live, remove it
            if (liveInfo.liveAtEntry(value, block) is false)
                gpRegMap[regNo] = null;
        }

        // For each slot for which we have an assigned value
        foreach (idx; slotMap.keys)
        {
            auto value = slotMap[idx];

            // If this value is not from this function, skip it
            if (value.block.fun !is block.fun)
                continue;

            // If the value is no longer live, remove it
            if (liveInfo.liveAtEntry(value, block) is false)
                slotMap.remove(idx);
        }
    }

    /**
    Compute the difference (similarity) between this state and another
    - If states are identical, 0 will be returned
    - If states are incompatible, size_t.max will be returned
    */
    size_t diff(CodeGenState succ)
    {
        assert (this.callCtx is succ.callCtx);

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

        // If the value is an IR constant
        if (dstVal is null)
        {
            auto word = value.cstValue.word;

            // Note: the sequence below is necessary because the 64-bit
            // value of a 32-bit negative integer is positive as the
            // higher bits are all zeros.
            if (numBits is 8)
                return X86Opnd(word.int8Val);
            if (numBits is 32)
                return X86Opnd(word.int32Val);
            else
                return X86Opnd(word.int64Val);
        }

        // Get the state for this value
        auto state = getState(dstVal);

        return state.getWordOpnd(numBits);
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
                // Write the FP constant in the code stream and load it
                as.movq(tmpReg, X86Opnd(64, RIP, 2));
                as.jmp8(8);
                as.writeInt(curOpnd.imm.imm, 64);
                return tmpReg;
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
            // should benchmark this idea

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
        if (dstVal is null)
        {
            return X86Opnd(value.cstValue.type);
        }

        // Get the state for this value
        auto state = getState(dstVal);

        return state.getTypeOpnd();
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
        size_t numBits
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

    /// Set the output type value for an instruction's output
    void setOutType(CodeBlock as, IRInstr instr, Type type)
    {
        assert (
            instr !is null,
            "null instruction"
        );

        /*
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
        */

        // Write the type value to the type stack
        as.mov(X86Opnd(8, tspReg, instr.outSlot), X86Opnd(type));
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

    /// Get the state for a given value
    auto getState(IRDstValue val) const
    {
        assert (val !is null);

        return valMap.get(
            val,
            ValState.stack(val.outSlot)
        );
    }

    /// Map a value to a specific stack location
    void mapToStack(IRDstValue val, StackIdx slotIdx)
    {
        valMap[val] = ValState.stack(slotIdx);

        // TODO: gpRegMap?

        // TODO: localMap?
    }
}

/**
Executable code fragment
*/
abstract class CodeFragment
{
    /// Start index in the executable heap
    uint32_t startIdx = uint32_t.max;

    /// End index in the executable heap
    uint32_t endIdx = uint32_t.max;

    /// Produce a string representation of this blocks's code
    final string genString(CodeBlock cb)
    {
        return cb.toString(startIdx, endIdx);
    }

    /// Get the name string for this fragment
    final string getName()
    {
        if (auto ver = cast(BlockVersion)this)
        {
            return ver.block.getName;
        }

        if (auto branch = cast(BranchCode)this)
        {
            return "branch_" ~ branch.target.block.getName;
        }

        if (auto stub = cast(EntryStub)this)
        {
            return "entry_stub_" ~ (stub.ctorCall? "ctor":"reg");
        }

        if (auto stub = cast(BranchStub)this)
        {
            return "branch_stub_" ~ to!string(stub.targetIdx);
        }

        if (auto stub = cast(ContStub)this)
        {
            return "cont_stub_" ~ stub.contBranch.getName;
        }

        if (auto exit = cast(ExitCode)this)
        {
            return "unit_exit_" ~ exit.fun.getName;
        }

        assert (false);
    }

    /// Get the length of the code fragment
    final auto length()
    {
        assert (startIdx !is startIdx.max);
        assert (ended);
        return endIdx - startIdx;
    }

    /// Get a pointer to the executable code for this version
    final auto getCodePtr(CodeBlock cb)
    {
        return cb.getAddress(startIdx);
    }

    /**
    Store the start position of the code
    */
    final void markStart(CodeBlock as, VM vm)
    {
        assert (
            startIdx is startIdx.max,
            "start position is already marked"
        );

        startIdx = cast(uint32_t)as.getWritePos();

        // Add a label string comment
        as.writeString(this.getName ~ ":");
    }

    /**
    Store the end position of the code
    */
    final void markEnd(CodeBlock as, VM vm)
    {
        assert (
            !ended,
            "end position is already marked"
        );

        endIdx = cast(uint32_t)as.getWritePos();

        // Add this fragment to the back of to the list of compiled fragments
        vm.fragList ~= this;

        // Update the generated code size stat
        stats.genCodeSize += this.length();
    }

    /**
    Check if the fragment start has been marked (fragment is instantiated)
    */
    final bool started()
    {
        return startIdx !is startIdx.max;
    }

    /**
    Check if the end of the fragment has been marked
    */
    final bool ended()
    {
        return endIdx !is endIdx.max;
    }

    /**
    Patch this code fragment to jump to a newer version
    */
    final void patch(CodeBlock as, CodeFragment next)
    {
        assert (this.started && next.started);

        // Clear the old ASM comments
        as.delStrings(startIdx, endIdx);

        // Write a relative 32-bit jump to the instance over the stub code
        auto startPos = as.getWritePos();
        as.setWritePos(this.startIdx);
        as.writeASM("jmp", next.getName);
        as.writeByte(JMP_REL32_OPCODE);
        auto offset = next.startIdx - (as.getWritePos + 4);
        as.writeInt(offset, 32);

        // Ensure that we did not overrun the code fragment length
        assert (as.getWritePos() <= this.endIdx);

        // Return to the original write position
        as.setWritePos(startPos);
    }
}

/**
Function entry stub
*/
class EntryStub : CodeFragment
{
    /// Associated VM
    VM vm;

    /// Constructor call flag
    bool ctorCall;

    this(VM vm, bool ctorCall)
    {
        this.vm = vm;
        this.ctorCall = ctorCall;
    }
}

/**
Branch target stub
*/
class BranchStub : CodeFragment
{
    /// Associated VM
    VM vm;

    /// Branch target index
    size_t targetIdx;

    this(VM vm, size_t targetIdx)
    {
        this.vm = vm;
        this.targetIdx = targetIdx;
    }
}

/**
Call continuation stub
*/
class ContStub : CodeFragment
{
    /// Block version containing the call instruction
    BlockVersion callVer;

    /// Call continuation branch
    BranchCode contBranch;

    this(BlockVersion callVer, BranchCode contBranch)
    {
        this.callVer = callVer;
        this.contBranch = contBranch;
    }
}

/**
Unit exit code
*/
class ExitCode : CodeFragment
{
    IRFunction fun;

    this(IRFunction fun)
    {
        this.fun = fun;
    }
}

/// Branch edge prelude code generation delegate
alias void delegate(
    CodeBlock as,
    VM vm
) PrelGenFn;

/**
Branch edge transition code
*/
class BranchCode : CodeFragment
{
    /// Prelude code generation function
    PrelGenFn prelGenFn;

    // List of moves to transition to the successor state
    Move[] moveList;

    /// IR branch edge object
    BranchEdge branch;

    /// Target block version (may be a stub)
    BlockVersion target;

    this(
        BranchEdge branch,
        BlockVersion target,
        PrelGenFn prelGenFn,
        Move[] moveList)
    {
        this.branch = branch;
        this.target = target;
        this.prelGenFn = prelGenFn;
        this.moveList = moveList;
    }
}

/// Branch code shape enumeration
enum BranchShape
{
    NEXT0,  // Target 0 is next
    NEXT1,  // Target 1 is next
    DEFAULT // Neither target is next
}

/// Branch code generation delegate
alias void delegate(
    CodeBlock as,
    VM vm,
    CodeFragment target0,
    CodeFragment target1,
    BranchShape shape
) BranchGenFn;

/**
Basic block version
*/
class BlockVersion : CodeFragment
{
    /// Final branch code generation function
    BranchGenFn branchGenFn;

    /// Associated block
    IRBlock block;

    /// Code generation state at block entry
    CodeGenState state;

    /// Branch targets
    CodeFragment targets[2];

    /// Inner code length, excluding final branches
    uint32_t codeLen;

    /// Execution frequency counter
    uint32_t counter;

    this(IRBlock block, CodeGenState state)
    {
        this.block = block;
        this.state = state;
    }

    /**
    Generate the final branch for the block
    */
    void genBranch(
        CodeBlock as,
        CodeFragment target0,
        CodeFragment target1,
        BranchGenFn genFn
    )
    {
        assert (started);

        auto vm = state.callCtx.vm;

        // Store the branch generation function and targets
        this.branchGenFn = genFn;
        this.targets = [target0, target1];

        // Compute the code length
        codeLen = cast(uint32_t)as.getWritePos - startIdx;

        // If this block doesn't end in a call
        if (block.lastInstr.opcode.isCall is false)
        {
            // Write the block idx in scrReg[0]
            size_t blockIdx = vm.fragList.length;
            as.mov(scrRegs[0].opnd(32), X86Opnd(blockIdx));
        }

        // Generate the final branch code
        branchGenFn(
            as,
            vm,
            target0,
            target1,
            BranchShape.DEFAULT
        );

        // Store the code end index
        markEnd(as, vm);
    }

    /**
    Rewrite the final branch of this block
    */
    void regenBranch(CodeBlock as, size_t blockIdx)
    {
        //writeln("rewriting final branch for ", block.getName);

        // Ensure that this block has already been compiled
        assert (started && ended);

        auto vm = state.callCtx.vm;

        // Move to the branch code position
        auto origPos = as.getWritePos();
        as.setWritePos(startIdx + codeLen);

        // Clear the ASM comments of the old branch code
        as.delStrings(as.getWritePos, endIdx);



        auto stub0 = (
            targets[0] &&
            !targets[0].started &&
            !vm.compQueue.canFind(targets[0])
        );
        auto stub1 = (
            targets[1] &&
            !targets[1].started &&
            !vm.compQueue.canFind(targets[1])
        );

        // If this block doesn't end in a call and at least one target is a stub
        if (!block.lastInstr.opcode.isCall && (stub0 || stub1))
        {
            // Write the block idx in scrReg[0]
            as.mov(scrRegs[0].opnd(32), X86Opnd(blockIdx));
        }

        // Determine the branch shape, whether a target is immediately next
        BranchShape shape = BranchShape.DEFAULT;
        if (targets[0])
        {
            if (targets[0].startIdx is endIdx)
                shape = BranchShape.NEXT0;
            if (endIdx is origPos &&
                vm.compQueue.length > 0 &&
                vm.compQueue.back is targets[0])
                shape = BranchShape.NEXT0;
        }
        if (targets[1])
        {
            if (targets[1].startIdx is endIdx)
                shape = BranchShape.NEXT1;
            if (endIdx is origPos &&
                vm.compQueue.length > 0 &&
                vm.compQueue.back is targets[1])
                shape = BranchShape.NEXT1;
        }

        // Generate the final branch code
        branchGenFn(
            as,
            vm,
            targets[0],
            targets[1],
            shape
        );

        // Ensure that we did not overwrite the next block
        assert (as.getWritePos <= endIdx);

        // If this is the last block in the executable heap
        if (endIdx is origPos)
        {
            // Resize the block to the current position
            endIdx = cast(uint32_t)as.getWritePos;
        }
        else
        {
            // Pad the end of the fragment with noops
            as.nop(endIdx - as.getWritePos);

            // Return to the previous write position
            as.setWritePos(origPos);
        }
    }
}

/**
Produce a string representation of the code generated for a function
*/
string asmString(IRFunction fun, CodeFragment entryFrag, CodeBlock execHeap)
{
    auto workList = [entryFrag];

    void queue(CodeFragment frag, CodeFragment target)
    {
        if (target is null || target.ended is false)
            return;

        // Don't re-visit fragments at smaller addresses
        if (target.startIdx < frag.startIdx || target is frag)
            return;

        workList ~= target;
    }

    CodeFragment[] fragList;

    while (workList.empty is false)
    {
        // Get a fragment from the work list
        auto frag = workList.back;
        workList.popBack();

        fragList ~= frag;

        if (auto branch = cast(BranchCode)frag)
        {
            queue(frag, branch.target);
        }

        if (auto cont = cast(ContStub)frag)
        {
            queue(frag, cont.contBranch);
        }

        else if (auto inst = cast(BlockVersion)frag)
        {
            queue(frag, inst.targets[0]);
            queue(frag, inst.targets[1]);
        }

        else
        {
            // Do nothing
        }
    }

    // Sort the fragment by increasing memory address
    fragList.sort!"a.startIdx < b.startIdx";

    auto str = appender!string;

    foreach (fIdx, frag; fragList)
    {
        if (frag.length is 0)
            continue;

        if (str.data != "")
            str.put("\n\n");

        str.put(frag.genString(execHeap));

        if (fIdx < fragList.length - 1)
        {
            auto next = fragList[fIdx+1];
            if (next.startIdx > frag.endIdx)
            {
                auto numBytes = next.startIdx - frag.endIdx;
                str.put(format("\n\n; ### %s byte gap ###", numBytes));
            }
        }
    }

    return str.data;
}

/**
Request a block version matching the incoming state
*/
BlockVersion getBlockVersion(
    IRBlock block,
    CodeGenState state,
    bool noStub
)
{
    auto callCtx = state.callCtx;
    auto vm = callCtx.vm;

    // Get the list of versions for this block
    auto versions = callCtx.versionMap.get(block, []);

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
        debug
        {
            writeln("version limit hit: ", versions.length);
        }

        // If a compatible match was found
        if (bestDiff < size_t.max)
        {
            // Return the best match found
            assert (bestVer.state.callCtx is callCtx);
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

        assert (genState.callCtx is callCtx);
        state = genState;
    }

    //writeln("best ver diff: ", bestDiff, " (", versions.length, ")");

    // Create a new block version object using the predecessor's state
    auto ver = new BlockVersion(block, state);

    // Add the new version to the list for this block
    callCtx.versionMap[block] ~= ver;

    // If we know this version will be executed, queue it for compilation
    if (noStub)
        vm.queue(ver);

    // Increment the total number of block versions (compiled or not)
    stats.numVersions++;

    // Return the newly created block version
    assert (ver.state.callCtx is callCtx);
    return ver;
}

/**
Request a branch edge transition matching the incoming state
*/
BranchCode getBranchEdge(
    BranchEdge branch,
    CodeGenState predState,
    bool noStub,
    PrelGenFn prelGenFn = null
)
{
    assert (
        branch !is null,
        "branch edge is null"
    );

    auto callCtx = predState.callCtx;
    auto vm = callCtx.vm;
    auto liveInfo = callCtx.fun.liveInfo;

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

        // Map the phi node to its stack location
        succState.valMap[phi] = ValState.stack(phi.outSlot);

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
        */

        /*
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
        false
    );

    // Update the successor state
    succState = succVer.state;

    // List of moves to transition to the successor state
    Move[] moveList;

    // For each value in the successor state
    foreach (succVal, succSt; succState.valMap)
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

        /*
        if (succPhi)
            as.comment(succPhi.getName ~ " = phi " ~ predVal.getName);
        else
            as.comment("move " ~ succVal.getName);
        */

        // Test if the successor value is a parameter
        // We don't need to move parameter values to the stack
        bool succParam = cast(FunParam)succVal !is null;

        // Get the source and destination operands for the arg word
        X86Opnd srcWordOpnd = predState.getWordOpnd(predVal, 64);
        X86Opnd dstWordOpnd = succState.getWordOpnd(succVal, 64);

        if (srcWordOpnd != dstWordOpnd && !(succParam && dstWordOpnd.isMem))
            moveList ~= Move(dstWordOpnd, srcWordOpnd);

        // Get the source and destination operands for the phi type
        X86Opnd srcTypeOpnd = predState.getTypeOpnd(predVal);
        X86Opnd dstTypeOpnd = succState.getTypeOpnd(succVal);

        if (srcTypeOpnd != dstTypeOpnd && !(succParam && dstTypeOpnd.isMem))
            moveList ~= Move(dstTypeOpnd, srcTypeOpnd);

        // TODO: handle delayed writes

        /*
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
        */
    }

    // Return a branch edge code object for the successor
    auto branchCode = new BranchCode(
        branch,
        succVer,
        prelGenFn,
        moveList
    );

    // If we know this will be executed, queue the branch edge for compilation
    if (noStub)
        vm.queue(branchCode);

    return branchCode;
}

/// Return address entry
alias Tuple!(
    IRInstr, "callInstr",
    CallCtx, "callCtx",
    CodeFragment, "retCode",
    CodeFragment, "excCode"
) RetEntry;

/// Fragment reference tuple
alias Tuple!(
    size_t, "pos",
    size_t, "size",
    CodeFragment, "frag",
    size_t, "targetIdx"
) FragmentRef;

/**
Add a fragment reference to the reference list
*/
void addFragRef(
    VM vm,
    size_t pos,
    size_t size,
    CodeFragment frag,
    size_t targetIdx
)
{
    vm.refList ~= FragmentRef(pos, size, frag, targetIdx);
}

/**
Queue a block version to be compiled
*/
void queue(VM vm, CodeFragment frag)
{
    //writeln("queueing: ", frag.getName);

    vm.compQueue ~= frag;
}

/**
Set the current calling context when calling host code from JITted code.
Must set the call context to null when returning from host code.
*/
void setCallCtx(VM vm, CallCtx callCtx)
{
    // Ensure proper usage
    assert (
        !(vm.callCtx !is null && callCtx !is null),
        "VM call ctx is not null: " ~
        vm.callCtx.fun.getName
    );

    vm.callCtx = callCtx;
}

/**
Set the return address entry for a call instruction
*/
void setRetEntry(
    VM vm,
    IRInstr callInstr,
    CallCtx callCtx,
    CodeFragment retCode,
    CodeFragment excCode
)
{
    auto retAddr = retCode.getCodePtr(vm.execHeap);
    vm.retAddrMap[retAddr] = RetEntry(callInstr, callCtx, retCode, excCode);
}

/**
Compile all blocks in the compile queue
*/
void compile(VM vm, CallCtx callCtx)
{
    //writeln("entering compile");

    assert (vm !is null);
    auto as = vm.execHeap;
    assert (as !is null);

    // Set the call context
    vm.setCallCtx(callCtx);

    assert (vm.compQueue.length > 0);

    // Until the compilation queue is empty
    while (vm.compQueue.length > 0)
    {
        assert (
            as.getRemSpace() >= JIT_MIN_BLOCK_SPACE,
            "insufficient space to compile version"
        );

        // Get a fragment to compile from the queue
        auto frag = vm.compQueue.back;
        vm.compQueue.popBack();

        //writeln("compiling: ", frag.getName);

        // If this is a version instance
        if (auto ver = cast(BlockVersion)frag)
        {
            //writeln("compiling instance");

            assert (
                ver.ended is false,
                "version already compiled: " ~ ver.getName
            );

            auto block = ver.block;
            assert (ver.block !is null);

            //writeln(block.toString);

            // Copy the instance's state object
            auto state = new CodeGenState(ver.state);

            // Store the code start index for this fragment
            if (ver.startIdx is ver.startIdx.max)
               ver.markStart(as, vm);

            as.comment("Instance of " ~ ver.getName());

            // For each instruction of the block
            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
            {
                if (opts.jit_dumpinfo)
                    writeln("compiling instr: ", instr.toString());

                // If we should generate disassembly strings
                if (opts.jit_genasm)
                    as.comment(instr.toString());

                //as.printStr(instr.toString());

                auto opcode = instr.opcode;
                assert (opcode !is null);

                assert (
                    opcode.genFn !is null,
                    "no codegen function for \"" ~ instr.toString() ~ "\" in " ~
                    block.fun.getName()
                );

                // Call the code generation function for the opcode
                opcode.genFn(
                    ver,
                    state,
                    instr,
                    as
                );

                // Link block-internal labels
                as.linkLabels();

                // If the end of the block was marked, skip further instructions
                if (ver.ended)
                    break;
            }

            // Ensure that the end of the fragment was marked
            assert (frag.ended, ver.block.toString);

            stats.numInsts++;
        }

        // If this is a branch code fragment
        else if (auto branch = cast(BranchCode)frag)
        {
            assert (branch.target !is null);

            // Store the code start index
            branch.markStart(as, vm);

            // Generate the prelude code, if any
            if (branch.prelGenFn)
                branch.prelGenFn(as, vm);

            // Execute the moves
            execMoves(as, branch.moveList, scrRegs[0], scrRegs[1]);

            // If the target is already compiled
            if (branch.target.started)
            {
                // Encode the final jump and version reference
                as.jmp32Ref(vm, branch.target);
            }
            else
            {
                // Queue the target for compilation
                // No jump since the target will immediately follow
                vm.queue(branch.target);
            }

            // Store the code end index
            branch.markEnd(as, vm);

            if (opts.jit_dumpinfo)
            {
                writeln(
                    "branch code length: ", branch.length, 
                    " (", branch.moveList.length, " moves)"
                );
                writeln();
            }
        }

        // If this is a call continuation stub
        else if (auto stub = cast(ContStub)frag)
        {
            stub.markStart(as, vm);

            as.comment("Cont stub for " ~ stub.contBranch.getName);

            as.pushJITRegs();

            // Save the return value
            as.push(retWordReg.reg(64));
            as.push(retTypeReg.reg(64));

            // The first argument is the stub object
            as.ptr(cargRegs[0], stub);

            // Call the JIT compilation function,
            auto compileFn = &compileCont;
            as.ptr(scrRegs[0], compileFn);
            as.call(scrRegs[0]);

            // Restore the return value
            as.pop(retTypeReg.reg(64));
            as.pop(retWordReg.reg(64));

            as.popJITRegs();

            // Jump to the compiled continuation
            as.jmp(X86Opnd(RAX));

            stub.markEnd(as, vm);

            // Set the return address entry for this stub
            vm.setRetEntry(
                stub.callVer.block.lastInstr,
                stub.callVer.state.callCtx,
                stub,
                stub.callVer.targets[1]
            );
        }

        else
        {
            assert (false, "invalid code fragment");
        }

        if (opts.jit_dumpasm)
        {
            writeln(frag.genString(as));
            writeln();
        }
    }

    assert (vm.compQueue.length is 0);

    // For each fragment reference
    foreach (refr; vm.refList)
    {
        // If the target is not compiled, substitute it for a branch stub
        CodeFragment target;
        if (refr.frag.started)
        {
            target = refr.frag;
        }
        else
        {
            assert (refr.targetIdx < 2);
            target = getBranchStub(vm, refr.targetIdx);
        }

        // Set the write position at the reference point
        auto startPos = as.getWritePos();
        as.setWritePos(refr.pos);

        // Switch on the reference size/type
        switch (refr.size)
        {
            case 32:
            auto offset = cast(int32_t)target.startIdx - (cast(int32_t)refr.pos + 4);
            as.writeInt(offset, 32);
            if (opts.jit_dumpinfo)
                writefln("linking ref to %s, offset=%s", target.getName, offset);
            break;

            case 64:
            as.writeInt(cast(int64_t)target.getCodePtr(as), 64);
            if (opts.jit_dumpinfo)
                writefln("linking absolute ref to %s", target.getName);
            break;

            default:
            assert (false);
        }

        // Return to the previous write position
        as.setWritePos(startPos);
    }

    // Clear the reference list
    vm.refList.length = 0;

    if (opts.jit_dumpinfo)
    {
        writeln("write pos: ", as.getWritePos, " / ", as.getRemSpace);
        writeln("num versions: ", stats.numVersions);
        writeln("num instances: ", stats.numInsts);
        writeln();
    }

    // Unset the call context
    vm.setCallCtx(null);

    //writeln("leaving compile");
}

/// Unit function entry point
alias extern (C) void function() EntryFn;

/**
Compile an entry point for a unit-level function
*/
EntryFn compileUnit(VM vm, IRFunction fun)
{
    auto startTimeUsecs = Clock.currAppTick().usecs();

    assert (fun.isUnit, "compileUnit on non-unit function");

    auto as = vm.execHeap;

    //
    // Create the return branch code
    //

    auto retEdge = new ExitCode(fun);
    retEdge.markStart(as, vm);

    // Push one slot for the return value
    as.sub(tspReg.opnd, X86Opnd(1));
    as.sub(wspReg.opnd, X86Opnd(8));

    // Place the return value on top of the stack
    as.setWord(0, retWordReg.opnd);
    as.setType(0, retTypeReg.opnd);

    // Store the stack pointers back in the VM
    as.setMember!("VM.wsp")(vmReg, wspReg);
    as.setMember!("VM.tsp")(vmReg, tspReg);

    // Restore the callee-save GP registers
    as.pop(R15);
    as.pop(R14);
    as.pop(R13);
    as.pop(R12);
    as.pop(RBP);
    as.pop(RBX);

    // Pop the stack alignment padding
    as.add(X86Opnd(RSP), X86Opnd(8));

    // Return to the host
    as.ret();

    retEdge.markEnd(as, vm);

    // Get the return code address
    auto retAddr = retEdge.getCodePtr(as);

    //
    // Compile the unit entry
    //

    // Create a version instance object for the function entry
    auto entryInst = new BlockVersion(
        fun.entryBlock,
        new CodeGenState(fun.getCtx(false, vm))
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

    // Load a pointer to the VM object
    as.ptr(vmReg, vm);

    // Load the stack pointers into RBX and RBP
    as.getMember!("VM.wsp")(wspReg, vmReg);
    as.getMember!("VM.tsp")(tspReg, vmReg);

    // Set the argument count (0)
    as.setWord(-1, X86Opnd(0));
    as.setType(-1, Type.INT32);

    // Set the "this" argument (global object)
    as.getMember!("VM.globalObj")(scrRegs[0], vmReg);
    as.setWord(-2, scrRegs[0].opnd);
    as.setType(-2, Type.REFPTR);

    // Set the closure argument (null)
    as.setWord(-3, X86Opnd(0));
    as.setType(-3, Type.REFPTR);

    // Set the return address
    as.ptr(scrRegs[0], retAddr);
    as.setWord(-4, scrRegs[0].opnd);
    as.setType(-4, Type.RETADDR);

    // Push space for the callee locals
    as.sub(tspReg.opnd, X86Opnd(1 * fun.numLocals));
    as.sub(wspReg.opnd, X86Opnd(8 * fun.numLocals));

    // Compile the unit entry version
    vm.queue(entryInst);
    vm.compile(null);

    // Set the return address entry for this call
    vm.setRetEntry(null, entryInst.state.callCtx, retEdge, null);

    // Get a pointer to the entry block version's code
    auto entryFn = cast(EntryFn)entryInst.getCodePtr(vm.execHeap);

    // Update the compilation time stat
    auto endTimeUsecs = Clock.currAppTick().usecs();
    stats.compTimeUsecs += endTimeUsecs - startTimeUsecs;

    // Return the unit entry function
    return entryFn;
}

/**
Compile an entry block instance for a function
*/
extern (C) CodePtr compileEntry(EntryStub stub)
{
    auto startTimeUsecs = Clock.currAppTick().usecs();

    //writeln("entering compileEntry");

    auto vm = stub.vm;
    auto ctorCall = stub.ctorCall;

    // Get the closure and IRFunction pointers
    auto argCount = vm.getWord(3).uint32Val;
    auto closPtr = vm.getWord(1).ptrVal;
    assert (closPtr !is null);
    auto fun = getClosFun(closPtr);
    assert (
        fun !is null,
        "closure IRFunction is null"
    );

    if (opts.jit_dumpinfo)
        writeln("compiling entry for " ~ fun.getName);

    /*
    writeln("closPtr=", closPtr);
    writeln("fun=", cast(ubyte*)fun);
    writeln("argCount=", argCount);
    if (argCount > 0)
        writeln("first arg: ", vm.getWord(4).uint64Val);
    writeln("orig stack size: ", vm.stackSize());
    */

    // Store the original number of locals for the function
    auto origLocals = fun.numLocals;

    // Generate the IR for this function
    if (fun.entryBlock is null)
    {
        astToIR(fun.ast, fun);
    }

    // Add space for the newly allocated locals
    vm.push(fun.numLocals - origLocals);

    /*
    writeln("fun.numLocals=", fun.numLocals);
    writeln("origLocals=", origLocals);
    writeln("new stack size: ", vm.stackSize());
    */

    // Request an instance for the function entry blocks
    auto entryInst = getBlockVersion(
        fun.entryBlock,
        new CodeGenState(fun.getCtx(false, vm)),
        true
    );

    // Request an instance for the function entry block
    auto ctorInst = getBlockVersion(
        fun.entryBlock,
        new CodeGenState(fun.getCtx(true, vm)),
        true
    );

    // Compile the entry versions
    vm.compile(fun.getCtx(ctorCall, vm));

    // Store the entry code pointer on the function
    fun.entryCode = entryInst.getCodePtr(vm.execHeap);
    fun.ctorCode = ctorInst.getCodePtr(vm.execHeap);
    assert (fun.entryCode !is fun.ctorCode);

    //writeln("leaving compileEntry");

    // Update the compilation time stat
    auto endTimeUsecs = Clock.currAppTick().usecs();
    stats.compTimeUsecs += endTimeUsecs - startTimeUsecs;

    return ctorCall? fun.ctorCode:fun.entryCode;
}

/**
Compile the branch code when a branch stub is hit
*/
extern (C) CodePtr compileBranch(VM vm, uint32_t blockIdx, uint32_t targetIdx)
{
    auto startTimeUsecs = Clock.currAppTick().usecs();

    //writeln("entering compileBranch");
    //writeln("    blockIdx=", blockIdx);
    //writeln("    targetIdx=", targetIdx);

    // Get the block from which the stub hit originated
    assert (blockIdx < vm.fragList.length, "invalid block idx");
    auto srcBlock = cast(BlockVersion)vm.fragList[blockIdx];
    assert (srcBlock !is null);

    // Get the branch edge
    assert (targetIdx < srcBlock.targets.length);
    auto branchCode = srcBlock.targets[targetIdx];
    assert (branchCode.started is false);

    // Queue the branch edge to be compiled
    vm.queue(branchCode);

    // Rewrite the final branch of the source block
    srcBlock.regenBranch(vm.execHeap, blockIdx);

    // Compile fragments and patch references
    vm.compile(srcBlock.state.callCtx);

    // Update the compilation time stat
    auto endTimeUsecs = Clock.currAppTick().usecs();
    stats.compTimeUsecs += endTimeUsecs - startTimeUsecs;

    //writeln("leaving compileBranch");

    // Return a pointer to the compiled branch code
    return branchCode.getCodePtr(vm.execHeap);
}

/**
Called when a call continuation stub is hit, compiles the continuation
*/
extern (C) CodePtr compileCont(ContStub stub)
{
    auto startTimeUsecs = Clock.currAppTick().usecs();

    //writeln("entering compileCont");

    auto callVer = stub.callVer;
    auto contBranch = stub.contBranch;
    auto callCtx = callVer.state.callCtx;
    auto vm = callCtx.vm;

    // Queue the continuation branch edge to be compiled
    assert (!contBranch.started);
    vm.queue(contBranch);

    // Update the continuation target in the call version
    stub.callVer.targets[0] = contBranch;

    // Rewrite the final branch of the call block
    stub.callVer.regenBranch(vm.execHeap, 0);

    // Compile fragments and patch references
    vm.compile(callCtx);

    // Patch the stub to jump to the continuation branch
    stub.patch(vm.execHeap, contBranch);

    // Set the return entry for the call continuation
    vm.setRetEntry(
        callVer.block.lastInstr,
        callCtx,
        contBranch,
        callVer.targets[1]
    );

    // Update the compilation time stat
    auto endTimeUsecs = Clock.currAppTick().usecs();
    stats.compTimeUsecs += endTimeUsecs - startTimeUsecs;

    //writeln("leaving compileCont");

    // Return a pointer to the compiled branch code
    return contBranch.getCodePtr(vm.execHeap);
}

/**
Get a function entry stub
*/
CodePtr getEntryStub(VM vm, bool ctorCall)
{
    auto as = vm.execHeap;

    if (ctorCall is true && vm.ctorStub)
        return vm.ctorStub.getCodePtr(as);
    if (ctorCall is false && vm.entryStub)
        return vm.entryStub.getCodePtr(as);

    auto stub = new EntryStub(vm, ctorCall);

    stub.markStart(as, vm);

    as.pushJITRegs();

    // Call the JIT compile function,
    // passing it a pointer to the stub
    auto compileFn = &compileEntry;
    as.ptr(scrRegs[0], compileFn);
    as.ptr(cargRegs[0], stub);
    as.call(scrRegs[0]);

    as.popJITRegs();

    // Jump to the compiled version
    as.jmp(X86Opnd(RAX));

    stub.markEnd(as, vm);

    if (ctorCall)
        vm.ctorStub = stub;
    else
        vm.entryStub = stub;

    return stub.getCodePtr(as);
}

/**
Get the branch target stub for a given target index
*/
BranchStub getBranchStub(VM vm, size_t targetIdx)
{
    auto as = vm.execHeap;

    // If this stub was already generated, return it
    if (targetIdx < vm.branchStubs.length && vm.branchStubs[targetIdx] !is null)
        return vm.branchStubs[targetIdx];

    // TODO: don't need special spill code for now, no reg alloc yet
    // eventually, need to save registers and implement soft-spilling scheme

    auto stub = new BranchStub(vm, targetIdx);
    vm.branchStubs.length = targetIdx + 1;
    vm.branchStubs[targetIdx] = stub;

    stub.markStart(as, vm);

    // Insert the label for this block in the out of line code
    as.comment("Branch stub (target " ~ to!string(targetIdx) ~ ")");

    //as.printStr("hit branch stub (target " ~ to!string(targetIdx) ~ ")");
    //as.printUint(scrRegs[0].opnd);

    // TODO: properly spill registers, GC may be run during compileBranch

    as.pushJITRegs();

    // The first argument is the VM object
    as.mov(cargRegs[0].opnd, vmReg.opnd);

    // The second argument is the src block index,
    // which was passed in scrRegs[0]
    as.mov(cargRegs[1].opnd(32), scrRegs[0].opnd(32));

    // The third argument is the branch target index
    as.mov(cargRegs[2].opnd(32), X86Opnd(targetIdx));

    // Call the JIT compilation function,
    auto compileFn = &compileBranch;
    as.ptr(scrRegs[0], compileFn);
    as.call(scrRegs[0]);

    as.popJITRegs();

    // Jump to the compiled version
    as.jmp(X86Opnd(RAX));

    // Store the code end index
    stub.markEnd(as, vm);

    return stub;
}

