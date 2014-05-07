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

module jit.ops;

import core.memory;
import std.c.math;
import std.stdio;
import std.string;
import std.array;
import std.stdint;
import std.conv;
import std.algorithm;
import std.traits;
import std.datetime;
import options;
import stats;
import parser.parser;
import ir.ir;
import ir.ops;
import ir.ast;
import ir.livevars;
import ir.typeprop;
import runtime.vm;
import runtime.layout;
import runtime.object;
import runtime.string;
import runtime.gc;
import jit.codeblock;
import jit.x86;
import jit.util;
import jit.jit;
import core.sys.posix.dlfcn;

/// Instruction code generation function
alias void function(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
) GenFn;

/// Get an argument by index
void gen_get_arg(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Get the first argument slot
    auto argSlot = instr.block.fun.argcVal.outSlot + 1;

    // Get the argument index
    auto idxOpnd = st.getWordOpnd(as, instr, 0, 32, scrRegs[0].opnd(32), false);
    assert (idxOpnd.isGPR);
    auto idxReg32 = idxOpnd.reg.opnd(32);
    auto idxReg64 = idxOpnd.reg.opnd(64);

    // Get the output operand
    auto opndOut = st.getOutOpnd(as, instr, 64);

    // Zero-extend the index to 64-bit
    as.mov(idxReg32, idxReg32);

    // TODO: optimize for immediate idx, register opndOut
    // Copy the word value
    auto wordSlot = X86Opnd(64, wspReg, 8 * argSlot, 8, idxReg64.reg);
    as.mov(scrRegs[1].opnd(64), wordSlot);
    as.mov(opndOut, scrRegs[1].opnd(64));

    // Copy the type value
    auto typeSlot = X86Opnd(8, tspReg, 1 * argSlot, 1, idxReg64.reg);
    as.mov(scrRegs[1].opnd(8), typeSlot);
    st.setOutType(as, instr, scrRegs[1].reg(8));
}

void gen_set_str(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto linkVal = cast(IRLinkIdx)instr.getArg(1);
    assert (linkVal !is null);

    if (linkVal.linkIdx is NULL_LINK)
    {
        auto vm = st.callCtx.vm;

        // Find the string in the string table
        auto strArg = cast(IRString)instr.getArg(0);
        assert (strArg !is null);
        auto strPtr = getString(vm, strArg.str);

        // Allocate a link table entry
        linkVal.linkIdx = vm.allocLink();

        vm.setLinkWord(linkVal.linkIdx, Word.ptrv(strPtr));
        vm.setLinkType(linkVal.linkIdx, Type.STRING);
    }

    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.getMember!("VM.wLinkTable")(scrRegs[0], vmReg);

    auto linkOpnd = X86Opnd(64, scrRegs[0], 8 * linkVal.linkIdx);

    if (outOpnd.isMem)
    {
        as.mov(scrRegs[0].opnd(64), linkOpnd);
        as.mov(outOpnd, scrRegs[0].opnd(64));
    }
    else
    {
        as.mov(outOpnd, linkOpnd);
    }

    st.setOutType(as, instr, Type.STRING);
}

void gen_make_value(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Move the word value into the output word,
    // allow reusing the input register
    auto wordOpnd = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64), true);
    auto outOpnd = st.getOutOpnd(as, instr, 64, true);
    if (outOpnd != wordOpnd)
        as.mov(outOpnd, wordOpnd);

    // Get the type value from the second operand
    auto typeOpnd = st.getWordOpnd(as, instr, 1, 8, scrRegs[0].opnd(8));
    assert (typeOpnd.isGPR);
    st.setOutType(as, instr, typeOpnd.reg);
}

void gen_get_word(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto wordOpnd = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64), true);
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.mov(outOpnd, wordOpnd);

    st.setOutType(as, instr, Type.INT64);
}

void gen_get_type(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto typeOpnd = st.getTypeOpnd(as, instr, 0, scrRegs[0].opnd(8), true);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    if (typeOpnd.isImm)
    {
        as.mov(outOpnd, typeOpnd);
    }
    else if (outOpnd.isGPR)
    {
        as.movzx(outOpnd, typeOpnd);
    }
    else
    {
        as.movzx(scrRegs[0].opnd(32), typeOpnd);
        as.mov(outOpnd, scrRegs[0].opnd(32));
    }

    st.setOutType(as, instr, Type.INT32);
}

void gen_i32_to_f64(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto opnd0 = st.getWordOpnd(as, instr, 0, 32, scrRegs[0].opnd(32), false, false);
    assert (opnd0.isReg);
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    // Sign-extend the 32-bit integer to 64-bit
    as.movsx(scrRegs[1].opnd(64), opnd0);

    as.cvtsi2sd(X86Opnd(XMM0), opnd0);

    as.movq(outOpnd, X86Opnd(XMM0));
    st.setOutType(as, instr, Type.FLOAT64);
}

void gen_f64_to_i32(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd(XMM0), false, false);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    if (!opnd0.isXMM)
        as.movq(X86Opnd(XMM0), opnd0);

    // Cast to int64 and truncate to int32 (to match JS semantics)
    as.cvttsd2si(scrRegs[0].opnd(64), X86Opnd(XMM0));
    as.mov(outOpnd, scrRegs[0].opnd(32));

    st.setOutType(as, instr, Type.INT32);
}

void RMMOp(string op, size_t numBits, Type typeTag)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Should be mem or reg
    auto opnd0 = st.getWordOpnd(
        as,
        instr,
        0,
        numBits,
        scrRegs[0].opnd(numBits),
        true
    );

    // May be reg or immediate
    auto opnd1 = st.getWordOpnd(
        as,
        instr,
        1,
        numBits,
        scrRegs[1].opnd(numBits),
        true
    );

    // Allow reusing an input register for the output,
    // except for subtraction which is not commutative
    auto opndOut = st.getOutOpnd(as, instr, numBits, op != "sub");

    if (op == "imul")
    {
        // imul does not support memory operands as output
        auto outReg = opndOut.isReg? opndOut:scrRegs[2].opnd(numBits);

        // TODO: handle this at the peephole level, assert not happening here
        if (opnd0.isImm && opnd1.isImm)
        {
            as.mov(outReg, opnd0);
            as.mov(scrRegs[0].opnd(numBits), opnd1);
            as.imul(outReg, scrRegs[0].opnd(numBits));
        }
        else if (opnd0.isImm)
        {
            as.imul(outReg, opnd1, opnd0);
        }
        else if (opnd1.isImm)
        {
            as.imul(outReg, opnd0, opnd1);
        }
        else if (opnd0 == opndOut)
        {
            as.imul(outReg, opnd1);
        }
        else if (opnd1 == opndOut)
        {
            as.imul(outReg, opnd0);
        }
        else
        {
            as.mov(outReg, opnd0);
            as.imul(outReg, opnd1);
        }

        if (outReg != opndOut)
            as.mov(opndOut, outReg);
    }
    else
    {
        if (opnd0 == opndOut)
        {
            mixin(format("as.%s(opndOut, opnd1);", op));
        }
        else if (opnd1 == opndOut)
        {
            // Note: the operation has to be commutative for this to work
            mixin(format("as.%s(opndOut, opnd0);", op));
        }
        else
        {
            // Neither input operand is the output
            as.mov(opndOut, opnd0);
            mixin(format("as.%s(opndOut, opnd1);", op));
        }
    }

    // Set the output type
    st.setOutType(as, instr, typeTag);

    // If the instruction has an exception/overflow target
    if (instr.getTarget(0))
    {
        auto branchNO = getBranchEdge(instr.getTarget(0), st, false);
        auto branchOV = getBranchEdge(instr.getTarget(1), st, false);

        // Generate the branch code
        ver.genBranch(
            as,
            branchNO,
            branchOV,
            delegate void(
                CodeBlock as,
                VM vm,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                final switch (shape)
                {
                    case BranchShape.NEXT0:
                    jo32Ref(as, vm, target1, 1);
                    break;

                    case BranchShape.NEXT1:
                    jno32Ref(as, vm, target0, 0);
                    break;

                    case BranchShape.DEFAULT:
                    jo32Ref(as, vm, target1, 1);
                    jmp32Ref(as, vm, target0, 0);
                }
            }
        );
    }
}

alias RMMOp!("add" , 32, Type.INT32) gen_add_i32;
alias RMMOp!("sub" , 32, Type.INT32) gen_sub_i32;
alias RMMOp!("imul", 32, Type.INT32) gen_mul_i32;
alias RMMOp!("and" , 32, Type.INT32) gen_and_i32;
alias RMMOp!("or"  , 32, Type.INT32) gen_or_i32;
alias RMMOp!("xor" , 32, Type.INT32) gen_xor_i32;

alias RMMOp!("add" , 32, Type.INT32) gen_add_i32_ovf;
alias RMMOp!("sub" , 32, Type.INT32) gen_sub_i32_ovf;
alias RMMOp!("imul", 32, Type.INT32) gen_mul_i32_ovf;

void gen_add_ptr_i32(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Should be mem or reg
    auto opnd0 = st.getWordOpnd(
        as,
        instr,
        0,
        64,
        scrRegs[0].opnd(64),
        false
    );

    // May be reg or immediate
    auto opnd1 = st.getWordOpnd(
        as,
        instr,
        1,
        32,
        scrRegs[1].opnd(32),
        true
    );

    auto opndOut = st.getOutOpnd(as, instr, 64);

    // Zero-extend the integer operand to 64-bits
    as.mov(scrRegs[1].opnd(32), opnd1);

    as.mov(opndOut, opnd0);
    as.add(opndOut, scrRegs[1].opnd);

    // Set the output type
    st.setOutType(as, instr, Type.RAWPTR);
}

void divOp(string op)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Spill EAX and EDX (used by the idiv instruction)
    st.spillReg(as, EAX);
    st.spillReg(as, EDX);

    auto opnd0 = st.getWordOpnd(as, instr, 0, 32, X86Opnd.NONE, true, false);
    auto opnd1 = st.getWordOpnd(as, instr, 1, 32, scrRegs[1].opnd(32), false, false);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    as.mov(EAX.opnd, opnd0);

    if (opnd1 == EDX.opnd(32))
    {
        assert (scrRegs[1] != RAX && scrRegs[1] != RDX);
        as.mov(scrRegs[1].opnd(32), opnd1);
        opnd1 = scrRegs[1].opnd(32);
    }

    // Sign-extend EAX into EDX:EAX
    as.cdq();

    // Signed divide/quotient EDX:EAX by r/m32
    as.idiv(opnd1);

    // Store the divisor or remainder into the output operand
    static if (op == "div")
        as.mov(outOpnd, EAX.opnd);
    else if (op == "mod")
        as.mov(outOpnd, EDX.opnd);
    else
        assert (false);

    // Set the output type
    st.setOutType(as, instr, Type.INT32);
}

alias divOp!("div") gen_div_i32;
alias divOp!("mod") gen_mod_i32;

void gen_not_i32(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto opnd0 = st.getWordOpnd(as, instr, 0, 32, scrRegs[0].opnd(32), true);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    as.mov(outOpnd, opnd0);
    as.not(outOpnd);

    // Set the output type
    st.setOutType(as, instr, Type.INT32);
}

void ShiftOp(string op)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    //auto startPos = as.getWritePos;

    // TODO: need way to allow reusing arg 0 reg only, but not arg1
    auto opnd0 = st.getWordOpnd(as, instr, 0, 32, X86Opnd.NONE, true);
    auto opnd1 = st.getWordOpnd(as, instr, 1, 8, X86Opnd.NONE, true);
    auto outOpnd = st.getOutOpnd(as, instr, 32, false);

    auto shiftOpnd = outOpnd;

    // If the shift amount is a constant
    if (opnd1.isImm)
    {
        // Truncate the shift amount bits
        opnd1 = X86Opnd(opnd1.imm.imm & 31);

        // If opnd0 is not shiftOpnd (or is a constant)
        if (opnd0 != shiftOpnd)
            as.mov(shiftOpnd, opnd0);
    }
    else
    {
        // Spill the CL register if needed
        if (opnd1 != CL.opnd(8) && outOpnd != CL.opnd(32))
            st.spillReg(as, CL);

        // If outOpnd is CL, the shift amount register
        if (outOpnd == CL.opnd(32))
        {
            // Use a different register for the shiftee
            shiftOpnd = scrRegs[0].opnd(32);
        }

        // If opnd0 is not shiftOpnd (or is a constant)
        if (opnd0 != shiftOpnd)
            as.mov(shiftOpnd, opnd0);

        // If the shift amount is not already in CL
        if (opnd1 != CL.opnd(8))
        {
            as.mov(CL.opnd, opnd1);
            opnd1 = CL.opnd;
        }
    }

    static if (op == "sal")
        as.sal(shiftOpnd, opnd1);
    else if (op == "sar")
        as.sar(shiftOpnd, opnd1);
    else if (op == "shr")
        as.shr(shiftOpnd, opnd1);
    else
        assert (false);

    if (shiftOpnd != outOpnd)
        as.mov(outOpnd, shiftOpnd);

    // Set the output type
    st.setOutType(as, instr, Type.INT32);
}

