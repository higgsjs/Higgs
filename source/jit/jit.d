/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

/// Scratch registers, these do not conflict with the C arguments
immutable X86Reg[] scrRegs = [RAX, RBX, RBP];

/// RCX, RBX, RBP, R8-R12: 9 allocatable registers
immutable X86Reg[] allocRegs = [RDI, RSI, RCX, RDX, R8, R9, R10, R11, R12];

/// Return word register
alias RCX retWordReg;

/// Return type tag register
alias DL retTagReg;

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

        /// Type written to stack flag
        bool, "tagWritten", 1,

        /// Local index, or register number, or constant value
        int, "val", 24,

        /// Padding bits
        uint, "", 5
    ));

    /// Value type, may be unknown
    ValType type;

    /// Stack value constructor
    static ValState stack()
    {
        ValState val;
        val.kind = Kind.STACK;
        val.tagWritten = false;
        val.val = 0xFFFF;
        return val;
    }

    /// Register value constructor
    static ValState reg(X86Reg reg)
    {
        ValState val;
        val.kind = Kind.REG;
        val.tagWritten = false;
        val.val = reg.regNo;
        return val;
    }

    bool isStack() const { return kind is Kind.STACK; }
    bool isReg() const { return kind is Kind.REG; }
    bool isConst() const { return kind is Kind.CONST; }

    bool tagKnown() const { return type.tagKnown; }
    Tag tag() const { assert (tagKnown); return type.tag; }
    bool shapeKnown() const { return type.shapeKnown; }
    ObjShape shape() const { return cast(ObjShape)type.shape; }

    /// Get a word operand for this value
    X86Opnd getWordOpnd(size_t numBits, StackIdx stackIdx = StackIdx.max) const
    {
        switch (kind)
        {
            case Kind.STACK:
            assert (stackIdx !is StackIdx.max);
            return wordStackOpnd(stackIdx, numBits);

            case Kind.REG:
            return X86Reg(X86Reg.GP, val, numBits).opnd;

            // TODO: const kind
            default:
            assert (false);
        }
    }

    /// Get a type tag operand for this value
    X86Opnd getTagOpnd(StackIdx stackIdx = StackIdx.max) const
    {
        if (type.tagKnown)
            return X86Opnd(type.tag);

        assert (stackIdx !is StackIdx.max);
        return tagStackOpnd(stackIdx);
    }

    /// Set the type tag for this value
    ValState setTag(Tag tag) const
    {
        assert (!isConst);

        ValState val = cast(ValState)this;
        val.type = ValType(tag);
        return val;
    }

    /// Set the shape for this value
    ValState setShape(ObjShape shape) const
    {
        assert (!isConst);

        ValState val = cast(ValState)this;
        val.type.shape = shape;
        val.type.shapeKnown = true;
        val.type.fptrKnown = false;
        return val;
    }

    /// Set the type for this value
    ValState setType(const ValType type) const
    {
        assert (!isConst);

        ValState val = cast(ValState)this;
        val.type = cast(ValType)type;
        return val;
    }

    /// Clear the type tag information for this value
    ValState clearTag() const
    {
        assert (!isConst);

        ValState val = cast(ValState)this;
        val.type.tagKnown = false;
        return val;
    }

    /// Clear the shape information for this value
    ValState clearShape() const
    {
        assert (!isConst);

        ValState val = cast(ValState)this;

        if (type.shapeKnown)
        {
            assert (!type.fptrKnown);
            val.type.shape = null;
            val.type.shapeKnown = false;
        }

        return val;
    }

    /// Clear all type information for this value
    ValState clearType() const
    {
        assert (!isConst);

        ValState val = cast(ValState)this;
        val.type = ValType();
        return val;
    }

    /// Move this value to the stack
    ValState toStack() const
    {
        ValState val = cast(ValState)this;
        val.kind = Kind.STACK;
        val.val = 0xFFFF;
        return val;
    }

    /// Move this value to a register
    ValState toReg(X86Reg reg) const
    {
        ValState val = cast(ValState)this;
        val.kind = Kind.REG;
        val.val = reg.regNo;
        return val;
    }

    /// Mark the type as written to the stack
    ValState writeTag() const
    {
        ValState val = cast(ValState)this;
        val.tagWritten = true;
        return val;
    }
}

/**
Current code generation state. This includes register
allocation state and known type information.
*/
class CodeGenState
{
    /// Associated IR function
    IRFunction fun;

    /// Map of live values to current type/allocation states
    private ValState[IRDstValue] valMap;

    /// Map of general-purpose registers to values
    /// If a register is free, its value is null
    private IRDstValue[NUM_REGS] gpRegMap;

    /**
    Constructor for a function entry code generation state
    */
    this(IRFunction fun)
    {
        this.fun = fun;

        mapToStack(fun.raVal);
        mapToStack(fun.closVal);
        mapToStack(fun.thisVal);
        mapToStack(fun.argcVal);

        foreach (ident, param; fun.paramMap)
            mapToStack(param);

        // Set the tags for the untagged hidden argument values
        setTag(fun.raVal, Tag.RETADDR);
        setTag(fun.closVal, Tag.CLOSURE);
        setTag(fun.argcVal, Tag.INT32);
    }

    /**
    Copy constructor
    */
    this(CodeGenState that)
    {
        this.fun = that.fun;
        this.valMap = that.valMap.dup;
        this.gpRegMap = that.gpRegMap;
    }

    /**
    Construct the successor state for a given predecessor state and branch edge
    */
    this(CodeGenState predState, BranchEdge branch)
    {
        // Call the copy constructor
        this(predState);

        auto liveInfo = fun.liveInfo;

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

            // Free the register currently used by the phi node (if any)
            auto predPhiState = getState(phi);
            if (predPhiState.isReg)
            {
                auto regNo = predPhiState.val;
                gpRegMap[regNo] = null;
            }

            // Get the default register for the phi node
            auto phiReg = getDefReg(phi);

            // If the argument is a dst value
            if (auto dstArg = cast(IRDstValue)arg)
            {
                // Get the word operand for the argument
                X86Opnd argOpnd = dstArg? predState.getWordOpnd(dstArg, 64):X86Opnd.NONE;

                // If the argument is in a register which is about to become free
                if (argOpnd.isReg && liveInfo.liveAfterPhi(dstArg, phi.block) is false)
                {
                    // Try to use the phi register for the ph inode
                    phiReg = argOpnd.reg;
                }
            }

            // Get the value currently mapped to this register
            auto regVal = gpRegMap[phiReg.regNo];

            ValState phiState;

            // If the register is free
            if (regVal is null || liveInfo.liveAfterPhi(regVal, phi.block) is false)
            {
                // Map the phi node to the register
                phiState = ValState.reg(phiReg);
                gpRegMap[phiReg.regNo] = phi;
            }
            else
            {
                // Map the phi node to its stack location
                phiState = ValState.stack();
            }

            // If the phi value is flowing into itself and the
            // type was previously written to the stack
            if (arg is phi && predPhiState.tagWritten)
            {
                // Mark the type as written to the stack
                phiState = phiState.writeTag();
            }

            // Set the phi type to the argument type
            auto argType = predState.getType(arg);
            phiState = phiState.setType(argType);

            // Set the phi node's new state
            valMap[phi] = phiState;
        }