alias ShiftOp!("sal") gen_lsft_i32;
alias ShiftOp!("sar") gen_rsft_i32;
alias ShiftOp!("shr") gen_ursft_i32;

void FPOp(string op)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    X86Opnd opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd(XMM0));
    X86Opnd opnd1 = st.getWordOpnd(as, instr, 1, 64, X86Opnd(XMM1));
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    assert (opnd0.isReg && opnd1.isReg);

    if (opnd0.isGPR)
        as.movq(X86Opnd(XMM0), opnd0);
    if (opnd1.isGPR)
        as.movq(X86Opnd(XMM1), opnd1);

    static if (op == "add")
        as.addsd(X86Opnd(XMM0), X86Opnd(XMM1));
    else if (op == "sub")
        as.subsd(X86Opnd(XMM0), X86Opnd(XMM1));
    else if (op == "mul")
        as.mulsd(X86Opnd(XMM0), X86Opnd(XMM1));
    else if (op == "div")
        as.divsd(X86Opnd(XMM0), X86Opnd(XMM1));
    else
        assert (false);

    as.movq(outOpnd, X86Opnd(XMM0));

    // Set the output type
    st.setOutType(as, instr, Type.FLOAT64);
}

alias FPOp!("add") gen_add_f64;
alias FPOp!("sub") gen_sub_f64;
alias FPOp!("mul") gen_mul_f64;
alias FPOp!("div") gen_div_f64;

void HostFPOp(alias cFPFun, size_t arity = 1)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    assert (arity is 1 || arity is 2);

    // Spill the values live before the instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);
    as.movq(X86Opnd(XMM0), opnd0);

    static if (arity is 2)
    {
        auto opnd1 = st.getWordOpnd(as, instr, 1, 64, X86Opnd.NONE, false, false);
        as.movq(X86Opnd(XMM1), opnd1);
    }

    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the host function
    as.ptr(scrRegs[0], &cFPFun);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Store the output value into the output operand
    as.movq(outOpnd, X86Opnd(XMM0));

    st.setOutType(as, instr, Type.FLOAT64);
}

alias HostFPOp!(std.c.math.sin) gen_sin_f64;
alias HostFPOp!(std.c.math.cos) gen_cos_f64;
alias HostFPOp!(std.c.math.sqrt) gen_sqrt_f64;
alias HostFPOp!(std.c.math.ceil) gen_ceil_f64;
alias HostFPOp!(std.c.math.floor) gen_floor_f64;
alias HostFPOp!(std.c.math.log) gen_log_f64;
alias HostFPOp!(std.c.math.exp) gen_exp_f64;
alias HostFPOp!(std.c.math.pow, 2) gen_pow_f64;
alias HostFPOp!(std.c.math.fmod, 2) gen_mod_f64;

void FPToStr(string fmt)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr toStrFn(VM vm, IRInstr curInstr, double f)
    {
        vm.setCurInstr(curInstr);

        auto str = getString(vm, to!wstring(format(fmt, f)));

        vm.setCurInstr(null);

        return str;
    }

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);

    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.movq(X86Opnd(XMM0), opnd0);
    as.ptr(scrRegs[0], &toStrFn);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Store the output value into the output operand
    as.mov(outOpnd, X86Opnd(RAX));

    st.setOutType(as, instr, Type.STRING);
}

alias FPToStr!("%G") gen_f64_to_str;
alias FPToStr!(format("%%.%sf", float64.dig)) gen_f64_to_str_lng;

void LoadOp(size_t memSize, bool signed, Type typeTag)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // The pointer operand must be a register
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64));
    assert (opnd0.isGPR);

    // The offset operand may be a register or an immediate
    auto opnd1 = st.getWordOpnd(as, instr, 1, 32, scrRegs[1].opnd(32), true);

    //auto outOpnd = st.getOutOpnd(as, instr, 64);
    auto outOpnd = st.getOutOpnd(as, instr, (memSize < 64)? 32:64);

    // Create the memory operand
    X86Opnd memOpnd;
    if (opnd1.isImm)
    {
        memOpnd = X86Opnd(memSize, opnd0.reg, cast(int32_t)opnd1.imm.imm);
    }
    else if (opnd1.isGPR)
    {
        // Zero-extend the offset from 32 to 64 bits
        as.mov(opnd1, opnd1);
        memOpnd = X86Opnd(memSize, opnd0.reg, 0, 1, opnd1.reg.reg(64));
    }
    else
    {
        assert (false, "invalid offset operand");
    }

    // If the output operand is a memory location
    if (outOpnd.isMem)
    {
        auto scrReg = scrRegs[2].opnd((memSize < 64)? 32:64);

        // Load to a scratch register first
        static if (memSize < 32)
        {
            static if (signed)
                as.movsx(scrReg, memOpnd);
            else
                as.movzx(scrReg, memOpnd);
        }
        else
        {
            as.mov(scrReg, memOpnd);
        }

        // Move the scratch register to the output
        as.mov(outOpnd, scrReg);
    }
    else
    {
        // Load to the output register directly
        static if (memSize == 8 || memSize == 16)
        {
            static if (signed)
                as.movsx(outOpnd, memOpnd);
            else
                as.movzx(outOpnd, memOpnd);
        }
        else
        {
            as.mov(outOpnd, memOpnd);
        }
    }

    // Set the output type tag
    st.setOutType(as, instr, typeTag);
}

alias LoadOp!(8 , false, Type.INT32) gen_load_u8;
alias LoadOp!(16, false, Type.INT32) gen_load_u16;
alias LoadOp!(32, false, Type.INT32) gen_load_u32;
alias LoadOp!(64, false, Type.INT64) gen_load_u64;
alias LoadOp!(8 , true , Type.INT32) gen_load_i8;
alias LoadOp!(16, true , Type.INT32) gen_load_i16;
alias LoadOp!(32, true , Type.INT32) gen_load_i32;
alias LoadOp!(64, true, Type.INT64) gen_load_i64;
alias LoadOp!(64, false, Type.FLOAT64) gen_load_f64;
alias LoadOp!(64, false, Type.REFPTR) gen_load_refptr;
alias LoadOp!(64, false, Type.RAWPTR) gen_load_rawptr;
alias LoadOp!(64, false, Type.FUNPTR) gen_load_funptr;
alias LoadOp!(64, false, Type.MAPPTR) gen_load_mapptr;

void StoreOp(size_t memSize, Type typeTag)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // The pointer operand must be a register
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64));
    assert (opnd0.isGPR);

    // The offset operand may be a register or an immediate
    auto opnd1 = st.getWordOpnd(as, instr, 1, 32, scrRegs[1].opnd(32), true);

    // The value operand may be a register or an immediate
    auto opnd2 = st.getWordOpnd(as, instr, 2, memSize, scrRegs[2].opnd(memSize), true);

    // Create the memory operand
    X86Opnd memOpnd;
    if (opnd1.isImm)
    {
        memOpnd = X86Opnd(memSize, opnd0.reg, cast(int32_t)opnd1.imm.imm);
    }
    else if (opnd1.isGPR)
    {
        // Zero-extend the offset from 32 to 64 bits
        as.mov(opnd1, opnd1);
        memOpnd = X86Opnd(memSize, opnd0.reg, 0, 1, opnd1.reg.reg(64));
    }
    else
    {
        assert (false, "invalid offset operand");
    }

    // Store the value into the memory location
    as.mov(memOpnd, opnd2);
}

alias StoreOp!(8 , Type.INT32) gen_store_u8;
alias StoreOp!(16, Type.INT32) gen_store_u16;
alias StoreOp!(32, Type.INT32) gen_store_u32;
alias StoreOp!(64, Type.INT64) gen_store_u64;
alias StoreOp!(8 , Type.INT32) gen_store_i8;
alias StoreOp!(16, Type.INT32) gen_store_i16;
alias StoreOp!(32, Type.INT32) gen_store_i32;
alias StoreOp!(64, Type.INT64) gen_store_u64;
alias StoreOp!(64, Type.FLOAT64) gen_store_f64;
alias StoreOp!(64, Type.REFPTR) gen_store_refptr;
alias StoreOp!(64, Type.RAWPTR) gen_store_rawptr;
alias StoreOp!(64, Type.FUNPTR) gen_store_funptr;
alias StoreOp!(64, Type.MAPPTR) gen_store_mapptr;

void IsTypeOp(Type type)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    //as.printStr(instr.toString);
    //as.printStr("    " ~ instr.block.fun.getName);

    // Get an operand for the value's type
    auto typeOpnd = st.getTypeOpnd(as, instr, 0, X86Opnd.NONE, true);

    auto testResult = TestResult.UNKNOWN;

    // If the type is available through basic block versioning
    if (typeOpnd.isImm)
    {
        // Get the known type
        auto knownType = cast(Type)typeOpnd.imm.imm;

        // Get the test result
        testResult = (type is knownType)? TestResult.TRUE:TestResult.FALSE;
    }

    // If the type analysis was run
    if (opts.jit_typeprop)
    {
        // Get the type analysis result for this value at this instruction
        auto propResult = st.callCtx.fun.typeInfo.argIsType(instr, 0, type);

        //writeln("result: ", propResult);

        // If the analysis yields a known result
        if (propResult != TestResult.UNKNOWN)
        {
            // Warn if the analysis knows more than BBV
            if (testResult == TestResult.UNKNOWN && opts.jit_maxvers > 0)
            {
                writeln(
                    "analysis yields more info than BBV for:\n",
                    instr, "\n",
                    "prop result:\n",
                    propResult, "\n",
                    "in:\n",
                    instr.block.fun,
                    "\n"
                );
            }

            // If there is a contradiction between versioning and the analysis
            if (testResult != TestResult.UNKNOWN && propResult != testResult)
            {
                writeln(
                    "type analysis contradiction for:\n",
                     instr, "\n",
                    "prop result:\n",
                    propResult, "\n",
                    "vers result:\n",
                    testResult, "\n",
                    "in:\n",
                    instr.block.fun,
                    "\n"
                );
                assert (false);
            }

            testResult = propResult;
        }
    }

    // If the type test result is known
    if (testResult != TestResult.UNKNOWN)
    {
        // Get the boolean value of the test
        auto boolResult = testResult is TestResult.TRUE;

        // If this instruction has many uses or is not followed by an if
        if (instr.hasManyUses || ifUseNext(instr) is false)
        {
            auto outOpnd = st.getOutOpnd(as, instr, 64);
            auto outVal = boolResult? TRUE:FALSE;
            as.mov(outOpnd, X86Opnd(outVal.word.int8Val));
            st.setOutType(as, instr, Type.CONST);
        }

        // If our only use is an immediately following if_true
        if (ifUseNext(instr) is true)
        {
            // Get the branch edge
            auto targetIdx = boolResult? 0:1;
            auto branch = getBranchEdge(instr.next.getTarget(targetIdx), st, true);

            // Generate the branch code
            ver.genBranch(
                as,
                branch,
                null,
                delegate void(
                    CodeBlock as,
                    VM vm,
                    CodeFragment target0,
                    CodeFragment target1,
                    BranchShape shape
                )
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        break;

                        case BranchShape.NEXT1:
                        case BranchShape.DEFAULT:
                        jmp32Ref(as, vm, target0, 0);
                    }
                }
            );
        }

        return;
    }

    // Increment the stat counter for this specific kind of type test
    as.incStatCnt(stats.getTypeTestCtr(instr.opcode.mnem), scrRegs[1]);

    // Compare against the tested type
    as.cmp(typeOpnd, X86Opnd(type));

    // If this instruction has many uses or is not followed by an if
    if (instr.hasManyUses || ifUseNext(instr) is false)
    {
        // We must have a register for the output (so we can use cmov)
        auto outOpnd = st.getOutOpnd(as, instr, 64);
        X86Opnd outReg = outOpnd.isReg? outOpnd.reg.opnd(32):scrRegs[0].opnd(32);

        // Generate a boolean output value
        as.mov(outReg, X86Opnd(FALSE.word.int8Val));
        as.mov(scrRegs[1].opnd(32), X86Opnd(TRUE.word.int8Val));
        as.cmove(outReg.reg, scrRegs[1].opnd(32));

        // If the output register is not the output operand
        if (outReg != outOpnd)
            as.mov(outOpnd, outReg.reg.opnd(64));

        // Set the output type
        st.setOutType(as, instr, Type.CONST);
    }

    // If our only use is an immediately following if_true
    if (ifUseNext(instr) is true)
    {
        // If the argument is not a constant, add type information
        // about the argument's type along the true branch
        CodeGenState trueSt = st;
        if (opts.jit_maxvers > 0)
        {
            if (auto dstArg = cast(IRDstValue)instr.getArg(0))
            {
                trueSt = new CodeGenState(trueSt);
                trueSt.setType(dstArg, type);
            }
        }

        // Get branch edges for the true and false branches
        auto branchT = getBranchEdge(instr.next.getTarget(0), trueSt, false);
        auto branchF = getBranchEdge(instr.next.getTarget(1), st, false);

        // Generate the branch code
        ver.genBranch(
            as,
            branchT,
            branchF,
            delegate void(
                CodeBlock as,
                VM vm,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                final switch (shape)
                {
                    case BranchShape.NEXT0:
                    jne32Ref(as, vm, target1, 1);
                    break;

                    case BranchShape.NEXT1:
                    je32Ref(as, vm, target0, 0);
                    break;

                    case BranchShape.DEFAULT:
                    jne32Ref(as, vm, target1, 1);
                    jmp32Ref(as, vm, target0, 0);
                }
            }
        );
    }
}

alias IsTypeOp!(Type.CONST) gen_is_const;
alias IsTypeOp!(Type.INT32) gen_is_i32;
alias IsTypeOp!(Type.INT64) gen_is_i64;
alias IsTypeOp!(Type.FLOAT64) gen_is_f64;
alias IsTypeOp!(Type.RAWPTR) gen_is_rawptr;
alias IsTypeOp!(Type.REFPTR) gen_is_refptr;
alias IsTypeOp!(Type.OBJECT) gen_is_object;
alias IsTypeOp!(Type.ARRAY) gen_is_array;
alias IsTypeOp!(Type.CLOSURE) gen_is_closure;
alias IsTypeOp!(Type.STRING) gen_is_string;

void CmpOp(string op, size_t numBits)(
    BlockVersion ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Check if this is a floating-point comparison
    static bool isFP = op.startsWith("f");

    // The first operand must be memory or register, but not immediate
    auto opnd0 = st.getWordOpnd(
        as,
        instr,
        0,
        numBits,
        scrRegs[0].opnd(numBits),
        false
    );

    // The second operand may be an immediate, unless FP comparison
    auto opnd1 = st.getWordOpnd(
        as,
        instr,
        1,
        numBits,
        scrRegs[1].opnd(numBits),
        isFP? false:true
    );

    // If this is an FP comparison
    if (isFP)
    {
        // Move the operands into XMM registers
        as.movq(X86Opnd(XMM0), opnd0);
        as.movq(X86Opnd(XMM1), opnd1);
        opnd0 = X86Opnd(XMM0);
        opnd1 = X86Opnd(XMM1);
    }

    // We must have a register for the output (so we can use cmov)
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    X86Opnd outReg = outOpnd.isReg? outOpnd.reg.opnd(32):scrRegs[0].opnd(32);

    auto tmpReg = scrRegs[1].opnd(32);
    auto trueOpnd = X86Opnd(TRUE.word.int8Val);
    auto falseOpnd = X86Opnd(FALSE.word.int8Val);

    // Generate a boolean output only if this instruction has
    // many uses or is not followed by an if
    bool genOutput = (instr.hasManyUses || ifUseNext(instr) is false);

    // Integer comparison
    static if (op == "eq")
    {
        as.cmp(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmove(outReg.reg, tmpReg);
        }
    }
    else if (op == "ne")
    {
        as.cmp(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovne(outReg.reg, tmpReg);
        }
    }
    else if (op == "lt")
    {
        as.cmp(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovl(outReg.reg, tmpReg);
        }
    }
    else if (op == "le")
    {
        as.cmp(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovle(outReg.reg, tmpReg);
        }
    }
    else if (op == "gt")
    {
        as.cmp(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovg(outReg.reg, tmpReg);
        }
    }
    else if (op == "ge")
    {
        as.cmp(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovge(outReg.reg, tmpReg);
        }
    }

    // Floating-point comparisons
    // From the Intel manual, EFLAGS are:
    // UNORDERED:    ZF, PF, CF ← 111;
    // GREATER_THAN: ZF, PF, CF ← 000;
    // LESS_THAN:    ZF, PF, CF ← 001;
    // EQUAL:        ZF, PF, CF ← 100;
    else if (op == "feq")
    {
        // feq:
        // True: 100
        // False: 111 or 000 or 001
        // False: JNE + JP
        as.ucomisd(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, trueOpnd);
            as.mov(tmpReg, falseOpnd);
            as.cmovne(outReg.reg, tmpReg);
            as.cmovp(outReg.reg, tmpReg);
        }
    }
    else if (op == "fne")
    {
        // fne: 
        // True: 111 or 000 or 001
        // False: 100
        // True: JNE + JP
        as.ucomisd(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovne(outReg.reg, tmpReg);
            as.cmovp(outReg.reg, tmpReg);
        }
    }
    else if (op == "flt")
    {
        as.ucomisd(opnd1, opnd0);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmova(outReg.reg, tmpReg);
        }
    }
    else if (op == "fle")
    {
        as.ucomisd(opnd1, opnd0);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovae(outReg.reg, tmpReg);
        }
    }
    else if (op == "fgt")
    {
        as.ucomisd(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmova(outReg.reg, tmpReg);
        }
    }
    else if (op == "fge")
    {
        as.ucomisd(opnd0, opnd1);
        if (genOutput)
        {
            as.mov(outReg, falseOpnd);
            as.mov(tmpReg, trueOpnd);
            as.cmovae(outReg.reg, tmpReg);
        }
    }

    else
    {
        assert (false);
    }

    // If we are to generate output
    if (genOutput)
    {
        // If the output register is not the output operand
        if (outReg != outOpnd)
            as.mov(outOpnd, outReg.reg.opnd(64));

        // Set the output type
        st.setOutType(as, instr, Type.CONST);
    }

    // If there is an immediately following if_true using this value
    if (ifUseNext(instr) is true)
    {
        // Get branch edges for the true and false branches
        auto branchT = getBranchEdge(instr.next.getTarget(0), st, false);
        auto branchF = getBranchEdge(instr.next.getTarget(1), st, false);

        // Generate the branch code
        ver.genBranch(
            as,
            branchT,
            branchF,
            delegate void(
                CodeBlock as,
                VM vm,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                // Integer comparison
                static if (op == "eq")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jne32Ref(as, vm, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        je32Ref(as, vm, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        je32Ref(as, vm, target0, 0);
                        jmp32Ref(as, vm, target1, 1);
                    }
                }
                else if (op == "ne")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        je32Ref(as, vm, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jne32Ref(as, vm, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jne32Ref(as, vm, target0, 0);
                        jmp32Ref(as, vm, target1, 1);
                    }
                }
                else if (op == "lt")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jge32Ref(as, vm, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jl32Ref(as, vm, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jl32Ref(as, vm, target0, 0);
                        jmp32Ref(as, vm, target1, 1);
                    }
                }
                else if (op == "le")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jg32Ref(as, vm, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jle32Ref(as, vm, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jle32Ref(as, vm, target0, 0);
                        jmp32Ref(as, vm, target1, 1);
                    }
                }
                else if (op == "gt")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jle32Ref(as, vm, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jg32Ref(as, vm, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jg32Ref(as, vm, target0, 0);
                        jmp32Ref(as, vm, target1, 1);
                    }
                }
                else if (op == "ge")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jl32Ref(as, vm, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jge32Ref(as, vm, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jge32Ref(as, vm, target0, 0);
                        jmp32Ref(as, vm, target1, 1);
                    }
                }

                // Floating-point comparisons
                else if (op == "feq")
                {
                    // feq:
                    // True: 100
                    // False: 111 or 000 or 001
                    // False: JNE + JP
                    jne32Ref(as, vm, target1, 1);
                    jp32Ref(as, vm, target1, 1);
                    jmp32Ref(as, vm, target0, 0);
                }
                else if (op == "fne")
                {
                    // fne: 
                    // True: 111 or 000 or 001
                    // False: 100
                    // True: JNE + JP
                    jne32Ref(as, vm, target0, 0);
                    jp32Ref(as, vm, target0, 0);
                    jmp32Ref(as, vm, target1, 1);
                }
                else if (op == "flt")
                {
                    ja32Ref(as, vm, target0, 0);
                    jmp32Ref(as, vm, target1, 1);
                }
                else if (op == "fle")
                {
                    jae32Ref(as, vm, target0, 0);
                    jmp32Ref(as, vm, target1, 1);
                }
                else if (op == "fgt")
                {
                    ja32Ref(as, vm, target0, 0);
                    jmp32Ref(as, vm, target1, 1);
                }
                else if (op == "fge")
                {
                    jae32Ref(as, vm, target0, 0);
                    jmp32Ref(as, vm, target1, 1);
                }
            }
        );
    }
}

alias CmpOp!("eq", 8) gen_eq_i8;
alias CmpOp!("eq", 32) gen_eq_i32;
alias CmpOp!("ne", 32) gen_ne_i32;
alias CmpOp!("lt", 32) gen_lt_i32;
alias CmpOp!("le", 32) gen_le_i32;
alias CmpOp!("gt", 32) gen_gt_i32;
alias CmpOp!("ge", 32) gen_ge_i32;
alias CmpOp!("eq", 64) gen_eq_i64;

alias CmpOp!("eq", 8) gen_eq_const;
alias CmpOp!("ne", 8) gen_ne_const;
alias CmpOp!("eq", 64) gen_eq_refptr;
alias CmpOp!("ne", 64) gen_ne_refptr;
alias CmpOp!("eq", 64) gen_eq_rawptr;
alias CmpOp!("ne", 64) gen_ne_rawptr;
alias CmpOp!("feq", 64) gen_eq_f64;
alias CmpOp!("fne", 64) gen_ne_f64;
alias CmpOp!("flt", 64) gen_lt_f64;
alias CmpOp!("fle", 64) gen_le_f64;
alias CmpOp!("fgt", 64) gen_gt_f64;
alias CmpOp!("fge", 64) gen_ge_f64;

void gen_if_true(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // If a boolean argument immediately precedes, the
    // conditional branch has already been generated
    if (boolArgPrev(instr) is true)
        return;

    // TODO
    /*
    auto argVal = instr.getArg(0);

    // If the argument is a known constant
    if (st.wordKnown(argVal))
    {
        auto targetT = instr.getTarget(0);
        auto targetF = instr.getTarget(1);

        // TODO: use getWordOpnd
        // TODO: get rid of wordKnown?
        auto argWord = st.getWord(argVal);
        auto target = (argWord == TRUE)? targetT:targetF;
        ctx.genBranchEdge(ctx.as, null, target, st);

        return;
    }
    */

    // Compare the argument to the true boolean value
    auto argOpnd = st.getWordOpnd(as, instr, 0, 8);
    as.cmp(argOpnd, X86Opnd(TRUE.word.int8Val));

    auto branchT = getBranchEdge(instr.getTarget(0), st, false);
    auto branchF = getBranchEdge(instr.getTarget(1), st, false);

    // Generate the branch code
    ver.genBranch(
        as,
        branchT,
        branchF,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            final switch (shape)
            {
                case BranchShape.NEXT0:
                jne32Ref(as, vm, target1, 1);
                break;

                case BranchShape.NEXT1:
                je32Ref(as, vm, target0, 0);
                break;

                case BranchShape.DEFAULT:
                je32Ref(as, vm, target0, 0);
                jmp32Ref(as, vm, target1, 1);
            }
        }
    );
}

void gen_jump(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto branch = getBranchEdge(
        instr.getTarget(0),
        st,
        true
    );

    // Jump to the target block directly
    ver.genBranch(
        as,
        branch,
        null,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            final switch (shape)
            {
                case BranchShape.NEXT0:
                break;

                case BranchShape.NEXT1:
                assert (false);

                case BranchShape.DEFAULT:
                jmp32Ref(as, vm, target0, 0);
            }
        }
    );
}

/**
Throw an exception and unwind the stack when one calls a non-function.
Returns a pointer to an exception handler.
*/
extern (C) CodePtr throwCallExc(
    VM vm,
    IRInstr instr,
    BranchCode excHandler
)
{
    auto fnName = getCalleeName(instr);

    return throwError(
        vm,
        instr,
        excHandler,
        "TypeError",
        fnName?
        ("call to non-function \"" ~ fnName ~ "\""):
        ("call to non-function")
    );
}