        // Remove information about values dead after
        // the phi nodes in the successor block
        removeDead(liveInfo, branch.target);
    }

    /**
    Produce a string representation of the type information in
    this code generation state
    */
    override string toString() const
    {
        string str;

        foreach (val, st; valMap)
        {
            str ~= format("%s: %s\n", val.getName, st.tagKnown? to!string(st.type):"unknown");
        }

        return str;
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

            if (liveInfo.liveAfterPhi(value, block) is false)
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
            if (liveInfo.liveAfterPhi(value, block) is false)
                gpRegMap[regNo] = null;
        }
    }

    /**
    Compute the difference (similarity) between this state and another
    - If states are identical, 0 will be returned
    - If states are incompatible, size_t.max will be returned
    */
    size_t diff(CodeGenState succ)
    {
        assert (this.fun is succ.fun);

        auto pred = this;

        // Difference (penalty) sum
        size_t diff = 0;

        debug
        {
            foreach (value, state; pred.valMap)
            {
                assert (
                    value in succ.valMap,
                    "value not in succ valMap: " ~ value.toString
                );
            }
        }

        // For each value in the successor type state map
        foreach (value, state; succ.valMap)
        {
            auto predSt = pred.getState(value);
            auto succSt = succ.getState(value);

            // If the type states match perfectly, no penalty
            if (predSt == succSt)
                continue;

            // If the types do not match perfectly
            if (predSt.type != succSt.type)
            {
                // If the predecessor type is a subtype of the successor
                if (predSt.type.isSubType(succSt.type))
                {
                    // Add a penalty for the inexact type match,
                    // since information would be lost
                    diff += 1;
                }
                else
                {
                    // The types are incompatible
                    return size_t.max;
                }
            }
        }

        // Return the total difference
        return diff;
    }

    /**
    Get the default register for a given value
    */
    X86Reg getDefReg(IRDstValue value)
    {
        assert (
            value.outSlot !is NULL_STACK,
            "no out slot for value: " ~ value.toString
        );

        // If this value flows into a phi node other than itself
        for (auto use = value.getFirstUse; use !is null; use = use.next)
        {
            auto owner = value.getFirstUse.owner;
            if (!cast(PhiNode)value && cast(PhiNode)owner)
            {
                return getDefReg(owner);
            }
        }

        auto regIdx = value.outSlot % allocRegs.length;
        auto reg = allocRegs[regIdx];

        return reg;
    }

    /**
    Map a register to a value
    */
    X86Reg mapReg(X86Reg reg, IRDstValue value, size_t numBits)
    {
        assert (getState(value).isReg is false);
        assert (gpRegMap[reg.regNo] is null);

        // Map the register to the new value
        gpRegMap[reg.regNo] = value;

        // Map the value to the register
        valMap[value] = getState(value).toReg(reg);

        // Return the operand for this register
        return reg.reg(numBits);
    }

    /**
    Find a free register or spill one
    */
    X86Reg freeReg(
        CodeBlock as,
        IRInstr instr,
        X86Reg defReg = allocRegs[0]
    )
    {
        auto liveInfo = fun.liveInfo;

        // Get the value mapped to the default register
        auto defRegVal = gpRegMap[defReg.regNo];

        // If the default register is free
        if (defRegVal is null)
            return defReg;

        // If the value mapped to the default register is not live
        if (!liveInfo.liveBefore(defRegVal, instr) && defRegVal !is instr)
        {
            // Remove the mapped value from the value map
            valMap.remove(defRegVal);
            gpRegMap[defReg.regNo] = null;
            return defReg;
        }

        // For each allocatable general-purpose register
        foreach (reg; allocRegs)
        {
            auto regVal = gpRegMap[reg.regNo];

            // If nothing is mapped to this register
            if (regVal is null)
            {
                return reg;
            }

            // If the value mapped is not live
            if (!liveInfo.liveBefore(regVal, instr) && regVal !is instr)
            {
                // Remove the mapped value from the value map
                valMap.remove(regVal);
                gpRegMap[reg.regNo] = null;
                return reg;
            }
        }

        // If the value mapped to the default register
        // is not an argument of the instruction
        if (!instr.hasArg(defRegVal) && defRegVal !is instr)
        {
            // Spill the default register
            spillReg(as, defReg);
            return defReg;
        }

        // Chosen register to spill
        immutable(X86Reg)* chosenReg = null;

        // For each allocatable general-purpose register
        foreach (reg; allocRegs)
        {
            auto regVal = gpRegMap[reg.regNo];

            // If an argument of the instruction uses this register, skip it
            if (instr.hasArg(regVal) || regVal is instr)
                continue;

            chosenReg = &reg;
            break;
        }

        // If no non-argument register could be found, spill a 
        // register which isn't the mapped to the instruction
        if (chosenReg is null)
        {
            foreach (reg; allocRegs)
            {
                auto regVal = gpRegMap[reg.regNo];
                if (regVal is instr)
                    continue;
                chosenReg = &reg;
                break;
            }
        }

        // Spill the chosen register
        assert (
            chosenReg !is null,
            "couldn't find register to spill"
        );
        spillReg(as, *chosenReg);

        return *chosenReg;
    }

    /**
    Allocate a register for a value
    */
    X86Reg allocReg(
        CodeBlock as,
        IRInstr instr,
        IRDstValue value,
        size_t numBits,
        X86Opnd defReg = X86Opnd.NONE
    )
    {
        assert (value !is null);

        // If no default register was specified, assign one
        if (defReg == X86Opnd.NONE)
            defReg = getDefReg(value).opnd;

        // Find or free a register
        auto reg = freeReg(as, instr, defReg.reg);

        // Map the value to the chosen register
        return mapReg(reg, value, numBits);
    }

    /**
    Get the operand for an instruction's output
    */
    X86Opnd getOutOpnd(
        CodeBlock as,
        IRInstr instr,
        size_t numBits,
        bool useArgReg = false
    )
    {
        assert (instr !is null);

        X86Opnd defReg = X86Opnd.NONE;

        // If we should try to reuse an argument register
        if (useArgReg)
        {
            // For each argument of the instruction
            for (size_t i = 0; i < instr.numArgs; ++i)
            {
                // If the argument is a constant, skip it
                auto dstArg = cast(IRDstValue)instr.getArg(i);
                if (dstArg is null)
                    continue;

                // If the argument is not mapped to a register, skip it
                auto state = getState(dstArg);
                if (state.isReg is false)
                    continue;

                // If the argument is live after the instruction, skip it
                if (fun.liveInfo.liveAfter(dstArg, instr) is true)
                    continue;

                auto argOpnd = state.getWordOpnd(64);

                // Free the register
                valMap.remove(dstArg);
                gpRegMap[argOpnd.reg.regNo] = null;

                // Bias the register allocation towards this register
                defReg = argOpnd;
                break;
            }
        }

        // Attempt to allocate a register for the output value
        auto reg = allocReg(
            as,
            instr,
            instr,
            numBits,
            defReg
        );

        assert (instr in valMap);

        //writeln("outOpnd=", reg);

        return reg.opnd;
    }

    /**
    Map a value to its stack location
    */
    void mapToStack(IRDstValue value)
    {
        // Map the value and its type to the stack
        valMap[value] = ValState.stack().writeTag();
    }

    /**
    Spill a specific register to the stack
    */
    void spillReg(CodeBlock as, X86Reg reg)
    {
        // Get the value mapped to this register
        auto regVal = gpRegMap[reg.regNo];

        // If no value is mapped to this register, stop
        if (regVal is null)
            return;

        // Get the state for this value
        auto state = getState(regVal);

        assert (
            state.isReg,
            "value not mapped to reg in spillReg:\n" ~
            regVal.toString
        );

        // Mark the value as being on the stack
        valMap[regVal] = state.toStack();

        // Mark the register as free
        gpRegMap[reg.regNo] = null;

        // If the value is a function parameter,
        // we don't actually need to spill it
        if (cast(FunParam)regVal)
            return;

        //writeln("spilling: ", regVal);

        auto mem = wordStackOpnd(regVal.outSlot);

        //as.printStr("spilling " ~ regVal.toString);
        //as.printStr("spilling " ~ reg.toString);
        //writefln("spilling: %s (%s)", regVal.toString, reg);

        // Spill the value currently in the register
        if (opts.genasm)
            as.comment("Spilling " ~ regVal.getName);
        as.mov(mem, reg.opnd(64));

        // If the type is known, spill it
        if (state.tagKnown && !state.tagWritten)
        {
            // Write the type tag to the type stack
            //if (opts.genasm)
            //    as.comment("Spilling type for " ~ regVal.getName);
            as.mov(tagStackOpnd(regVal.outSlot), state.getTagOpnd());
            valMap[regVal] = valMap[regVal].writeTag();
        }
    }

    /// Spill test function
    alias bool delegate(LiveInfo liveInfo, IRDstValue value) SpillTestFn;

    /**
    Spill a set of values to the stack
    */
    void spillValues(CodeBlock as, SpillTestFn spillTest)
    {
        auto liveInfo = fun.liveInfo;

        // For each allocatable general-purpose register
        foreach (reg; allocRegs)
        {
            auto value = gpRegMap[reg.regNo];

            // If nothing is mapped to this register, skip it
            if (value is null)
                continue;

            // If the value should be spilled, spill it
            if (spillTest(liveInfo, value) is true)
                spillReg(as, reg);
        }

        // For each value in the value map
        foreach (value, state; valMap)
        {
            if (cast(FunParam)value)
                continue;

            // If the value has a known type and is not in a register
            if (state.tagKnown && !state.tagWritten && !state.isReg)
            {
                // If the value should be spilled
                if (spillTest(liveInfo, value) is true)
                {
                    // Spill the type for this value
                    as.mov(tagStackOpnd(value.outSlot), state.getTagOpnd());
                    valMap[value] = state.writeTag();
                }
            }
        }
    }

    /**
    Spill the values live before a given instruction
    */
    void spillLiveBefore(CodeBlock as, IRInstr instr)
    {
        return spillValues(
            as,
            delegate bool(LiveInfo liveInfo, IRDstValue value)
            {
                return liveInfo.liveBefore(value, instr);
            }
        );
    }

    /**
    Spill live registers from the register save space
    */
    void spillSavedRegs(SpillTestFn spillTest)
    {
        auto vm = fun.vm;
        auto liveInfo = fun.liveInfo;

        // For each allocatable register
        foreach (regIdx, reg; allocRegs)
        {
            // Get the value mapped to this register
            auto regVal = gpRegMap[reg.regNo];

            // If nothing is mapped to this register, skip it
            if (regVal is null)
                continue;

            // If the value is not live, skip it
            if (spillTest(liveInfo, regVal) is false)
                continue;

            //writefln("spilling reg %s val %s", reg, regVal);
            //writefln("  val=%s", vm.regSave[regIdx].uint64Val);

            // Get the state for this value
            auto state = getState(regVal);

            assert (
                state.isReg,
                "value not mapped to reg to be spilled"
            );

            // Store the value in its stack location
            vm.wsp[regVal.outSlot] = vm.regSave[regIdx];

            // If the type is known, store it
            if (state.tagKnown)
            {
                //writeln("spilling known type");

                // Write the type tag to the type stack
                vm.tsp[regVal.outSlot] = state.tag;
            }
        }
    }

    /**
    Reload registers from the stack to the register save space
    */
    void loadSavedRegs(SpillTestFn spillTest)
    {
        auto vm = fun.vm;
        auto liveInfo = fun.liveInfo;

        // For each allocatable register
        foreach (regIdx, reg; allocRegs)
        {
            // Get the value mapped to this register
            auto regVal = gpRegMap[reg.regNo];

            // If nothing is mapped to this register, skip it
            if (regVal is null)
                continue;

            // If the value is not live, skip it
            if (spillTest(liveInfo, regVal) is false)
                continue;

            // Restore the register value from its stack location
            // Note: this is important because a GC may have occurred
            vm.regSave[regIdx] = vm.wsp[regVal.outSlot];
        }
    }

    /**
    Clear known shape information. Used at function calls.
    */
    void clearShapes()
    {
        // For each value in the value map
        foreach (value, state; valMap)
        {
            if (state.type.shapeKnown)
                valMap[value] = state.clearShape();
        }
    }

    /**
    Get an operand for any IR value without allocating a register
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

        return state.getWordOpnd(numBits, dstVal.outSlot);
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
        auto argDst = cast(IRDstValue)argVal;

        // If the argument is a string
        if (auto argStr = cast(IRString)argVal)
        {
            // Ensure that the string is allocated
            argStr.getPtr(fun.vm);

            // If no temporary register is supplied, free one
            if (tmpReg == X86Opnd.NONE)
                tmpReg = freeReg(as, instr).opnd;

            as.ptr(tmpReg.reg, argStr);
            as.getMember!("IRString.ptr")(tmpReg.reg, tmpReg.reg);
            return tmpReg;
        }

        // Ensure that the value was previously defined and is live
        assert (
            argDst is null || argDst in valMap,
            "argument not in val map: " ~ argDst.toString
        );

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
                if (curOpnd.imm.imm is 0)
                {
                    as.xorps(tmpReg, tmpReg);
                }
                else
                {
                    // Write the FP constant in the code stream and load it
                    as.movsd(tmpReg, X86Opnd(64, RIP, 2));
                    as.jmp8(8);
                    as.writeInt(curOpnd.imm.imm, 64);
                }

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
            // Try to allocate a register for the operand
            assert (argDst !is null);
            assert (getState(argDst).isStack);
            auto opnd = loadVal? allocReg(as, instr, argDst, numBits).opnd:curOpnd;

            // If a register was successfully allocated
            if (opnd.isReg && curOpnd.isMem)
            {
                //writeln("loading: ", argDst);

                // Load the value into the register
                // Note: we load all 64 bits, not just the requested bits
                as.mov(opnd.reg.opnd(64), wordStackOpnd(argDst.outSlot));

                assert (getState(argDst).isReg);
            }

            // If the register allocation failed but a temp reg was supplied
            else if (opnd.isMem && !tmpReg.isNone)
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
    Get an x86 operand for the type tag of any IR value
    */
    X86Opnd getTagOpnd(IRValue value) const
    {
        assert (value !is null);

        auto dstVal = cast(IRDstValue)value;

        // If the value is not a dst value
        if (dstVal is null)
        {
            // If the value is a string
            if (auto argStr = cast(IRString)value)
            {
                return X86Opnd(Tag.STRING);
            }

            return X86Opnd(value.cstValue.tag);
        }

        // Get the type operand for this value
        return getState(dstVal).getTagOpnd(dstVal.outSlot);
    }

    /**
    Get an x86 operand for the type of an instruction argument
    */
    X86Opnd getTagOpnd(
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
        auto curOpnd = getTagOpnd(argVal);

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

    /// Set the type tag value for an instruction's output
    void setOutTag(
        CodeBlock as,
        IRInstr instr,
        Tag tag
    )
    {
        assert (
            instr !is null,
            "null instruction"
        );

        // getOutOpnd should be called before setOutTag
        assert (
            instr in valMap,
            "setOutTag: instr not in valMap:\n" ~
            instr.toString
        );

        auto state = getState(instr);

        // Set a known type for this value
        valMap[instr] = state.setTag(tag);
    }

    /// Write the type tag for an instruction's output to the type stack
    void setOutTag(CodeBlock as, IRInstr instr, X86Reg tagReg)
    {
        assert (
            instr !is null,
            "null instruction"
        );

        // getOutOpnd should be called before setOutTag
        assert (instr in valMap);

        auto state = getState(instr);

        // Clear the type tag information for the value
        valMap[instr] = state.clearTag();

        // Write the type to the type stack
        as.mov(tagStackOpnd(instr.outSlot), X86Opnd(tagReg));
    }

    /// Set the type tag for a given value
    void setTag(IRDstValue value, Tag tag)
    {
        assert (value in valMap, "value not in val map: " ~ value.toString);
        ValState state = getState(value);

        // Assert that we aren't contradicting existing information
        assert (!state.tagKnown || tag is state.tag);

        // If the type was previously unknown, it must have
        // been written on the stack, mark it as such
        if (!state.tagKnown)
            state = state.writeTag();

        // Set a known type for this value
        valMap[value] = state.setTag(tag);
    }

    /// Set shape information for a given value
    void setShape(IRDstValue value, ObjShape shape)
    {
        assert (
            value in valMap,
            "setShape: value not in value map"
        );
        ValState state = getState(value);

        // Set a known type for this value
        valMap[value] = state.setShape(shape);
    }

    /// Set the type for a given value
    void setType(IRDstValue value, ValType type)
    {
        assert (value in valMap);
        ValState state = getState(value);

        // Assert that we aren't contradicting existing information
        assert (!type.tagKnown || !state.tagKnown || type.tag is state.tag);

        // Set a known type for this value
        valMap[value] = state.setType(type);
    }

    /// Clear shape information for a given value
    void clearShape(IRDstValue value)
    {
        assert (value in valMap);
        ValState state = getState(value);

        // Set a known type for this value
        valMap[value] = state.clearShape();
    }

    /// Get the type for a given value
    auto getType(IRValue value)
    {
        // If this is a dst value
        if (auto dstVal = cast(IRDstValue)value)
        {
            assert (
                dstVal in valMap,
                "getType: value not in val map " ~ value.toString
            );
            ValState state = getState(dstVal);
            return state.type;
        }

        // If the value is a string
        if (auto argStr = cast(IRString)value)
        {
            return ValType(Tag.STRING);
        }

        return ValType(value.cstValue.tag);
    }

    /// Test if the shape is known for a given value
    auto shapeKnown(IRDstValue value)
    {
        assert (
            value in valMap,
            "shapeKnown: value not in val map " ~ value.toString
        );
        ValState state = getState(value);

        return state.type.shapeKnown;
    }

    /// Get shape information for a given value
    auto getShape(IRDstValue value)
    {
        assert (value in valMap);
        ValState state = getState(value);

        assert (
            state.type.shapeKnown,
            "shape is not known"
        );
        return state.type.shape;
    }

    /// Get the state for a given value
    ValState getState(IRDstValue val) const
    {
        assert (val !is null);

        return cast(ValState)valMap.get(
            val,
            ValState.stack()
        );
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
        assert (
            opts.genasm ||
            opts.dumpinfo ||
            opts.trace_instrs
        );

        if (auto ver = cast(BlockVersion)this)
        {
            return ver.block.getName;
        }

        if (auto branch = cast(BranchCode)this)
        {
            return "branch_" ~ branch.branch.target.getName;
        }

        if (auto stub = cast(EntryStub)this)
        {
            return "entry_stub";
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
        if (opts.genasm)
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
        if (opts.genasm)
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
    /// Predecessor state
    CodeGenState predState;

    /// IR branch edge object
    BranchEdge branch;

    /// Prelude code generation function
    PrelGenFn prelGenFn;

    /// Target block version (null until compiled)
    BlockVersion target = null;

    this(
        CodeGenState predState,
        BranchEdge branch,
        PrelGenFn prelGenFn
    )
    {
        this.predState = predState;
        this.branch = branch;
        this.prelGenFn = prelGenFn;
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
    CodeFragment[] targets;

    /// Inner code length, excluding final branches
    uint32_t codeLen;

    /// Extended version info
    ExtVerInfo extInfo = null;

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

        auto vm = state.fun.vm;

        // Store the branch generation function and targets
        assert (target0 !is null);
        this.branchGenFn = genFn;
        this.targets = [target0, target1];

        // Compute the code length
        codeLen = cast(uint32_t)as.getWritePos - startIdx;

        // If this block doesn't end in a call and there are two targets
        if (block.lastInstr.opcode.isCall is false && target1 !is null)
        {
            // Write the block idx in scrReg[0]
            size_t blockIdx = vm.fragList.length;
            as.mov(scrRegs[0].opnd(32), X86Opnd(blockIdx));
        }

        // Determine the branch shape
        /*auto shape = (target1 is null)? BranchShape.NEXT0:BranchShape.DEFAULT;
        assert (
            (shape !is BranchShape.NEXT0) ||
            (vm.compQueue.length > 0 && vm.compQueue.back is targets[0])
        );*/

        BranchShape shape = BranchShape.DEFAULT;
        if (vm.compQueue.length > 0)
        {
            if (vm.compQueue.back is targets[0])
                shape = BranchShape.NEXT0;
            else if (vm.compQueue.back is targets[1])
                shape = BranchShape.NEXT1;
        }

        // Generate the final branch code
        branchGenFn(
            as,
            vm,
            target0,
            target1,
            shape
        );

        // Store the code end index
        markEnd(as, vm);
    }

    /**
    Rewrite the final branch of this block
    */
    void regenBranch(CodeBlock as, size_t blockIdx)
    {
        // Ensure that this block has already been compiled
        assert (started && ended);

        auto vm = state.fun.vm;

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
        assert (branchGenFn !is null);
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
Base class for extended version information
*/
class ExtVerInfo
{
}

/**
Shape dispatch information
*/
class ShapeDispInfo : ExtVerInfo
{
    /// State at the shape dispatch instruction
    CodeGenState instrSt;

    // TODO: exec counter?
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

        // Don't queue multiple identical targets
        if (workList.length > 0 && workList[$-1] is target)
            return;

        workList ~= target;
    }

    CodeFragment[] fragList;

    // Until the work list is empty
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
            foreach (target; inst.targets)
                queue(frag, target);
        }

        else
        {
            // Do nothing
        }
    }

    // Sort the fragment by increasing memory address
    fragList.sort!"a.startIdx < b.startIdx";

    auto str = appender!string;

    // For each fragment queued
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
    CodeGenState state
)
{
    auto fun = state.fun;
    auto vm = fun.vm;

    // Get the list of versions for this block
    auto versions = fun.versionMap.get(block, []);

    // Best version found
    BlockVersion bestVer;
    size_t bestDiff = size_t.max;

    //writeln("requesting: ", block.getName);

    // For each successor version available
    foreach (ver; versions)
    {
        // Compute the difference with the incoming state
        auto diff = state.diff(ver.state);

        //writeln("diff: ", diff);

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
    if (versions.length >= opts.maxvers)
    {
        debug
        {
            if (opts.maxvers > 0)
                writefln("version limit hit (%s) in %s", versions.length, fun.getName);
        }

        // If a compatible match was found
        if (bestDiff < size_t.max)
        {
            // Return the best match found
            assert (bestVer.state.fun is fun);
            return bestVer;
        }

        //writeln("producing general version for: ", block.getName);

        // Strip the state of known types and constants,
        // except for hidden function arguments
        auto genState = new CodeGenState(state);
        foreach (val, valSt; genState.valMap)
        {
            if (val !is fun.closVal &&
                val !is fun.argcVal &&
                val !is fun.raVal &&
                (valSt.tagKnown || valSt.shapeKnown))
            {
                genState.valMap[val] = valSt.clearType();
            }
        }

        // Ensure that the general version matches
        assert(state.diff(genState) !is size_t.max);

        assert (genState.fun is fun);
        state = genState;
    }

    //writeln("best ver diff: ", bestDiff, " (", versions.length, ")");

    // Create a new block version object using the predecessor's state
    auto ver = new BlockVersion(block, state);

    // Add the new version to the list for this block
    fun.versionMap[block] ~= ver;

    // If block version stats should be computed
    if (opts.stats)
    {
        auto numVersions = fun.versionMap[block].length;

        // If this is the first version for this block
        if (numVersions is 1)
        {
            // Increment the number of compiled blocks
            stats.numBlocks++;

            // Increment the number of blocks with 1 version
            stats.numVerBlocks[1]++;
        }
        else
        {
            // Update counts of blocks with specific numbers of versions
            stats.numVerBlocks[numVersions-1]--;
            stats.numVerBlocks[numVersions]++;
        }

        // Increment the total number of block versions generated
        stats.numVersions++;

        // Update the maximum version count
        stats.maxVersions = max(stats.maxVersions, numVersions);
    }

    // Queue the block version for compilation
    vm.queue(ver);

    // Return the newly created block version
    assert (ver.state.fun is fun);
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
    // If eager codegen is enabled, force the version
    // to be generated now
    if (opts.bbv_eager)
        noStub = true;

    auto vm = predState.fun.vm;

    assert (
        branch !is null,
        "getBranchEdge: branch edge is null"
    );

    // Return a branch edge code object for the successor
    auto branchCode = new BranchCode(
        predState,
        branch,
        prelGenFn
    );

    // If we know this will be executed, queue the branch edge for compilation
    if (noStub)
        vm.queue(branchCode);

    return branchCode;
}

/**
Generate the moves to transition from a predecessor to a successor state
*/
void genBranchMoves(
    CodeBlock as,
    CodeGenState predState,
    CodeGenState succState,
    BranchEdge branch
)
{
    // List of moves to transition to the successor state
    Move[] moveList;

    // String values and phi nodes for string moves
    IRString[] strVals;
    X86Opnd[] strDsts;

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

        bool moveAdded = false;

        // Test if the successor value is a parameter
        // We don't need to move parameter values to the stack
        bool succParam = cast(FunParam)succVal !is null;

        // If the pred value is a string
        if (auto predStr = cast(IRString)predVal)
        {
            // Get the destionation operand for the phi word
            X86Opnd dstWordOpnd = succState.getWordOpnd(succVal, 64);

            strVals ~= predStr;
            strDsts ~= dstWordOpnd;
        }
        else
        {
            // Get the source and destination operands for the phi word
            X86Opnd srcWordOpnd = predState.getWordOpnd(predVal, 64);
            X86Opnd dstWordOpnd = succState.getWordOpnd(succVal, 64);

            if (srcWordOpnd != dstWordOpnd &&
                !dstWordOpnd.isImm &&
                !(succParam && dstWordOpnd.isMem))
            {
                moveList ~= Move(dstWordOpnd, srcWordOpnd);
                moveAdded = true;
            }
        }

        // Get the source and destination operands for the phi type
        X86Opnd srcTypeOpnd = predState.getTagOpnd(predVal);
        X86Opnd dstTypeOpnd = succState.getTagOpnd(succVal);
        assert (!(opts.maxvers is 0 && !srcTypeOpnd.isImm && dstTypeOpnd.isImm));

        if (srcTypeOpnd != dstTypeOpnd &&
            !dstTypeOpnd.isImm &&
            !(succParam && dstTypeOpnd.isMem))
        {
            moveList ~= Move(dstTypeOpnd, srcTypeOpnd);
            moveAdded = true;
        }

        // Get the successor value state
        auto succState = succState.getState(succVal);

        // Check if the predecessor is the same value and had its type written
        auto predWritten = predVal is succVal && predState.getState(succVal).tagWritten;

        // If the successor is not a function parameter and the successor
        // state requires the type be written and the predecessor type was not
        // written to the stack, then write the type
        if (!succParam && !dstTypeOpnd.isMem && succState.tagWritten && !predWritten)
        {
            as.mov(tagStackOpnd(succVal.outSlot), succState.getTagOpnd());
            moveAdded = true;
        }

        if (opts.genasm && moveAdded)
        {
            if (succPhi)
                as.comment(succPhi.getName ~ " = phi " ~ predVal.getName);
            else
                as.comment("move " ~ succVal.getName);
        }
    }

    //foreach (move; moveList)
    //    as.printStr(format("move from %s to %s", move.src, move.dst));

    // Execute the moves
    execMoves(as, moveList, scrRegs[0], scrRegs[1]);

    // For each string value
    foreach (idx, strVal; strVals)
    {
        auto dstOpnd = strDsts[idx];

        // Ensure that the string is allocated
        strVal.getPtr(predState.fun.vm);

        as.ptr(scrRegs[0], strVal);

        if (dstOpnd.isReg)
        {
            as.getMember!("IRString.ptr")(dstOpnd.reg, scrRegs[0]);
        }
        else
        {
            as.getMember!("IRString.ptr")(scrRegs[0], scrRegs[0]);
            as.mov(dstOpnd, scrRegs[0].opnd);
        }
    }
}

/// Return address entry
alias Tuple!(
    IRInstr, "callInstr",
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
Set the current instruction when calling host code from JITted code.
Must set the current instruction to null when returning from host code.
*/
void setCurInstr(VM vm, IRInstr curInstr)
{
    //writeln("curInstr=", curInstr);

    // Ensure proper usage
    assert (
        !(vm.curInstr !is null && curInstr !is null),
        "current instr is not null"
    );

    vm.curInstr = curInstr;
}

/**
Set the return address entry for a call instruction
*/
void setRetEntry(
    VM vm,
    IRInstr callInstr,
    CodeFragment retCode,
    CodeFragment excCode
)
{
    auto retAddr = retCode.getCodePtr(vm.execHeap);
    vm.retAddrMap[retAddr] = RetEntry(callInstr, retCode, excCode);
}

/**
Compile all blocks in the compile queue
*/
void compile(VM vm, IRInstr curInstr)
{
    //writeln("entering compile");

    assert (vm !is null);
    auto as = vm.execHeap;
    assert (as !is null);

    // Set the current instruction
    vm.setCurInstr(curInstr);

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

        //writeln("compiling fragment: ", frag.getName);

        // If this is a version instance
        if (auto ver = cast(BlockVersion)frag)
        {
            assert (
                ver.ended is false,
                "version already compiled: " ~ ver.getName
            );

            auto block = ver.block;
            assert (
                ver.block !is null,
                ver.state.fun.getName
            );

            // Copy the instance's state object
            auto state = new CodeGenState(ver.state);

            // Store the code start index for this fragment
            if (ver.startIdx is ver.startIdx.max)
                ver.markStart(as, vm);

            if (opts.dumpinfo)
                writeln("compiling block: ", block.getName);

            if (opts.trace_instrs)
                as.printStr(block.getName ~ ":");

            // For each instruction of the block
            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
            {
                if (opts.dumpinfo)
                    writeln("compiling instr: ", instr.toString());

                // If we should generate disassembly strings
                if (opts.genasm)
                    as.comment(instr.toString());

                if (opts.trace_instrs)
                    as.printStr(instr.toString());

                /*
                import main;
                as.ptr(scrRegs[0], &instrPtr);
                as.ptr(scrRegs[1], instr);
                as.mov(X86Opnd(64, scrRegs[0]), scrRegs[1].opnd);
                */

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
            assert (
                frag.ended,
                "unterminated code fragment: " ~
                ver.block.toString
            );

            // If this is a function entry block
            if (block is block.fun.entryBlock)
            {
                // Set the function entry code pointer
                block.fun.entryCode = frag.getCodePtr(vm.execHeap);
            }
        }

        // If this is a branch code fragment
        else if (auto branch = cast(BranchCode)frag)
        {
            assert (branch.predState !is null);

            // Store the code start index
            branch.markStart(as, vm);

            //as.printStr("branch code to " ~ branch.branch.target.getName);

            // Generate the prelude code, if any
            if (branch.prelGenFn)
                branch.prelGenFn(as, vm);

            // Generate the successor state for this branch
            auto succState = new CodeGenState(
                branch.predState,
                branch.branch
            );

            // Get a version of the successor matching the incoming state
            branch.target = getBlockVersion(
                branch.branch.target,
                succState
            );

            // Generate the moves to transition to the successor state
            genBranchMoves(
                as,
                branch.predState,
                branch.target.state,
                branch.branch
            );

            // The predecessor state is no longer needed
            branch.predState = null;

            // If the target was already compiled before
            if (branch.target.started)
            {
                // Encode the final jump and version reference
                as.jmp32Ref(vm, branch.target);
            }

            // Store the code end index
            branch.markEnd(as, vm);

            if (opts.dumpinfo)
            {
                writeln("branch code length: ", branch.length);
                writeln();
            }
        }

        // If this is a call continuation stub
        else if (auto stub = cast(ContStub)frag)
        {
            auto callInstr = stub.callVer.block.lastInstr;

            stub.markStart(as, vm);

            if (opts.genasm)
                as.comment("Cont stub for " ~ stub.contBranch.getName);

            if (opts.trace_instrs)
                as.printStr("Cont stub for " ~ stub.contBranch.getName);

            as.saveJITRegs();

            // Save the return value
            if (callInstr.hasUses)
            {
                as.setWord(callInstr.outSlot, retWordReg.opnd(64));
                as.setTag(callInstr.outSlot, retTagReg.opnd(8));
            }

            // The first argument is the stub object
            as.ptr(cargRegs[0], stub);

            // Call the JIT compilation function,
            auto compileFn = &compileCont;
            as.ptr(scrRegs[0], compileFn);
            as.call(scrRegs[0]);

            as.loadJITRegs();

            // Restore the return value
            if (callInstr.hasUses)
            {
                as.getWord(retWordReg.reg(64), callInstr.outSlot);
                as.getTag(retTagReg.reg(8), callInstr.outSlot);
            }

            // Jump to the compiled continuation
            as.jmp(X86Opnd(cretReg));

            stub.markEnd(as, vm);

            // Set the return address entry for this stub
            vm.setRetEntry(
                callInstr,
                stub,
                stub.callVer.targets[1]
            );
        }

        else
        {
            assert (false, "invalid code fragment");
        }

        if (opts.dumpasm && frag.length > 0)
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
            if (opts.dumpinfo)
                writefln("linking ref to %s, offset=%s", target.getName, offset);
            break;

            case 64:
            as.writeInt(cast(int64_t)target.getCodePtr(as), 64);
            if (opts.dumpinfo)
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

    if (opts.dumpinfo)
    {
        writeln("write pos: ", as.getWritePos, " / ", as.getRemSpace);
        writeln("num blocks: ", stats.numBlocks);
        writeln("num versions: ", stats.numVersions);
        writeln();
    }

    // Unset the current instruction
    vm.setCurInstr(null);

    //writeln("leaving compile");
}

/// Unit function entry point
alias extern (C) void function() EntryFn;

/**
Compile an entry point for a unit-level function
*/
EntryFn compileUnit(VM vm, IRFunction fun)
{
    // Start recording compilation time
    stats.compTimeStart();

    assert (fun.isUnit, "compileUnit on non-unit function");

    if (opts.dumpinfo)
        writeln("compiling unit ", fun.getName);

    auto as = vm.execHeap;

    //
    // Create the return branch code
    //

    auto retEdge = new ExitCode(fun);
    retEdge.markStart(as, vm);

    if (opts.trace_instrs)
        as.printStr("Unit return branch for " ~ fun.getName);

    // Push one slot for the return value
    as.sub(tspReg.opnd, X86Opnd(1));
    as.sub(wspReg.opnd, X86Opnd(8));

    // Place the return value on top of the stack
    as.setWord(0, retWordReg.opnd);
    as.setTag(0, retTagReg.opnd);

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

    debug
    {
        as.checkStackAlign("stack unaligned at unit exit for " ~ fun.getName);
    }

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
    auto entryInst = getBlockVersion(
        fun.entryBlock,
        new CodeGenState(fun)
    );

    // Mark the code start index
    entryInst.markStart(as, vm);

    as.comment("unit " ~ fun.getName);

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

    // Set the "this" argument (global object)
    as.getMember!("VM.globalObj.word")(scrRegs[0], vmReg);
    as.setWord(-2, scrRegs[0].opnd);
    as.setTag(-2, Tag.OBJECT);

    // Set the closure argument (null)
    as.setWord(-3, X86Opnd(0));

    // Set the return address
    as.ptr(scrRegs[0], retAddr);
    as.setWord(-4, scrRegs[0].opnd);

    // Push space for the callee locals
    as.sub(tspReg.opnd, X86Opnd(1 * fun.numLocals));
    as.sub(wspReg.opnd, X86Opnd(8 * fun.numLocals));

    debug
    {
        as.checkStackAlign("stack unaligned at unit entry");
    }

    // Compile the unit entry version
    vm.compile(null);

    // Set the return address entry for this call
    vm.setRetEntry(null, retEdge, null);

    // Get a pointer to the entry block version's code
    auto entryFn = cast(EntryFn)entryInst.getCodePtr(vm.execHeap);

    // Stop recording compilation time
    stats.compTimeStop();

    // Return the unit entry function
    return entryFn;
}

/**
Compile an entry block instance for a function
*/
extern (C) CodePtr compileEntry(EntryStub stub)
{
    // Stop recording execution time, start recording compilation time
    stats.execTimeStop();
    stats.compTimeStart();

    if (opts.dumpinfo)
    {
        writeln("entering compileEntry");
    }

    auto vm = stub.vm;

    // Get the closure and IRFunction pointers
    auto argCount = vm.getWord(3).uint32Val;
    auto closPtr = vm.getWord(1).ptrVal;
    assert (
        closPtr !is null,
        "closure pointer is null in compileEntry"
    );
    auto fun = getFunPtr(closPtr);
    assert (
        fun !is null,
        "closure IRFunction is null"
    );

    if (opts.dumpinfo)
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
    try
    {
        fun.entryBlock = null;
        astToIR(vm, fun.ast, fun);
    }
    catch (Error err)
    {
        assert (
            false, 
            "failed to generate IR for: \"" ~ fun.getName ~ "\"\n" ~
            err.toString
        );
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
        new CodeGenState(fun)
    );

    /*
    // warning, ctor is first on queue
    auto as = vm.execHeap;
    entryInst.markStart(as, vm);
    as.getMember!"VM.tsp"(scrRegs[0], vmReg);
    as.getMember!"VM.tStack"(scrRegs[1], vmReg);

    as.cmp(scrRegs[0].opnd, scrRegs[1].opnd);
    as.jle(Label.TRUE);
    as.jmp(Label.FALSE);
    as.label(Label.TRUE);

    as.printStr("stack limit exceeded");
    //as.printStack(fun.getCtx(ctorCall, vm));
    as.mov(scrRegs[0].opnd, X86Opnd(0));
    as.jmp(scrRegs[0].opnd);

    as.label(Label.FALSE);
    as.linkLabels();
    */

    // Compile the entry versions
    // Note: the entry code pointer is set in the compile function
    vm.compile(fun.entryBlock.firstInstr);

    // Store the entry code pointer on the function
    //fun.entryCode = entryInst.getCodePtr(vm.execHeap);

    if (opts.dumpinfo)
    {
        writeln("leaving compileEntry");
    }

    // Stop recording compilation time, resume recording execution time
    stats.compTimeStop();
    stats.execTimeStart();

    return fun.entryCode;
}

/**
Compile the branch code when a branch stub is hit
*/
extern (C) CodePtr compileBranch(VM vm, uint32_t blockIdx, uint32_t targetIdx)
{
    // Stop recording execution time, start recording compilation time
    stats.execTimeStop();
    stats.compTimeStart();

    if (opts.dumpinfo)
    {
        writeln("entering compileBranch");
        writeln("blockIdx=", blockIdx);
        writeln("targetIdx=", targetIdx);
    }

    // Get the block from which the stub hit originated
    assert (blockIdx < vm.fragList.length, "invalid block idx");
    auto srcBlock = cast(BlockVersion)vm.fragList[blockIdx];
    assert (srcBlock !is null);

    // Get the branch edge
    assert (targetIdx < srcBlock.targets.length);
    auto branchCode = cast(BranchCode)srcBlock.targets[targetIdx];
    assert (branchCode !is null);
    assert (branchCode.started is false, "branchCode already compiled");
    auto predState = branchCode.predState;
    auto targetBlock = branchCode.branch.target;

    if (opts.dumpinfo)
    {
        writefln(
            "branch from %s to %s",
            srcBlock.block.getName,
            branchCode.branch.target.getName
        );
    }

    auto spillTest = delegate bool(LiveInfo liveInfo, IRDstValue val)
    {
        return liveInfo.liveAtEntry(val, targetBlock);
    };

    // Spill the saved registers
    predState.spillSavedRegs(spillTest);

    // Queue the branch edge to be compiled
    vm.queue(branchCode);

    // Rewrite the final branch of the source block
    srcBlock.regenBranch(vm.execHeap, blockIdx);

    // Compile fragments and patch references
    vm.compile(branchCode.branch.target.firstInstr);

    // Reload the saved registers
    predState.loadSavedRegs(spillTest);

    // Stop recording compilation time, resume recording execution time
    stats.compTimeStop();
    stats.execTimeStart();

    if (opts.dumpinfo)
    {
        writeln("leaving compileBranch");
        writeln();
    }

    // Return a pointer to the compiled branch code
    return branchCode.getCodePtr(vm.execHeap);
}

/**
Called when a call continuation stub is hit, compiles the continuation
*/
extern (C) CodePtr compileCont(ContStub stub)
{
    // Stop recording execution time, start recording compilation time
    stats.execTimeStop();
    stats.compTimeStart();

    if (opts.dumpinfo)
    {
        writeln("entering compileCont");
    }

    auto callVer = stub.callVer;
    auto contBranch = stub.contBranch;
    auto vm = callVer.state.fun.vm;

    // Queue the continuation branch edge to be compiled
    assert (!contBranch.started);
    vm.queue(contBranch);

    // Update the continuation target in the call version
    stub.callVer.targets[0] = contBranch;

    // Rewrite the final branch of the call block
    stub.callVer.regenBranch(vm.execHeap, 0);

    // Compile fragments and patch references
    vm.compile(contBranch.branch.target.firstInstr);

    // Patch the stub to jump to the continuation branch
    stub.patch(vm.execHeap, contBranch);

    // Set the return entry for the call continuation
    vm.setRetEntry(
        callVer.block.lastInstr,
        contBranch,
        callVer.targets[1]
    );

    // Stop recording compilation time, resume recording execution time
    stats.compTimeStop();
    stats.execTimeStart();

    if (opts.dumpinfo)
    {
        writeln("leaving compileCont");
    }

    // Return a pointer to the compiled branch code
    return contBranch.getCodePtr(vm.execHeap);
}

/**
Get a function entry stub
*/
CodePtr getEntryStub(VM vm, bool ctorCall)
{
    auto as = vm.execHeap;

    if (vm.entryStub)
        return vm.entryStub.getCodePtr(as);

    auto stub = new EntryStub(vm, ctorCall);

    stub.markStart(as, vm);

    as.saveJITRegs();

    debug
    {
        as.checkStackAlign("stack unaligned before compileEntry");
    }

    // Call the JIT compile function,
    // passing it a pointer to the stub
    auto compileFn = &compileEntry;
    as.ptr(scrRegs[0], compileFn);
    as.ptr(cargRegs[0], stub);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Jump to the compiled version
    as.jmp(X86Opnd(RAX));

    stub.markEnd(as, vm);

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

    auto stub = new BranchStub(vm, targetIdx);
    vm.branchStubs.length = targetIdx + 1;
    vm.branchStubs[targetIdx] = stub;

    stub.markStart(as, vm);

    // Insert the label for this block in the out of line code
    as.comment("Branch stub (target " ~ to!string(targetIdx) ~ ")");

    //as.printStr("hit branch stub (target " ~ to!string(targetIdx) ~ ")");
    //as.printUint(scrRegs[0].opnd);

    // Save the allocatable registers
    as.saveAllocRegs();

    as.saveJITRegs();

    // The first argument is the VM object
    as.mov(cargRegs[0].opnd, vmReg.opnd);

    // The second argument is the src block index,
    // which was passed in scrRegs[0]
    as.mov(cargRegs[1].opnd(32), scrRegs[0].opnd(32));

    // The third argument is the branch target index
    as.mov(cargRegs[2].opnd(32), X86Opnd(targetIdx));

    debug
    {
        as.checkStackAlign("stack unaligned before compileBranch");
    }

    // Call the JIT compilation function,
    auto compileFn = &compileBranch;
    as.ptr(scrRegs[0], compileFn);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Restore the allocatable registers
    as.loadAllocRegs();

    // Jump to the compiled version
    as.jmp(cretReg.opnd);

    // Store the code end index
    stub.markEnd(as, vm);

    return stub;
}