/**
Generate the final branch and exception handler for a call instruction
*/
void genCallBranch(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as,
    BranchGenFn genFn,
    bool mayThrow
)
{
    auto vm = st.callCtx.vm;

    // Map the return value to its stack location
    st.mapToStack(instr);

    // Create a branch object for the continuation
    auto contBranch = getBranchEdge(
        instr.getTarget(0),
        st,
        false,
        delegate void(CodeBlock as, VM vm)
        {
            // Move the return value into the instruction's output slot
            if (instr.hasUses)
            {
                as.setWord(instr.outSlot, retWordReg.opnd(64));
                as.setType(instr.outSlot, retTypeReg.opnd(8));
            }
        }
    );

    // Create the continuation branch object
    BranchCode excBranch = null;
    if (instr.getTarget(1))
    {
        excBranch = getBranchEdge(
            instr.getTarget(1),
            st,
            false,
            delegate void(CodeBlock as, VM vm)
            {
                // Pop the exception value off the stack and
                // move it into the instruction's output slot
                as.add(tspReg, Type.sizeof);
                as.add(wspReg, Word.sizeof);
                as.getWord(scrRegs[0], -1);
                as.setWord(instr.outSlot, scrRegs[0].opnd(64));
                as.getType(scrRegs[0].reg(8), -1);
                as.setType(instr.outSlot, scrRegs[0].opnd(8));
            }
        );
    }

    // If the call may throw an exception
    if (mayThrow)
    {
        as.jmp(Label.SKIP);

        as.label(Label.THROW);

        as.saveJITRegs();

        // Throw the call exception, unwind the stack,
        // find the topmost exception handler
        as.mov(cargRegs[0], vmReg);
        as.ptr(cargRegs[1], instr);
        as.ptr(cargRegs[2], excBranch);
        as.ptr(scrRegs[0], &throwCallExc);
        as.call(scrRegs[0].opnd);

        as.loadJITRegs();

        // Jump to the exception handler
        as.jmp(X86Opnd(RAX));

        as.label(Label.SKIP);
    }

    // Create a call continuation stub
    auto contStub = new ContStub(ver, contBranch);
    vm.queue(contStub);

    // Generate the call branch code
    ver.genBranch(
        as,
        contStub,
        excBranch,
        genFn
    );

    //writeln("call block length: ", ver.length);
}

void gen_call_prim(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = st.callCtx.vm;

    // Function name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Increment the stat counter for this primitive
    as.incStatCnt(stats.getPrimCallCtr(to!string(nameStr)), scrRegs[0]);

    // Get the primitve function from the global object
    auto closVal = getProp(vm, vm.globalObj, nameStr);
    assert (closVal.type is Type.CLOSURE);
    assert (closVal.word.ptrVal !is null);
    auto fun = getFunPtr(closVal.word.ptrVal);

    //as.printStr(to!string(nameStr));

    // Check that the argument count matches
    auto numArgs = cast(int32_t)instr.numArgs - 2;
    assert (
        numArgs is fun.numParams,
        "incorrect argument count for primitive call"
    );

    // Check that the hidden arguments are not used
    assert (
        (!fun.closVal || fun.closVal.hasNoUses) &&
        (!fun.thisVal || fun.thisVal.hasNoUses) &&
        (!fun.argcVal || fun.argcVal.hasNoUses),
        "hidden args used"
    );

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
    {
        //writeln("compiling");
        //writeln(core.memory.GC.addrOf(cast(void*)fun.ast));
        astToIR(vm, fun.ast, fun);
    }

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto instrArgIdx = instr.numArgs - (1+i);
        auto dstIdx = -(cast(int32_t)i + 1);

        // Copy the argument word
        auto argOpnd = st.getWordOpnd(
            as,
            instr,
            instrArgIdx,
            64,
            scrRegs[1].opnd(64),
            true,
            false
        );
        as.setWord(dstIdx, argOpnd);

        // Copy the argument type
        auto typeOpnd = st.getTypeOpnd(
            as,
            instr,
            instrArgIdx,
            scrRegs[1].opnd(8),
            true
        );
        as.setType(dstIdx, typeOpnd);
    }

    // Write the argument count
    as.setWord(-numArgs - 1, numArgs);

    // Spill the values that are live after the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveAfter(value, instr);
        }
    );

    // Push space for the callee arguments and locals
    as.sub(X86Opnd(tspReg), X86Opnd(fun.numLocals));
    as.sub(X86Opnd(wspReg), X86Opnd(8 * fun.numLocals));

    // Request an instance for the function entry block
    auto entryVer = getBlockVersion(
        fun.entryBlock,
        new CodeGenState(vm, fun, false),
        true
    );

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            // Get the return address slot of the callee
            auto raSlot = entryVer.block.fun.raVal.outSlot;
            assert (raSlot !is NULL_STACK);

            // Write the return address on the stack
            as.movAbsRef(vm, scrRegs[0], target0, 0);
            as.setWord(raSlot, scrRegs[0].opnd(64));

            // Jump to the function entry block
            jmp32Ref(as, vm, entryVer, 0);
        },
        false
    );
}

void gen_call(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    as.incStatCnt(&stats.numCall, scrRegs[0]);

    // Free an extra register to use as scratch
    auto scrReg3 = st.freeReg(as, instr);

    //
    // Function pointer extraction
    //

    // Get the type tag for the closure value
    auto closType = st.getTypeOpnd(
        as,
        instr,
        0,
        scrRegs[0].opnd(8),
        false
    );

    // If the value is not a closure, bailout
    as.cmp(closType, X86Opnd(Type.CLOSURE));
    as.jne(Label.THROW);

    // Get the word for the closure value
    auto closReg = st.getWordOpnd(
        as,
        instr,
        0,
        64,
        scrRegs[0].opnd(64),
        false,
        false
    );
    assert (closReg.isGPR);

    // Get the IRFunction pointer from the closure object
    auto fptrMem = X86Opnd(64, closReg.reg, FPTR_SLOT_OFS);
    as.mov(scrRegs[1].opnd(64), fptrMem);

    //
    // Function call logic
    //

    auto numArgs = cast(uint32_t)instr.numArgs - 2;

    // Compute -missingArgs = numArgs - numParams
    // This is the negation of the number of missing arguments
    // We use this as an offset when writing arguments to the stack
    auto numParamsOpnd = memberOpnd!("IRFunction.numParams")(scrRegs[1]);
    as.mov(scrRegs[2].opnd(32), X86Opnd(numArgs));
    as.sub(scrRegs[2].opnd(32), numParamsOpnd);
    as.cmp(scrRegs[2].opnd(32), X86Opnd(0));
    as.jle(Label.FALSE);
    as.xor(scrRegs[2].opnd(32), scrRegs[2].opnd(32));
    as.label(Label.FALSE);
    as.movsx(scrRegs[2].opnd(64), scrRegs[2].opnd(32));

    //as.printStr("missing args");
    //as.printInt(scrRegs[2].opnd(64));
    //as.printInt(scrRegs[2].opnd(32));

    // Initialize the missing arguments, if any
    as.mov(scrReg3.opnd(64), scrRegs[2].opnd(64));
    as.label(Label.LOOP);
    as.cmp(scrReg3.opnd(64), X86Opnd(0));
    as.jge(Label.LOOP_EXIT);
    as.mov(X86Opnd(64, wspReg, 0, 8, scrReg3), X86Opnd(UNDEF.word.int8Val));
    as.mov(X86Opnd(8, tspReg, 0, 1, scrReg3), X86Opnd(Type.CONST));
    as.add(scrReg3.opnd(64), X86Opnd(1));
    as.jmp(Label.LOOP);
    as.label(Label.LOOP_EXIT);

    static void movArgWord(CodeBlock as, size_t argIdx, X86Opnd val)
    {
        as.mov(X86Opnd(64, wspReg, -8 * cast(int32_t)(argIdx+1), 8, scrRegs[2]), val);
    }

    static void movArgType(CodeBlock as, size_t argIdx, X86Opnd val)
    {
        as.mov(X86Opnd(8, tspReg, -1 * cast(int32_t)(argIdx+1), 1, scrRegs[2]), val);
    }

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto instrArgIdx = instr.numArgs - (1+i);

        // Copy the argument word
        auto argOpnd = st.getWordOpnd(
            as,
            instr,
            instrArgIdx,
            64,
            scrReg3.opnd(64),
            true,
            false
        );
        movArgWord(as, i, argOpnd);

        // Copy the argument type
        auto typeOpnd = st.getTypeOpnd(
            as,
            instr,
            instrArgIdx,
            scrReg3.opnd(8),
            true
        );
        movArgType(as, i, typeOpnd);
    }

    // Write the argument count
    movArgWord(as, numArgs + 0, X86Opnd(numArgs));

    // Write the "this" argument
    auto thisReg = st.getWordOpnd(
        as,
        instr,
        1,
        64,
        scrReg3.opnd(64),
        true,
        false
    );
    movArgWord(as, numArgs + 1, thisReg);
    auto typeOpnd = st.getTypeOpnd(
        as,
        instr,
        1,
        scrReg3.opnd(8),
        true
    );
    movArgType(as, numArgs + 1, typeOpnd);

    // Write the closure argument
    movArgWord(as, numArgs + 2, closReg);

    // Compute the total number of locals and extra arguments
    // input : scr1, IRFunction
    // output: scr0, total frame size
    // mangle: scr3
    // scr3 = numArgs, actual number of args passed
    as.mov(scrReg3.opnd(32), X86Opnd(numArgs));
    // scr3 = numArgs - numParams (num extra args)
    as.sub(scrReg3.opnd(32), numParamsOpnd);
    // scr0 = numLocals
    as.getMember!("IRFunction.numLocals")(scrRegs[0].reg(32), scrRegs[1]);
    // if there are no missing parameters, skip the add
    as.cmp(scrReg3.opnd(32), X86Opnd(0));
    as.jle(Label.FALSE2);
    // src0 = numLocals + extraArgs
    as.add(scrRegs[0].opnd(32), scrReg3.opnd(32));
    as.label(Label.FALSE2);

    // Spill the values that are live after the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveAfter(value, instr);
        }
    );

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            // Write the return address on the stack
            as.movAbsRef(vm, scrReg3, target0, 0);
            movArgWord(as, numArgs + 3, scrReg3.opnd);

            // Adjust the stack pointers
            //as.printStr("pushing");
            //as.printUint(scrRegs[0].opnd(64));
            as.sub(X86Opnd(tspReg), scrRegs[0].opnd(64));

            // Adjust the word stack pointer
            as.shl(scrRegs[0].opnd(64), X86Opnd(3));
            as.sub(X86Opnd(wspReg), scrRegs[0].opnd(64));

            // Jump to the function entry block
            as.getMember!("IRFunction.entryCode")(scrRegs[0], scrRegs[1]);
            as.jmp(scrRegs[0].opnd(64));
        },
        true
    );
}

/// JavaScript new operator (constructor call)
void gen_call_new(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    /// Host function to allocate the "this" object
    extern (C) refptr makeThisObj(VM vm, IRInstr curInstr, refptr closPtr)
    {
        vm.setCurInstr(curInstr);

        // Get the function object from the closure
        auto clos = GCRoot(vm, closPtr, Type.CLOSURE);
        auto fun = getFunPtr(clos.ptr);

        assert (
            fun !is null,
            "null IRFunction pointer"
        );

        // Lookup the "prototype" property on the closure
        auto protoObj = GCRoot(
            vm,
            getProp(
                vm,
                clos.pair,
                "prototype"w
            )
        );

        // Get the "this" object map from the closure
        auto ctorMap = cast(ObjMap)clos_get_ctor_map(clos.ptr);

        // Lazily allocate the "this" object map if it doesn't already exist
        if (ctorMap is null)
        {
            ctorMap = new ObjMap(vm, 0);
            clos_set_ctor_map(clos.ptr, cast(rawptr)ctorMap);
        }

        // Allocate the "this" object
        auto thisObj = GCRoot(
            vm,
            newObj(
                vm,
                ctorMap,
                protoObj.pair
            )
        );

        vm.setCurInstr(null);

        assert(
            vm.inFromSpace(thisObj.ptr) && ptrValid(thisObj.ptr)
        );

        return thisObj.ptr;
    }

    // TODO: steal an allocatable reg to use as an extra temporary
    // force its contents to be spilled if necessary
    // maybe add State.freeReg method
    auto scrReg3 = allocRegs[$-1];

    // TODO: optimize call spills
    // TODO: move spills after arg copying?
    // Spill the values that are live after the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    //
    // Function pointer extraction
    //

    // Get the type tag for the closure value
    auto closType = st.getTypeOpnd(
        as,
        instr,
        0,
        scrRegs[0].opnd(8),
        false
    );

    // If the value is not a closure, bailout
    as.cmp(closType, X86Opnd(Type.CLOSURE));
    as.jne(Label.THROW);

    // Get the word for the closure value
    auto closReg = st.getWordOpnd(
        as,
        instr,
        0,
        64,
        scrRegs[0].opnd(64),
        false,
        false
    );
    assert (closReg.isGPR);

    // Get the IRFunction pointer from the closure object
    auto fptrMem = X86Opnd(64, closReg.reg, FPTR_SLOT_OFS);
    as.mov(scrRegs[1].opnd(64), fptrMem);

    //
    // Function call logic
    //

    auto numArgs = cast(uint32_t)instr.numArgs - 1;

    //writeln(instr.toString);
    //writeln("numArgs=", numArgs);

    // Compute -missingArgs = numArgs - numParams
    // This is the negation of the number of missing arguments
    // We use this as an offset when writing arguments to the stack
    auto numParamsOpnd = memberOpnd!("IRFunction.numParams")(scrRegs[1]);
    as.mov(scrRegs[2].opnd(32), X86Opnd(numArgs));
    as.sub(scrRegs[2].opnd(32), numParamsOpnd);
    as.cmp(scrRegs[2].opnd(32), X86Opnd(0));
    as.jle(Label.FALSE);
    as.xor(scrRegs[2].opnd(32), scrRegs[2].opnd(32));
    as.label(Label.FALSE);
    as.movsx(scrRegs[2].opnd(64), scrRegs[2].opnd(32));

    //as.printStr("missing args");
    //as.printInt(scrRegs[2].opnd(64));

    // Initialize the missing arguments, if any
    as.mov(scrReg3.opnd(64), scrRegs[2].opnd(64));
    as.label(Label.LOOP);
    as.cmp(scrReg3.opnd(64), X86Opnd(0));
    as.jge(Label.LOOP_EXIT);
    as.mov(X86Opnd(64, wspReg, 0, 8, scrReg3), X86Opnd(UNDEF.word.int8Val));
    as.mov(X86Opnd(8, tspReg, 0, 1, scrReg3), X86Opnd(Type.CONST));
    as.add(scrReg3.opnd(64), X86Opnd(1));
    as.jmp(Label.LOOP);
    as.label(Label.LOOP_EXIT);

    static void movArgWord(CodeBlock as, size_t argIdx, X86Opnd val)
    {
        as.mov(X86Opnd(64, wspReg, -8 * cast(int32_t)(argIdx+1), 8, scrRegs[2]), val);
    }

    static void movArgType(CodeBlock as, size_t argIdx, X86Opnd val)
    {
        as.mov(X86Opnd(8, tspReg, -1 * cast(int32_t)(argIdx+1), 1, scrRegs[2]), val);
    }

    //
    // "this" object allocation
    //

    as.saveJITRegs();
    as.push(scrRegs[1]);
    as.push(scrRegs[2]);

    // Call a host function to allocate the "this" object
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd(64), closReg);
    as.ptr(scrRegs[0], &makeThisObj);
    as.call(scrRegs[0].opnd(64));

    as.pop(scrRegs[2]);
    as.pop(scrRegs[1]);
    as.loadJITRegs();

    // Write the "this" argument
    movArgWord(as, numArgs + 1, cretReg.opnd);
    movArgType(as, numArgs + 1, X86Opnd(Type.OBJECT));

    //
    // Argument copying
    //

    // Write the argument count
    movArgWord(as, numArgs + 0, X86Opnd(numArgs));

    // Write the closure argument
    // Note: the closure may have been moved during GC
    closReg = st.getWordOpnd(
        as,
        instr,
        0,
        64,
        scrRegs[0].opnd(64),
        false,
        false
    );
    movArgWord(as, numArgs + 2, closReg);

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto instrArgIdx = instr.numArgs - (1+i);

        // Copy the argument word
        auto argOpnd = st.getWordOpnd(
            as,
            instr,
            instrArgIdx,
            64,
            scrReg3.opnd(64),
            true,
            false
        );
        movArgWord(as, i, argOpnd);

        // Copy the argument type
        auto typeOpnd = st.getTypeOpnd(
            as,
            instr,
            instrArgIdx,
            scrReg3.opnd(8),
            true
        );
        movArgType(as, i, typeOpnd);
    }

    //
    // Final branch generation
    //

    // Compute the total number of locals and extra arguments
    // input : scr1, IRFunction
    // output: scr0, total frame size
    // mangle: scr3
    // scr3 = numArgs, actual number of args passed
    as.mov(scrReg3.opnd(32), X86Opnd(numArgs));
    // scr3 = numArgs - numParams (num extra args)
    as.sub(scrReg3.opnd(32), numParamsOpnd);
    // scr0 = numLocals
    as.getMember!("IRFunction.numLocals")(scrRegs[0].reg(32), scrRegs[1]);
    // if there are no missing parameters, skip the add
    as.cmp(scrReg3.opnd(32), X86Opnd(0));
    as.jle(Label.FALSE2);
    // src0 = numLocals + extraArgs
    as.add(scrRegs[0].opnd(32), scrReg3.opnd(32));
    as.label(Label.FALSE2);

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            // Write the return address on the stack
            as.movAbsRef(vm, scrReg3, target0, 0);
            movArgWord(as, numArgs + 3, scrReg3.opnd);

            // Adjust the stack pointers
            //as.printStr("pushing");
            //as.printUint(scrRegs[0].opnd(64));
            as.sub(X86Opnd(tspReg), scrRegs[0].opnd(64));
            as.shl(scrRegs[0].opnd(64), X86Opnd(3));
            as.sub(X86Opnd(wspReg), scrRegs[0].opnd(64));

            // Jump to the function entry block
            as.getMember!("IRFunction.ctorCode")(scrRegs[0], scrRegs[1]);
            as.jmp(scrRegs[0].opnd(64));
        },
        true
    );
}

void gen_call_apply(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) CodePtr op_call_apply(
        VM vm,
        IRInstr instr,
        CodePtr retAddr
    )
    {
        vm.setCurInstr(instr);

        auto closVal = vm.getArgVal(instr, 0);
        auto thisVal = vm.getArgVal(instr, 1);
        auto tblVal  = vm.getArgVal(instr, 2);
        auto argcVal = vm.getArgUint32(instr, 3);

        assert (
            tblVal.type !is Type.ARRAY,
            "invalid argument table"
        );

        assert (
            closVal.type is Type.CLOSURE,
            "apply call on to non-function"
        );

        // Get the function object from the closure
        auto closPtr = closVal.word.ptrVal;
        auto fun = getFunPtr(closPtr);

        // Get the array table pointer
        auto tblPtr = tblVal.word.ptrVal;

        auto argVals = cast(ValuePair*)GC.malloc(ValuePair.sizeof * argcVal);

        // Fetch the argument values from the array table
        for (uint32_t i = 0; i < argcVal; ++i)
        {
            argVals[i].word.uint64Val = arrtbl_get_word(tblPtr, i);
            argVals[i].type = cast(Type)arrtbl_get_type(tblPtr, i);
        }

        // Prepare the callee stack frame
        vm.callFun(
            fun,
            retAddr,
            closPtr,
            thisVal,
            argcVal,
            argVals
        );

        GC.free(argVals);

        vm.setCurInstr(null);

        // Return the function entry point code
        return fun.entryCode;
    }

    // TODO: optimize call spills
    // TODO: move spills after arg copying?
    // Spill the values that are live after the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            as.saveJITRegs();

            // Pass the call context and instruction as first two arguments
            as.mov(cargRegs[0], vmReg);
            as.ptr(cargRegs[1], instr);

            // Pass the return address as third argument
            as.movAbsRef(vm, cargRegs[2], target0, 0);

            // Call the host function
            as.ptr(scrRegs[0], &op_call_apply);
            as.call(scrRegs[0]);

            as.loadJITRegs();

            // Jump to the address returned by the host function
            as.jmp(cretReg.opnd);
        },
        false
    );
}

void gen_load_file(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) CodePtr op_load_file(
        VM vm,
        IRInstr instr,
        CodeFragment retTarget,
        CodeFragment excTarget
    )
    {
        // Stop recording execution time, start recording compilation time
        stats.execTimeStop();
        stats.compTimeStart();

        // When exiting this function
        scope (exit)
        {
            // Stop recording compilation time, resume recording execution time
            stats.compTimeStop();
            stats.execTimeStart();
        }

        auto strPtr = vm.getArgStr(instr, 0);
        auto fileName = vm.getLoadPath(extractStr(strPtr));

        try
        {
            // Parse the source file and generate IR
            auto ast = parseFile(fileName);
            auto fun = astToIR(vm, ast);

            // Register this function in the function reference set
            vm.funRefs[cast(void*)fun] = fun;

            // Create a version instance object for the unit function entry
            auto entryInst = getBlockVersion(
                fun.entryBlock,
                new CodeGenState(vm, fun, false),
                true
            );

            // Compile the unit entry version
            vm.compile(fun.entryBlock.firstInstr);

            // Get the return address for the continuation target
            auto retAddr = retTarget.getCodePtr(vm.execHeap);

            // Prepare the callee stack frame
            vm.callFun(
                fun,
                retAddr,
                null,
                vm.globalObj,
                0,
                null
            );

            // Return the function entry point code
            return entryInst.getCodePtr(vm.execHeap);
        }

        catch (Exception err)
        {
            return throwError(
                vm,
                instr,
                excTarget,
                "ReferenceError",
                "failed to load unit \"" ~ to!string(fileName) ~ "\""
            );
        }

        catch (Error err)
        {
            return throwError(
                vm,
                instr,
                excTarget,
                "SyntaxError",
                err.toString
            );
        }
    }

    // Spill the values that are live before the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            as.saveJITRegs();

            // Pass the call context and instruction as first two arguments
            as.mov(cargRegs[0], vmReg);
            as.ptr(cargRegs[1], instr);

            // Pass the return and exception addresses as third arguments
            as.ptr(cargRegs[2], target0);
            as.ptr(cargRegs[3], target1);

            // Call the host function
            as.ptr(scrRegs[0], &op_load_file);
            as.call(scrRegs[0]);

            as.loadJITRegs();

            // Jump to the address returned by the host function
            as.jmp(cretReg.opnd);
        },
        false
    );
}

void gen_eval_str(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) CodePtr op_eval_str(
        VM vm,
        IRInstr instr,
        CodeFragment retTarget,
        CodeFragment excTarget
    )
    {
        // Stop recording execution time, start recording compilation time
        stats.execTimeStop();
        stats.compTimeStart();

        // When exiting this function
        scope (exit)
        {
            // Stop recording compilation time, resume recording execution time
            stats.compTimeStop();
            stats.execTimeStart();
        }

        auto strPtr = vm.getArgStr(instr, 0);
        auto codeStr = extractStr(strPtr);

        try
        {
            // Parse the source file and generate IR
            auto ast = parseString(codeStr, "eval_str");
            auto fun = astToIR(vm, ast);

            // Register this function in the function reference set
            vm.funRefs[cast(void*)fun] = fun;

            // Create a version instance object for the unit function entry
            auto entryInst = getBlockVersion(
                fun.entryBlock,
                new CodeGenState(vm, fun, false),
                true
            );

            // Compile the unit entry version
            vm.compile(fun.entryBlock.firstInstr);

            // Get the return address for the continuation target
            auto retAddr = retTarget.getCodePtr(vm.execHeap);

            // Prepare the callee stack frame
            vm.callFun(
                fun,
                retAddr,
                null,
                vm.globalObj,
                0,
                null
            );

            // Return the function entry point code
            return entryInst.getCodePtr(vm.execHeap);
        }

        catch (Error err)
        {
            return throwError(
                vm,
                instr,
                excTarget,
                "SyntaxError",
                err.toString
            );
        }
    }

    // Spill the values that are live before the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            as.saveJITRegs();

            // Pass the call context and instruction as first two arguments
            as.mov(cargRegs[0], vmReg);
            as.ptr(cargRegs[1], instr);

            // Pass the return and exception addresses
            as.ptr(cargRegs[2], target0);
            as.ptr(cargRegs[3], target1);

            // Call the host function
            as.ptr(scrRegs[0], &op_eval_str);
            as.call(scrRegs[0]);

            as.loadJITRegs();

            // Jump to the address returned by the host function
            as.jmp(cretReg.opnd);
        },
        false
    );
}

void gen_ret(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto fun = instr.block.fun;

    auto raSlot    = fun.raVal.outSlot;
    auto argcSlot  = fun.argcVal.outSlot;
    auto numParams = fun.numParams;
    auto numLocals = fun.numLocals;

    // Get the return value word operand
    auto retOpnd = st.getWordOpnd(
        as,
        instr,
        0,
        64,
        //scrRegs[0].opnd(64),
        retWordReg.opnd(64),
        true,
        false
    );

    // Get the return value type operand
    auto typeOpnd = st.getTypeOpnd(
        as,
        instr,
        0,
        (retOpnd != retTypeReg.opnd(64))? retTypeReg.opnd(8):scrRegs[1].opnd(8),
        true
    );

    //as.printStr("ret from " ~ fun.getName);

    // Move the return word and type to the return registers
    if (retWordReg.opnd != retOpnd)
        as.mov(retWordReg.opnd, retOpnd);
    if (retTypeReg.opnd(8) != typeOpnd)
        as.mov(retTypeReg.opnd(8), typeOpnd);

    // If we are in a constructor (new) call
    if (st.callCtx.ctorCall is true)
    {
        // TODO: optimize for case where instr.getArg(0) is IRConst.undefCst

        // If the return value is not undefined (test word and type),
        // then skip over. If it is undefined, then fetch the "this"
        // value and return that instead.
        as.cmp(retTypeReg.opnd(8), X86Opnd(Type.CONST));
        as.jne(Label.FALSE);
        as.cmp(retWordReg.opnd(8), X86Opnd(UNDEF.word.int8Val));
        as.jne(Label.FALSE);

        // Use the "this" value as a return value
        auto thisWord = st.getWordOpnd(fun.thisVal, 64);
        as.mov(retWordReg.opnd(64), thisWord);
        auto thisType = st.getTypeOpnd(fun.thisVal);
        as.mov(retTypeReg.opnd(8), thisType);

        as.label(Label.FALSE);
    }

    // If this is a runtime primitive function
    if (fun.isPrim)
    {
        // Get the return address into r1
        as.getWord(scrRegs[1], raSlot);

        // Pop all local stack slots
        as.add(tspReg.opnd(64), X86Opnd(Type.sizeof * numLocals));
        as.add(wspReg.opnd(64), X86Opnd(Word.sizeof * numLocals));
    }
    else
    {
        //as.printStr("argc=");
        //as.printInt(scrRegs[0].opnd(64));

        // Compute the number of extra arguments into r0
        as.getWord(scrRegs[0].reg(32), argcSlot);
        if (numParams !is 0)
            as.sub(scrRegs[0].opnd(32), X86Opnd(numParams));
        as.xor(scrRegs[1].opnd(32), scrRegs[1].opnd(32));
        as.cmp(scrRegs[0].opnd(32), X86Opnd(0));
        as.cmovl(scrRegs[0].reg(32), scrRegs[1].opnd(32));

        // Compute the total number of stack slots to pop into r0
        as.add(scrRegs[0].opnd(32), X86Opnd(numLocals));

        // Get the return address into r1
        as.getWord(scrRegs[1], raSlot);

        // Pop all local stack slots and arguments
        //as.printStr("popping");
        //as.printUint(scrRegs[0].opnd);
        as.add(tspReg.opnd(64), scrRegs[0].opnd);
        as.shl(scrRegs[0].opnd, X86Opnd(3));
        as.add(wspReg.opnd(64), scrRegs[0].opnd);
    }

    // Jump to the return address
    //as.printStr("ra=");
    //as.printUint(scrRegs[1].opnd);
    as.jmp(scrRegs[1].opnd);

    // Mark the end of the fragment
    ver.markEnd(as, st.callCtx.vm);
}

void gen_throw(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Get the string pointer
    auto excWordOpnd = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, true, false);
    auto excTypeOpnd = st.getTypeOpnd(as, instr, 0, X86Opnd.NONE, true);

    // Spill the values live before the instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    as.saveJITRegs();

    // Call the host throwExc function
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd, X86Opnd(0));
    as.mov(cargRegs[3].opnd, excWordOpnd);
    as.mov(cargRegs[4].opnd(8), excTypeOpnd);
    as.ptr(scrRegs[0], &throwExc);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Jump to the exception handler
    as.jmp(cretReg.opnd);

    // Mark the end of the fragment
    ver.markEnd(as, st.callCtx.vm);
}

void GetValOp(Type typeTag, string fName)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto fSize = 8 * mixin("VM." ~ fName ~ ".sizeof");

    auto outOpnd = st.getOutOpnd(as, instr, fSize);

    as.getMember!("VM." ~ fName)(scrRegs[0].reg(fSize), vmReg);
    as.mov(outOpnd, scrRegs[0].opnd(fSize));

    st.setOutType(as, instr, typeTag);
}

alias GetValOp!(Type.OBJECT, "objProto.word") gen_get_obj_proto;
alias GetValOp!(Type.OBJECT, "arrProto.word") gen_get_arr_proto;
alias GetValOp!(Type.OBJECT, "funProto.word") gen_get_fun_proto;
alias GetValOp!(Type.OBJECT, "globalObj.word") gen_get_global_obj;
alias GetValOp!(Type.INT32, "heapSize") gen_get_heap_size;
alias GetValOp!(Type.INT32, "gcCount") gen_get_gc_count;

void gen_get_heap_free(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    as.getMember!("VM.allocPtr")(scrRegs[0], vmReg);
    as.getMember!("VM.heapLimit")(scrRegs[1], vmReg);

    as.sub(scrRegs[1].opnd, scrRegs[0].opnd);

    as.mov(outOpnd, scrRegs[1].opnd(32));

    st.setOutType(as, instr, Type.INT32);
}

void HeapAllocOp(Type type)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr allocFallback(VM vm, IRInstr curInstr, uint32_t allocSize)
    {
        vm.setCurInstr(curInstr);

        //writeln("alloc fallback");

        auto ptr = heapAlloc(vm, allocSize);

        vm.setCurInstr(null);

        return ptr;
    }

    // Spill the values live before the instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    // Get the allocation size operand
    auto szOpnd = st.getWordOpnd(as, instr, 0, 32, X86Opnd.NONE, true, false);

    // Get the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.getMember!("VM.allocPtr")(scrRegs[0], vmReg);
    as.getMember!("VM.heapLimit")(scrRegs[1], vmReg);

    // r2 = allocPtr + size
    // Note: we zero extend the size operand to 64-bits
    as.mov(scrRegs[2].opnd(32), szOpnd);
    as.add(scrRegs[2].opnd(64), scrRegs[0].opnd(64));

    // if (allocPtr + size > heapLimit) fallback
    as.cmp(scrRegs[2].opnd(64), scrRegs[1].opnd(64));
    as.jg(Label.FALLBACK);

    // Move the allocation pointer to the output
    as.mov(outOpnd, scrRegs[0].opnd(64));

    // Align the incremented allocation pointer
    as.add(scrRegs[2].opnd(64), X86Opnd(7));
    as.and(scrRegs[2].opnd(64), X86Opnd(-8));

    // Store the incremented and aligned allocation pointer
    as.setMember!("VM.allocPtr")(vmReg, scrRegs[2]);

    // Done allocating
    as.jmp(Label.DONE);

    // Clone the state for the bailout case, which will spill for GC
    auto bailSt = new CodeGenState(st);

    // Allocation fallback
    as.label(Label.FALLBACK);

    as.saveJITRegs();

    //as.printStr("alloc bailout ***");

    // Call the fallback implementation
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd(32), szOpnd);
    as.ptr(RAX, &allocFallback);
    as.call(RAX);

    //as.printStr("alloc bailout done ***");

    as.loadJITRegs();

    // Store the output value into the output operand
    as.mov(outOpnd, X86Opnd(RAX));

    // Allocation done
    as.label(Label.DONE);

    // Set the output type tag
    st.setOutType(as, instr, type);
}

alias HeapAllocOp!(Type.REFPTR) gen_alloc_refptr;
alias HeapAllocOp!(Type.OBJECT) gen_alloc_object;
alias HeapAllocOp!(Type.ARRAY) gen_alloc_array;
alias HeapAllocOp!(Type.CLOSURE) gen_alloc_closure;
alias HeapAllocOp!(Type.STRING) gen_alloc_string;

void gen_gc_collect(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) void op_gc_collect(VM vm, IRInstr curInstr, uint32_t heapSize)
    {
        vm.setCurInstr(curInstr);

        //writeln("triggering gc");

        gcCollect(vm, heapSize);

        vm.setCurInstr(null);
    }

    // Spill the values live before the instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    // Get the string pointer
    auto heapSizeOpnd = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, true, false);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd, heapSizeOpnd);
    as.ptr(scrRegs[0], &op_gc_collect);
    as.call(scrRegs[0]);

    as.loadJITRegs();
}

void gen_get_global(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = st.callCtx.vm;

    // Name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Lookup the property index in the class
    // if the property slot doesn't exist, it will be allocated
    auto globalMap = cast(ObjMap)obj_get_map(vm.globalObj.word.ptrVal);
    assert (globalMap !is null);
    auto propIdx = globalMap.getPropIdx(nameStr, false);

    // If the property was not found
    if (propIdx is uint32.max)
    {
        // Initialize the property, this may extend the global object
        setProp(vm, vm.globalObj, nameStr, MISSING);
        propIdx = globalMap.getPropIdx(nameStr, false);
        assert (propIdx !is uint32.max);
    }

    extern (C) static CodePtr hostGetProp(CodeGenState st, IRInstr instr)
    {
        auto vm = st.callCtx.vm;

        auto strArg = cast(IRString)instr.getArg(0);
        auto nameStr = strArg.str;

        auto propVal = getProp(
            vm,
            vm.globalObj,
            nameStr
        );

        if (propVal == MISSING)
        {
            auto spillTest = delegate bool(LiveInfo liveInfo, IRDstValue val)
            {
                return liveInfo.liveAfter(val, instr);
            };

            // Spill the saved registers
            st.spillSavedRegs(spillTest);

            auto excHandler = throwError(
                vm,
                instr,
                null,
                "TypeError",
                "global property not defined \"" ~ to!string(nameStr) ~ "\""
            );

            // Reload the saved registers
            st.loadSavedRegs(spillTest);

            return excHandler;
        }

        vm.push(propVal);

        return null;
    }

    static CodePtr getFallbackSub(VM vm)
    {
        if (vm.getGlobalSub)
            return vm.getGlobalSub;

        auto as = vm.subsHeap;
        vm.getGlobalSub = as.getAddress(as.getWritePos);

        // Save the scratch, JIT and alloc registers
        as.push(scrRegs[1]);
        as.push(scrRegs[2]);
        as.push(scrRegs[2]);
        as.saveJITRegs();
        as.saveAllocRegs();

        // Call the host fallback code
        // Note:
        // CodeGenState pointer is in cargRegs[0]
        // IRInstr pointer is in cargRegs[1]
        as.ptr(scrRegs[0], &hostGetProp);
        as.call(scrRegs[0].opnd);

        // Restore the scratch, JIT and alloc registers
        as.loadAllocRegs();
        as.loadJITRegs();
        as.pop(scrRegs[2]);
        as.pop(scrRegs[2]);
        as.pop(scrRegs[1]);

        // If an exception was thrown, jump to the exception handler
        as.cmp(cretReg.opnd, X86Opnd(0));
        as.je(Label.FALSE);
        as.pop(scrRegs[1]);
        as.jmp(cretReg.opnd);
        as.label(Label.FALSE);

        // Get the property value from the stack
        // r2 = type
        // r1 = word
        as.getType(scrRegs[2].reg(8), 0);
        as.getWord(scrRegs[1], 0);
        as.add(wspReg, Word.sizeof);
        as.add(tspReg, Type.sizeof);

        // Return to the point of call
        as.ret();

        // Link the labels in this subroutine
        as.linkLabels();
        return vm.getGlobalSub;
    }

    // Allocate the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    // Get the global object pointer
    as.getMember!("VM.globalObj.word")(scrRegs[0], vmReg);

    // Get the global object size/capacity
    as.getField(scrRegs[1].reg(32), scrRegs[0], obj_ofs_cap(null));

    // Get the offset of the start of the word array
    auto wordOfs = obj_ofs_word(vm.globalObj.word.ptrVal, 0);

    // Load the word and type values
    // r2 = type
    // r1 = word
    auto typeMem = X86Opnd(8 , scrRegs[0], wordOfs + propIdx, 8, scrRegs[1]);
    auto wordMem = X86Opnd(64, scrRegs[0], wordOfs + 8 * propIdx);
    as.mov(scrRegs[2].opnd(8), typeMem);
    as.mov(scrRegs[1].opnd(64), wordMem);

    // If the value is not "missing", skip the fallback code
    as.cmp(scrRegs[2].opnd(8), X86Opnd(Type.CONST));
    as.jne(Label.SKIP);
    as.cmp(scrRegs[1].opnd(64), X86Opnd(MISSING.word.int8Val));
    as.jne(Label.SKIP);

    // Call the fallback subroutine
    auto getGlobalSub = getFallbackSub(vm);
    as.ptr(cargRegs[0], st);
    as.ptr(cargRegs[1], instr);
    as.ptr(scrRegs[0], getGlobalSub);
    as.call(scrRegs[0]);

    // If skipping the fallback code
    as.label(Label.SKIP);

    // Set the output word
    as.mov(outOpnd, scrRegs[1].opnd(64));

    // Set the type value
    st.setOutType(as, instr, scrRegs[2].reg(8));
}

void gen_set_global(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = st.callCtx.vm;

    // Name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Lookup the property index in the class
    auto globalMap = cast(ObjMap)obj_get_map(vm.globalObj.word.ptrVal);
    assert (globalMap !is null);
    auto propIdx = globalMap.getPropIdx(nameStr, false);

    // If the property was not found
    if (propIdx is uint32.max)
    {
        // Initialize the property, this may extend the global object
        setProp(vm, vm.globalObj, nameStr, MISSING);
        propIdx = globalMap.getPropIdx(nameStr, false);
        assert (propIdx !is uint32.max);
    }

    // Allocate the input operand
    auto argOpnd = st.getWordOpnd(as, instr, 1, 64, scrRegs[0].opnd(64), true);

    // Get the global object pointer
    as.getMember!("VM.globalObj.word")(scrRegs[1], vmReg);

    // Get the global object size/capacity
    as.getField(scrRegs[2].reg(32), scrRegs[1], obj_ofs_cap(null));

    // Get the offset of the start of the word array
    auto wordOfs = obj_ofs_word(vm.globalObj.word.ptrVal, 0);

    // Set the word value
    auto wordMem = X86Opnd(64, scrRegs[1], wordOfs + 8 * propIdx);
    as.mov(wordMem, argOpnd);

    // Set the type value
    auto typeOpnd = st.getTypeOpnd(as, instr, 1, scrRegs[0].opnd(8), true);
    auto typeMem = X86Opnd(8, scrRegs[1], wordOfs + propIdx, 8, scrRegs[2]);
    as.mov(typeMem, typeOpnd);
}

void gen_get_str(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) refptr getStr(VM vm, IRInstr curInstr, refptr strPtr)
    {
        vm.setCurInstr(curInstr);

        // Compute and set the hash code for the string
        auto hashCode = compStrHash(strPtr);
        str_set_hash(strPtr, hashCode);

        // Find the corresponding string in the string table
        auto str = getTableStr(vm, strPtr);

        vm.setCurInstr(null);

        return str;
    }

    // Spill the values live before the instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    // Get the string pointer
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, true, false);

    // Allocate the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the fallback implementation
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd, opnd0);
    as.ptr(scrRegs[0], &getStr);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Store the output value into the output operand
    as.mov(outOpnd, X86Opnd(RAX));

    // The output is a reference pointer
    st.setOutType(as, instr, Type.STRING);
}

void gen_make_link(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = st.callCtx.vm;

    auto linkArg = cast(IRLinkIdx)instr.getArg(0);
    assert (linkArg !is null);

    if (linkArg.linkIdx is NULL_LINK)
    {
        linkArg.linkIdx = vm.allocLink();

        vm.setLinkWord(linkArg.linkIdx, NULL.word);
        vm.setLinkType(linkArg.linkIdx, NULL.type);
    }

    // Set the output value
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(linkArg.linkIdx));

    // Set the output type
    st.setOutType(as, instr, Type.INT32);
}

void gen_set_link(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Get the link index operand
    auto idxReg = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64));
    assert (idxReg.isGPR);

    // Set the link word
    auto valWord = st.getWordOpnd(as, instr, 1, 64, scrRegs[1].opnd(64));
    as.getMember!("VM.wLinkTable")(scrRegs[2], vmReg);
    auto wordMem = X86Opnd(64, scrRegs[2], 0, Word.sizeof, idxReg.reg);
    as.mov(wordMem, valWord);

    // Set the link type
    auto valType = st.getTypeOpnd(as, instr, 1, scrRegs[1].opnd(8));
    as.getMember!("VM.tLinkTable")(scrRegs[2], vmReg);
    auto typeMem = X86Opnd(8, scrRegs[2], 0, Type.sizeof, idxReg.reg);
    as.mov(typeMem, valType);
}

void gen_get_link(
    BlockVersion ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Get the link index operand
    auto idxReg = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64));
    assert (idxReg.isGPR);

    // Get the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    // Read the link word
    as.getMember!("VM.wLinkTable")(scrRegs[1], vmReg);
    auto wordMem = X86Opnd(64, scrRegs[1], 0, Word.sizeof, idxReg.reg);
    as.mov(scrRegs[1].opnd(64), wordMem);
    as.mov(outOpnd, scrRegs[1].opnd(64));

    // Read the link type
    as.getMember!("VM.tLinkTable")(scrRegs[1], vmReg);
    auto typeMem = X86Opnd(8, scrRegs[1], 0, Type.sizeof, idxReg.reg);
    as.mov(scrRegs[1].opnd(8), typeMem);
    st.setOutType(as, instr, scrRegs[1].reg(8));
}

void gen_make_map(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto mapArg = cast(IRMapPtr)instr.getArg(0);
    assert (mapArg !is null);

    auto numPropArg = cast(IRConst)instr.getArg(1);
    assert (numPropArg !is null);

    // Allocate the map
    if (mapArg.map is null)
        mapArg.map = new ObjMap(st.callCtx.vm, numPropArg.int32Val);

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    auto outReg = outOpnd.isReg? outOpnd.reg:scrRegs[0];

    as.ptr(outReg, mapArg.map);
    if (!outOpnd.isReg)
        as.mov(outOpnd, X86Opnd(outReg));

    // Set the output type
    st.setOutType(as, instr, Type.MAPPTR);
}

void gen_map_num_props(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static uint32_t op_map_num_props(ObjMap map)
    {
        // Get the number of properties to allocate
        assert (map !is null, "map is null");
        return map.numProps;
    }

    // Spill the values live before the instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);

    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0].opnd(64), opnd0);
    as.ptr(scrRegs[0], &op_map_num_props);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Store the output value into the output operand
    as.mov(outOpnd, X86Opnd(RAX));

    st.setOutType(as, instr, Type.INT32);
}

void gen_map_prop_idx(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    static const uint NUM_CACHE_ENTRIES = 4;
    static const uint CACHE_ENTRY_SIZE = 8 + 4;

    as.incStatCnt(&stats.numMapPropIdx, scrRegs[0]);

    extern (C) static uint32_t op_map_prop_idx(ObjMap map, refptr strPtr, bool allocField)
    {
        //writeln("slow lookup");

        // Increment the count of slow property lookups
        stats.numMapPropSlow++;

        // Lookup the property index
        assert (map !is null, "map is null");
        auto propIdx = map.getPropIdx(strPtr, allocField);

        return propIdx;
    }

    extern (C) static uint32_t updateCache(ObjMap map, wstring* propName, bool allocField, ubyte* cachePtr)
    {
        //writeln("cache miss");
        //writeln("propName=", *propName);
        //writeln("cachePtr=", cast(uint64_t)cast(void*)cachePtr);
        //writeln("map ptr=" , cast(uint64_t)cast(void*)map);
        //writeln("map id=", map.id);

        // Increment the count of property cache misses
        stats.numMapPropMisses++;

        // Lookup the property index
        assert (map !is null, "map is null");
        auto propIdx = map.getPropIdx(*propName, allocField);

        //writeln("shifting cache entries");

        // Shift the current cache entries down
        for (uint i = NUM_CACHE_ENTRIES - 1; i > 0; --i)
        {
            memcpy(
                cachePtr + CACHE_ENTRY_SIZE * i,
                cachePtr + CACHE_ENTRY_SIZE * (i-1),
                CACHE_ENTRY_SIZE
            );
        }

        // Add a new cache entry
        *(cast(uint64_t*)(cachePtr + 0)) = map.id;
        *(cast(uint32_t*)(cachePtr + 8)) = propIdx;

        // Return the property index
        return propIdx;
    }

    bool allocField;
    if (instr.getArg(2) is IRConst.trueCst)
        allocField = true;
    else if (instr.getArg(2) is IRConst.falseCst)
        allocField = false;
    else
        assert (false);

    // Spill the values live before the instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    // Get the map operand
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64), false, false);
    assert (opnd0.isReg);

    // Get the property name operand
    auto opnd1 = st.getWordOpnd(as, instr, 1, 64, X86Opnd.NONE, false, false);

    // Get the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    // If the property name is a known constant string
    auto nameArgInstr = cast(IRInstr)instr.getArg(1);
    if (nameArgInstr && nameArgInstr.opcode is &SET_STR)
    {
        // Allocate an extra temporary register
        auto scrReg3 = st.freeReg(as, instr);

        // Get the property name
        auto propName = &(cast(IRString)nameArgInstr.getArg(0)).str;

        // Inline cache entries
        // [mapIdx (uint64_t) | propIdx (uint32_t)]+
        as.lea(scrRegs[1], X86Mem(8, RIP, 5));
        as.jmp(Label.AFTER_DATA);
        for (uint i = 0; i < NUM_CACHE_ENTRIES; ++i)
        {
            as.writeInt(0xFFFFFFFFFFFFFFFF, 64);
            as.writeInt(0x00000000, 32);
        }
        as.label(Label.AFTER_DATA);

        // Get the map id
        as.getMember!("ObjMap.id")(scrRegs[2].reg(64), opnd0.reg);

        //as.printStr("inline cache lookup");
        //as.printStr("map id=");
        //as.printUint(scrRegs[2].opnd(64));

        // For each cache entry
        for (uint i = 0; i < NUM_CACHE_ENTRIES; ++i)
        {
            auto mapIdxOpnd  = X86Opnd(64, scrRegs[1], CACHE_ENTRY_SIZE * i + 0);
            auto propIdxOpnd = X86Opnd(32, scrRegs[1], CACHE_ENTRY_SIZE * i + 8);

            // Move the prop idx for this entry into the output operand
            if (outOpnd.isMem)
            {
                as.mov(scrReg3.opnd(32), propIdxOpnd);
                as.mov(outOpnd, scrReg3.opnd(32));
            }
            else
            {
                as.mov(outOpnd, propIdxOpnd);
            }

            // If this is a cache hit, we are done, stop
            as.cmp(mapIdxOpnd, scrRegs[2].opnd(64));
            as.je(Label.DONE);
        }

        as.saveJITRegs();

        // Call the cache update function
        as.mov(cargRegs[0].opnd(64), opnd0);
        as.ptr(cargRegs[1], propName);
        as.mov(cargRegs[2].opnd(64), X86Opnd(allocField? 1:0));
        as.mov(cargRegs[3].opnd(64), scrRegs[1].opnd(64));
        as.ptr(scrRegs[0], &updateCache);
        as.call(scrRegs[0]);

        as.loadJITRegs();

        // Store the output value into the output operand
        as.mov(outOpnd, cretReg.opnd(32));

        // Cache entry found
        as.label(Label.DONE);
    }
    else
    {
        as.saveJITRegs();

        // Call the host function
        as.mov(cargRegs[0].opnd(64), opnd0);
        as.mov(cargRegs[1].opnd(64), opnd1);
        as.mov(cargRegs[2].opnd(64), X86Opnd(allocField? 1:0));
        as.ptr(scrRegs[0], &op_map_prop_idx);
        as.call(scrRegs[0]);

        as.loadJITRegs();

        // Store the output value into the output operand
        as.mov(outOpnd, cretReg.opnd(32));
    }

    // Set the output type
    st.setOutType(as, instr, Type.INT32);
}

void gen_map_prop_name(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr op_map_prop_name(
        VM vm,
        IRInstr curInstr,
        ObjMap map,
        uint32_t propIdx
    )
    {
        vm.setCurInstr(curInstr);

        assert (map !is null, "map is null");
        auto propName = map.getPropName(propIdx);
        auto str = (propName !is null)? getString(vm, propName):null;

        vm.setCurInstr(null);

        return str;
    }

    // Spill the values that are live after the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);
    auto opnd1 = st.getWordOpnd(as, instr, 1, 32, X86Opnd.NONE, false, false);

    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd(64), opnd0);
    as.mov(cargRegs[3].opnd(32), opnd1);
    as.ptr(scrRegs[0], &op_map_prop_name);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Store the output value into the output operand
    as.mov(outOpnd, cretReg.opnd);

    // If the string is null, the type must be REFPTR
    as.mov(scrRegs[0].opnd(8), X86Opnd(Type.STRING));
    as.mov(scrRegs[1].opnd(8), X86Opnd(Type.REFPTR));
    as.cmp(outOpnd, X86Opnd(NULL.word.int8Val));
    as.cmove(scrRegs[0].reg(8), scrRegs[1].opnd(8));
    st.setOutType(as, instr, scrRegs[0].reg(8));
}

void gen_new_clos(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr op_new_clos(
        VM vm,
        IRInstr curInstr,
        IRFunction fun,
        ObjMap closMap,
        ObjMap protMap
    )
    {
        vm.setCurInstr(curInstr);

        // If the function has no entry point code
        if (fun.entryCode is null)
        {
            // Store the entry code pointers
            fun.entryCode = getEntryStub(vm, false);
            fun.ctorCode = getEntryStub(vm, true);
            assert (fun.entryCode !is fun.ctorCode);
        }

        // Allocate the closure object
        auto closPtr = GCRoot(
            vm,
            newClos(
                vm,
                closMap,
                vm.funProto,
                cast(uint32)fun.ast.captVars.length,
                fun
            )
        );

        // Allocate the prototype object
        auto objPtr = GCRoot(
            vm,
            newObj(
                vm,
                protMap,
                vm.objProto
            )
        );

        // Set the "prototype" property on the closure object
        setProp(
            vm,
            closPtr.pair,
            "prototype"w,
            objPtr.pair
        );

        assert (
            clos_get_next(closPtr.ptr) == null,
            "closure next pointer is not null"
        );

        //writeln("final clos ptr: ", closPtr.ptr);

        vm.setCurInstr(null);

        return closPtr.ptr;
    }

    // TODO: spill only values stored in C arg regs and C caller-save regs?
    // Spill all values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto funArg = cast(IRFunPtr)instr.getArg(0);
    assert (funArg !is null);

    auto closMapOpnd = st.getWordOpnd(as, instr, 1, 64, X86Opnd.NONE, false, false);
    auto protMapOpnd = st.getWordOpnd(as, instr, 2, 64, X86Opnd.NONE, false, false);

    as.saveJITRegs();

    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.ptr(cargRegs[2], funArg.fun);
    as.mov(cargRegs[3].opnd(64), closMapOpnd);
    as.mov(cargRegs[4].opnd(64), protMapOpnd);
    as.ptr(scrRegs[0], &op_new_clos);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(cretReg));

    st.setOutType(as, instr, Type.CLOSURE);
}

void gen_print_str(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static void printStr(refptr strPtr)
    {
        // Extract a D string
        auto str = extractStr(strPtr);

        // Print the string to standard output
        write(str);
    }

    auto strOpnd = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);

    as.pushRegs();

    as.mov(cargRegs[0].opnd(64), strOpnd);
    as.ptr(scrRegs[0], &printStr);
    as.call(scrRegs[0].opnd(64));

    as.popRegs();
}

void gen_get_time_ms(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static double op_get_time_ms()
    {
        long currTime = Clock.currStdTime();
        long epochTime = 621355968000000000; //unixTimeToStdTime(0);
        double retVal = cast(double)((currTime - epochTime)/10000);
        return retVal;
    }

    // Spill the values live after this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveAfter(value, instr);
        }
    );

    as.saveJITRegs();

    as.ptr(scrRegs[0], &op_get_time_ms);
    as.call(scrRegs[0].opnd(64));

    as.loadJITRegs();

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.movq(outOpnd, X86Opnd(XMM0));
    st.setOutType(as, instr, Type.FLOAT64);
}

void gen_get_ast_str(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr op_get_ast_str(
        VM vm, 
        IRInstr curInstr, 
        refptr closPtr
    )
    {
        vm.setCurInstr(curInstr);

        assert (
            refIsLayout(closPtr, LAYOUT_CLOS),
            "invalid closure object"
        );

        auto fun = getFunPtr(closPtr);

        auto str = fun.ast.toString();
        auto strObj = getString(vm, to!wstring(str));

        vm.setCurInstr(null);

        return strObj;
    }

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);

    as.saveJITRegs();

    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd, opnd0);
    as.ptr(scrRegs[0], &op_get_ast_str);
    as.call(scrRegs[0].opnd);

    as.loadJITRegs();

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(RAX));
    st.setOutType(as, instr, Type.STRING);
}

void gen_get_ir_str(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr op_get_ir_str(
        VM vm, 
        IRInstr curInstr,
        refptr closPtr
    )
    {
        vm.setCurInstr(curInstr);

        assert (
            refIsLayout(closPtr, LAYOUT_CLOS),
            "invalid closure object"
        );

        auto fun = getFunPtr(closPtr);

        // If the function is not yet compiled, compile it now
        if (fun.entryBlock is null)
        {
            auto numLocals = fun.numLocals;
            astToIR(vm, fun.ast, fun);
            fun.numLocals = numLocals;
        }

        auto str = fun.toString();
        auto strObj = getString(vm, to!wstring(str));

        vm.setCurInstr(null);

        return strObj;
    }

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);

    as.saveJITRegs();

    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd, opnd0);
    as.ptr(scrRegs[0], &op_get_ir_str);
    as.call(scrRegs[0].opnd);

    as.loadJITRegs();

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(RAX));
    st.setOutType(as, instr, Type.STRING);
}

void gen_get_asm_str(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr op_get_asm_str(
        VM vm,
        IRInstr curInstr,
        refptr closPtr
    )
    {
        vm.setCurInstr(curInstr);

        assert (
            refIsLayout(closPtr, LAYOUT_CLOS),
            "invalid closure object"
        );

        auto fun = getFunPtr(closPtr);

        string str;

        // If this function has a call context
        if (fun.ctx)
        {
            // Request an instance for the function entry block
            auto entryVer = getBlockVersion(
                fun.entryBlock,
                new CodeGenState(vm, fun, false),
                true
            );

            // Generate a string representation of the code
            str ~= asmString(fun, entryVer, vm.execHeap);
        }

        // If this function has a constructor context
        if (fun.ctorCtx)
        {
            // Request an instance for the constructor entry block
            auto entryVer = getBlockVersion(
                fun.entryBlock,
                new CodeGenState(vm, fun, true),
                true
            );

            if (str != "")
                str ~= "\n\n";

            // Generate a string representation of the code
            str ~= asmString(fun, entryVer, vm.execHeap);
        }

        // Get a string object for the output
        auto strObj = getString(vm, to!wstring(str));

        vm.setCurInstr(null);

        return strObj;
    }

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);

    as.saveJITRegs();

    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd, opnd0);
    as.ptr(scrRegs[0], &op_get_asm_str);
    as.call(scrRegs[0].opnd);

    as.loadJITRegs();

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(RAX));
    st.setOutType(as, instr, Type.STRING);
}

void gen_load_lib(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static CodePtr op_load_lib(
        VM vm,
        IRInstr instr
    )
    {
        // Library to load (JS string)
        auto strPtr = vm.getArgStr(instr, 0);

        // Library to load (D string)
        auto libname = extractStr(strPtr);

        // Let the user specify just the lib name
        if (libname.length > 0 && libname.countUntil('/') == -1)
        {
            if (libname.countUntil('.') == -1)
                libname ~= ".so";

            if (libname[0] != 'l' && libname[1] != 'i' && libname[2] != 'b')
                libname = "lib" ~ libname;
        }

        // String must be null terminated
        auto lib = dlopen(toStringz(libname), RTLD_LAZY | RTLD_LOCAL);

        if (lib is null)
        {
            return throwError(
                vm,
                instr,
                null,
                "RuntimeError",
                to!string(dlerror())
            );
        }

        vm.push(Word.ptrv(cast(rawptr)lib), Type.RAWPTR);

        return null;

    }

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.ptr(scrRegs[0], &op_load_lib);
    as.call(scrRegs[0].opnd);
    as.loadJITRegs();

    // If an exception was thrown, jump to the exception handler
    as.cmp(cretReg.opnd, X86Opnd(0));
    as.je(Label.FALSE);
    as.jmp(cretReg.opnd);
    as.label(Label.FALSE);

    // Get the lib handle from the stack
    as.getWord(scrRegs[0], 0);
    as.add(wspReg, Word.sizeof);
    as.add(tspReg, Type.sizeof);
    as.mov(outOpnd, scrRegs[0].opnd);
    st.setOutType(as, instr, Type.RAWPTR);
}

void gen_close_lib(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static CodePtr op_close_lib(
        VM vm,
        IRInstr instr
    )
    {
        auto libArg = vm.getArgVal(instr, 0);

        assert (
            libArg.type == Type.RAWPTR,
            "invalid rawptr value"
        );

        if (dlclose(libArg.word.ptrVal) != 0)
        {
            return throwError(
                vm,
                instr,
                null,
                "RuntimeError",
                "Could not close lib."
            );
        }

        return null;
    }

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    as.saveJITRegs();
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.ptr(scrRegs[0], &op_close_lib);
    as.call(scrRegs[0].opnd);
    as.loadJITRegs();

    // If an exception was thrown, jump to the exception handler
    as.cmp(cretReg.opnd, X86Opnd(0));
    as.je(Label.FALSE);
    as.jmp(cretReg.opnd);
    as.label(Label.FALSE);
}

void gen_get_sym(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static CodePtr op_get_sym(
        VM vm,
        IRInstr instr
    )
    {
        auto libArg = vm.getArgVal(instr, 0);

        assert (
            libArg.type == Type.RAWPTR,
            "invalid rawptr value"
        );

        // Symbol name (D string)
        auto strArg = cast(IRString)instr.getArg(1);
        assert (strArg !is null);
        auto symname = to!string(strArg.str);

        // String must be null terminated
        auto sym = dlsym(libArg.word.ptrVal, toStringz(symname));

        if (sym is null)
        {
            return throwError(
                vm,
                instr,
                null,
                "RuntimeError",
                to!string(dlerror())
            );
        }

        vm.push(Word.ptrv(cast(rawptr)sym), Type.RAWPTR);

        return null;
    }

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.ptr(scrRegs[0], &op_get_sym);
    as.call(scrRegs[0].opnd);
    as.loadJITRegs();

    // If an exception was thrown, jump to the exception handler
    as.cmp(cretReg.opnd, X86Opnd(0));
    as.je(Label.FALSE);
    as.jmp(cretReg.opnd);
    as.label(Label.FALSE);

    // Get the sym handle from the stack
    as.getWord(scrRegs[0], 0);
    as.add(wspReg, Word.sizeof);
    as.add(tspReg, Type.sizeof);
    as.mov(outOpnd, scrRegs[0].opnd);
    st.setOutType(as, instr, Type.RAWPTR);

}
// TODO: add support for new i types
// Mappings for arguments/return values
Type[string] typeMap;
size_t[string] sizeMap;
static this()
{
    typeMap = [
        "i8" : Type.INT32,
        "i16" : Type.INT32,
        "i32" : Type.INT32,
        "i64" : Type.INT64,
        "u8" : Type.INT32,
        "u16" : Type.INT32,
        "u32" : Type.INT32,
        "u64" : Type.INT64,
        "f64" : Type.FLOAT64,
        "*" : Type.RAWPTR
    ];

    sizeMap = [
        "i8" : 8,
        "i16" : 16,
        "i32" : 32,
        "i64" : 64,
        "u8" : 8,
        "u16" : 16,
        "u32" : 32,
        "u64" : 64,
        "f64" : 64,
        "*" : 64
    ];
}

void gen_call_ffi(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = st.callCtx.vm;

    // Get the function signature
    auto sigStr = cast(IRString)instr.getArg(1);
    assert (sigStr !is null, "null sigStr in call_ffi.");
    auto typeinfo = to!string(sigStr.str);
    auto types = split(typeinfo, ",");

    // Track register usage for args
    auto iArgIdx = 0;
    auto fArgIdx = 0;

    // Return type of the FFI call
    auto retType = types[0];

    // Argument types the call expects
    auto argTypes = types[1..$];

    // The number of args actually passed
    auto argCount = cast(uint32_t)instr.numArgs - 2;
    assert(argTypes.length == argCount, "Incorrect arg count in call_ffi.");

    // Spill the values live before this instruction
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    // outOpnd
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    // Indices of arguments to be pushed on the stack
    size_t stackArgs[];

    // Set up arguments
    for (size_t idx = 0; idx < argCount; ++idx)
    {
        // Either put the arg in the appropriate register
        // or set it to be pushed to the stack later
        if (argTypes[idx] == "f64" && fArgIdx < cfpArgRegs.length)
        {
            auto argOpnd = st.getWordOpnd(
                as,
                instr,
                idx + 2,
                64,
                scrRegs[0].opnd(64),
                true,
                false
            );
            as.movq(cfpArgRegs[fArgIdx++].opnd, argOpnd);
        }
        else if (iArgIdx < cargRegs.length)
        {
            auto argSize = sizeMap[argTypes[idx]];
            auto argOpnd = st.getWordOpnd(
                as, 
                instr,
                idx + 2,
                argSize,
                scrRegs[0].opnd(argSize),
                true,
                false
            );
            auto cargOpnd = cargRegs[iArgIdx++].opnd(argSize);
            as.mov(cargOpnd, argOpnd);
        }
        else
        {
            stackArgs ~= idx;
        }
    }

    // Save the JIT registers
    as.saveJITRegs();

    // Make sure there is an even number of pushes
    if (stackArgs.length % 2 != 0)
        as.push(scrRegs[0]);

    // Push the stack arguments, in reverse order
    foreach_reverse (idx; stackArgs)
    {
        auto argSize = sizeMap[argTypes[idx]];
        auto argOpnd = st.getWordOpnd(
            as,
            instr,
            idx + 2,
            argSize,
            scrRegs[0].opnd(argSize),
            true,
            false
        );
        as.mov(scrRegs[0].opnd(argSize), argOpnd);
        as.push(scrRegs[0]);
    }

    // Pointer to function to call
    auto funArg = st.getWordOpnd(
        as,
        instr,
        0,
        64,
        scrRegs[0].opnd(64),
        false,
        false
    );

    // call the function
    as.call(scrRegs[0].opnd);

    // Pop the stack arguments
    foreach (idx; stackArgs)
        as.pop(scrRegs[1]);

    // Make sure there is an even number of pops
    if (stackArgs.length % 2 != 0)
        as.pop(scrRegs[1]);

    // Restore the JIT registers
    as.loadJITRegs();

    // Send return value/type
    if (retType == "f64")
    {
        as.movq(outOpnd, X86Opnd(XMM0));
        st.setOutType(as, instr, typeMap[retType]);
    }
    else if (retType == "void")
    {
        as.mov(outOpnd, X86Opnd(UNDEF.word.int8Val));
        st.setOutType(as, instr, Type.CONST);
    }
    else
    {
        as.mov(outOpnd, X86Opnd(RAX));
        st.setOutType(as, instr, typeMap[retType]);
    }

    auto branch = getBranchEdge(
        instr.getTarget(0),
        st,
        true
    );

    // Jump to the target block directly
    ver.genBranch(
        as,
        branch,
        null,
        delegate void(
            CodeBlock as,
            VM vm,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            jmp32Ref(as, vm, target0, 0);
        }
    );
}

