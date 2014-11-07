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
import core.stdc.string;
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
alias GenFn = void function(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
);

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
    st.setOutTag(as, instr, scrRegs[1].reg(8));
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
    auto tagOpnd = st.getWordOpnd(as, instr, 1, 8, scrRegs[0].opnd(8));
    assert (tagOpnd.isGPR);
    st.setOutTag(as, instr, tagOpnd.reg);
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

    st.setOutTag(as, instr, Tag.INT64);
}

void gen_get_tag(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto tagOpnd = st.getTagOpnd(as, instr, 0, scrRegs[0].opnd(8), true);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    if (tagOpnd.isImm)
    {
        as.mov(outOpnd, tagOpnd);
    }
    else if (outOpnd.isGPR)
    {
        as.movzx(outOpnd, tagOpnd);
    }
    else
    {
        as.movzx(scrRegs[0].opnd(32), tagOpnd);
        as.mov(outOpnd, scrRegs[0].opnd(32));
    }

    st.setOutTag(as, instr, Tag.INT32);
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
    st.setOutTag(as, instr, Tag.FLOAT64);
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

    st.setOutTag(as, instr, Tag.INT32);
}

void RMMOp(string op, size_t numBits, Tag tag)(
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

    // Get type information about the first argument
    auto arg0Type = st.getType(instr.getArg(0));

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

    // Set the output type tag
    st.setOutTag(as, instr, tag);

    // If the instruction has no exception/overflow target, stop
    if (instr.getTarget(0) is null)
        return;

    // If this is an add operation
    static if (op == "add")
    {
        // If we are adding 1 to a submaximal argument,
        // there can be no overflow
        auto arg1Cst = cast(IRConst)instr.getArg(1);
        if (arg0Type.subMax && arg1Cst &&
            arg1Cst.isInt32 && arg1Cst.int32Val == 1)
        {
            //writeln(instr.block.fun.getName);

            // Jump directly to the successor block
            return gen_jump(ver, st, instr, as);
        }
    }

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
            BlockVersion block,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            final switch (shape)
            {
                case BranchShape.NEXT0:
                jo32Ref(as, vm, block, target1, 1);
                break;

                case BranchShape.NEXT1:
                jno32Ref(as, vm, block, target0, 0);
                break;

                case BranchShape.DEFAULT:
                jo32Ref(as, vm, block, target1, 1);
                jmp32Ref(as, vm, block, target0, 0);
            }
        }
    );
}

alias gen_add_i32 = RMMOp!("add", 32, Tag.INT32);
alias gen_sub_i32 = RMMOp!("sub", 32, Tag.INT32);
alias gen_mul_i32 = RMMOp!("imul", 32, Tag.INT32);
alias gen_and_i32 = RMMOp!("and", 32, Tag.INT32);
alias gen_or_i32 = RMMOp!("or", 32, Tag.INT32);
alias gen_xor_i32 = RMMOp!("xor", 32, Tag.INT32);

alias gen_add_i32_ovf = RMMOp!("add", 32, Tag.INT32);
alias gen_sub_i32_ovf = RMMOp!("sub", 32, Tag.INT32);
alias gen_mul_i32_ovf = RMMOp!("imul", 32, Tag.INT32);

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

    // Set the output type tag
    st.setOutTag(as, instr, Tag.RAWPTR);
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

    // Set the output type tag
    st.setOutTag(as, instr, Tag.INT32);
}

alias gen_div_i32 = divOp!("div");
alias gen_mod_i32 = divOp!("mod");

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

    // Set the output type tag
    st.setOutTag(as, instr, Tag.INT32);
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

    // Set the output type tag
    st.setOutTag(as, instr, Tag.INT32);
}

alias gen_lsft_i32 = ShiftOp!("sal");
alias gen_rsft_i32 = ShiftOp!("sar");
alias gen_ursft_i32 = ShiftOp!("shr");

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

    // Set the output type tag
    st.setOutTag(as, instr, Tag.FLOAT64);
}

alias gen_add_f64 = FPOp!("add");
alias gen_sub_f64 = FPOp!("sub");
alias gen_mul_f64 = FPOp!("mul");
alias gen_div_f64 = FPOp!("div");

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

    st.setOutTag(as, instr, Tag.FLOAT64);
}

alias gen_sin_f64 = HostFPOp!(std.c.math.sin);
alias gen_cos_f64 = HostFPOp!(std.c.math.cos);
alias gen_sqrt_f64 = HostFPOp!(std.c.math.sqrt);
alias gen_ceil_f64 = HostFPOp!(std.c.math.ceil);
alias gen_floor_f64 = HostFPOp!(std.c.math.floor);
alias gen_log_f64 = HostFPOp!(std.c.math.log);
alias gen_exp_f64 = HostFPOp!(std.c.math.exp);
alias gen_pow_f64 = HostFPOp!(std.c.math.pow, 2);
alias gen_mod_f64 = HostFPOp!(std.c.math.fmod, 2);

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

    st.setOutTag(as, instr, Tag.STRING);
}

alias gen_f64_to_str = FPToStr!("%G");
alias gen_f64_to_str_lng = FPToStr!(format("%%.%sf", float64.dig));

void LoadOp(size_t memSize, bool signed, Tag tag)(
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
    st.setOutTag(as, instr, tag);
}

alias gen_load_u8 = LoadOp!(8, false, Tag.INT32);
alias gen_load_u16 = LoadOp!(16, false, Tag.INT32);
alias gen_load_u32 = LoadOp!(32, false, Tag.INT32);
alias gen_load_u64 = LoadOp!(64, false, Tag.INT64);
alias gen_load_i8 = LoadOp!(8, true , Tag.INT32);
alias gen_load_i16 = LoadOp!(16, true , Tag.INT32);
alias gen_load_i32 = LoadOp!(32, true , Tag.INT32);
alias gen_load_i64 = LoadOp!(64, true , Tag.INT64);
alias gen_load_f64 = LoadOp!(64, false, Tag.FLOAT64);
alias gen_load_refptr = LoadOp!(64, false, Tag.REFPTR);
alias gen_load_string = LoadOp!(64, false, Tag.STRING);
alias gen_load_rawptr = LoadOp!(64, false, Tag.RAWPTR);
alias gen_load_funptr = LoadOp!(64, false, Tag.FUNPTR);
alias gen_load_shapeptr = LoadOp!(64, false, Tag.SHAPEPTR);

void StoreOp(size_t memSize, Tag tag)(
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

alias gen_store_u8 = StoreOp!(8, Tag.INT32);
alias gen_store_u16 = StoreOp!(16, Tag.INT32);
alias gen_store_u32 = StoreOp!(32, Tag.INT32);
alias gen_store_u64 = StoreOp!(64, Tag.INT64);
alias gen_store_i8 = StoreOp!(8, Tag.INT32);
alias gen_store_i16 = StoreOp!(16, Tag.INT32);
alias gen_store_i32 = StoreOp!(32, Tag.INT32);
alias gen_store_u64 = StoreOp!(64, Tag.INT64);
alias gen_store_f64 = StoreOp!(64, Tag.FLOAT64);
alias gen_store_refptr = StoreOp!(64, Tag.REFPTR);
alias gen_store_rawptr = StoreOp!(64, Tag.RAWPTR);
alias gen_store_funptr = StoreOp!(64, Tag.FUNPTR);
alias gen_store_shapeptr = StoreOp!(64, Tag.SHAPEPTR);

void TagTestOp(Tag tag)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    //as.printStr(instr.toString);
    //as.printStr("    " ~ instr.block.fun.getName);

    // Get an operand for the value's type
    auto tagOpnd = st.getTagOpnd(as, instr, 0, X86Opnd.NONE, true);

    auto testResult = TestResult.UNKNOWN;

    // If the type is available through basic block versioning
    if (tagOpnd.isImm)
    {
        // Get the known type
        auto knownTag = cast(Tag)tagOpnd.imm.imm;

        // Get the test result
        testResult = (tag is knownTag)? TestResult.TRUE:TestResult.FALSE;
    }

    // If the type analysis was run
    if (opts.typeprop)
    {
        // Get the type analysis result for this value at this instruction
        auto propResult = st.fun.typeInfo.argIsType(instr, 0, tag);

        //writeln("result: ", propResult);

        // If the analysis yields a known result
        if (propResult != TestResult.UNKNOWN)
        {
            // Warn if the analysis knows more than BBV
            if (testResult == TestResult.UNKNOWN && opts.maxvers > 0)
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
            st.setOutTag(as, instr, Tag.CONST);
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
                    BlockVersion block,
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
                        jmp32Ref(as, vm, block, target0, 0);
                    }
                }
            );
        }

        return;
    }

    // Increment the stat counter for this specific kind of type test
    as.incStatCnt(stats.getTagTestCtr(instr.opcode.mnem), scrRegs[1]);

    // Compare against the tested type
    as.cmp(tagOpnd, X86Opnd(tag));

    // If this instruction has many uses or is not followed by an if_true
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

        // Set the output type tag
        st.setOutTag(as, instr, Tag.CONST);
    }

    // If our only use is an immediately following if_true
    if (ifUseNext(instr) is true)
    {
        // If the argument is not a constant, add type information
        // about the argument's type along the true branch
        CodeGenState trueSt = st;
        if (auto dstArg = cast(IRDstValue)instr.getArg(0))
        {
            trueSt = new CodeGenState(trueSt);
            trueSt.setTag(dstArg, tag);
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
                BlockVersion block,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                final switch (shape)
                {
                    case BranchShape.NEXT0:
                    jne32Ref(as, vm, block, target1, 1);
                    break;

                    case BranchShape.NEXT1:
                    je32Ref(as, vm, block, target0, 0);
                    break;

                    case BranchShape.DEFAULT:
                    jne32Ref(as, vm, block, target1, 1);
                    jmp32Ref(as, vm, block, target0, 0);
                }
            }
        );
    }
}

alias gen_is_const = TagTestOp!(Tag.CONST);
alias gen_is_int32 = TagTestOp!(Tag.INT32);
alias gen_is_int64 = TagTestOp!(Tag.INT64);
alias gen_is_float64 = TagTestOp!(Tag.FLOAT64);
alias gen_is_rawptr = TagTestOp!(Tag.RAWPTR);
alias gen_is_refptr = TagTestOp!(Tag.REFPTR);
alias gen_is_object = TagTestOp!(Tag.OBJECT);
alias gen_is_array = TagTestOp!(Tag.ARRAY);
alias gen_is_closure = TagTestOp!(Tag.CLOSURE);
alias gen_is_string = TagTestOp!(Tag.STRING);
alias gen_is_rope = TagTestOp!(Tag.ROPE);

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

        // Set the output type tag
        st.setOutTag(as, instr, Tag.CONST);
    }

    // If there is an immediately following if_true using this value
    if (ifUseNext(instr) is true)
    {
        // If this is a less-than comparison and the argument
        // is not a constant, mark the argument as being
        // submaximal along the true branch
        CodeGenState trueSt = st;
        static if (op == "lt")
        {
            if (auto dstArg = cast(IRDstValue)instr.getArg(0))
            {
                trueSt = new CodeGenState(trueSt);
                ValType argType = trueSt.getType(dstArg);
                argType.subMax = true;
                trueSt.setType(dstArg, argType);
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
                BlockVersion block,
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
                        jne32Ref(as, vm, block, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        je32Ref(as, vm, block, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        je32Ref(as, vm, block, target0, 0);
                        jmp32Ref(as, vm, block, target1, 1);
                    }
                }
                else if (op == "ne")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        je32Ref(as, vm, block, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jne32Ref(as, vm, block, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jne32Ref(as, vm, block, target0, 0);
                        jmp32Ref(as, vm, block, target1, 1);
                    }
                }
                else if (op == "lt")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jge32Ref(as, vm, block, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jl32Ref(as, vm, block, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jl32Ref(as, vm, block, target0, 0);
                        jmp32Ref(as, vm, block, target1, 1);
                    }
                }
                else if (op == "le")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jg32Ref(as, vm, block, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jle32Ref(as, vm, block, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jle32Ref(as, vm, block, target0, 0);
                        jmp32Ref(as, vm, block, target1, 1);
                    }
                }
                else if (op == "gt")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jle32Ref(as, vm, block, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jg32Ref(as, vm, block, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jg32Ref(as, vm, block, target0, 0);
                        jmp32Ref(as, vm, block, target1, 1);
                    }
                }
                else if (op == "ge")
                {
                    final switch (shape)
                    {
                        case BranchShape.NEXT0:
                        jl32Ref(as, vm, block, target1, 1);
                        break;

                        case BranchShape.NEXT1:
                        jge32Ref(as, vm, block, target0, 0);
                        break;

                        case BranchShape.DEFAULT:
                        jge32Ref(as, vm, block, target0, 0);
                        jmp32Ref(as, vm, block, target1, 1);
                    }
                }

                // Floating-point comparisons
                else if (op == "feq")
                {
                    // feq:
                    // True: 100
                    // False: 111 or 000 or 001
                    // False: JNE + JP
                    jne32Ref(as, vm, block, target1, 1);
                    jp32Ref(as, vm, block, target1, 1);
                    jmp32Ref(as, vm, block, target0, 0);
                }
                else if (op == "fne")
                {
                    // fne: 
                    // True: 111 or 000 or 001
                    // False: 100
                    // True: JNE + JP
                    jne32Ref(as, vm, block, target0, 0);
                    jp32Ref(as, vm, block, target0, 0);
                    jmp32Ref(as, vm, block, target1, 1);
                }
                else if (op == "flt")
                {
                    ja32Ref(as, vm, block, target0, 0);
                    jmp32Ref(as, vm, block, target1, 1);
                }
                else if (op == "fle")
                {
                    jae32Ref(as, vm, block, target0, 0);
                    jmp32Ref(as, vm, block, target1, 1);
                }
                else if (op == "fgt")
                {
                    ja32Ref(as, vm, block, target0, 0);
                    jmp32Ref(as, vm, block, target1, 1);
                }
                else if (op == "fge")
                {
                    jae32Ref(as, vm, block, target0, 0);
                    jmp32Ref(as, vm, block, target1, 1);
                }
            }
        );
    }
}

alias gen_eq_i8 = CmpOp!("eq", 8);
alias gen_eq_i32 = CmpOp!("eq", 32);
alias gen_ne_i32 = CmpOp!("ne", 32);
alias gen_lt_i32 = CmpOp!("lt", 32);
alias gen_le_i32 = CmpOp!("le", 32);
alias gen_gt_i32 = CmpOp!("gt", 32);
alias gen_ge_i32 = CmpOp!("ge", 32);
alias gen_eq_i64 = CmpOp!("eq", 64);

alias gen_eq_const = CmpOp!("eq", 8);
alias gen_ne_const = CmpOp!("ne", 8);
alias gen_eq_refptr = CmpOp!("eq", 64);
alias gen_ne_refptr = CmpOp!("ne", 64);
alias gen_eq_rawptr = CmpOp!("eq", 64);
alias gen_ne_rawptr = CmpOp!("ne", 64);
alias gen_eq_f64 = CmpOp!("feq", 64);
alias gen_ne_f64 = CmpOp!("fne", 64);
alias gen_lt_f64 = CmpOp!("flt", 64);
alias gen_le_f64 = CmpOp!("fle", 64);
alias gen_gt_f64 = CmpOp!("fgt", 64);
alias gen_ge_f64 = CmpOp!("fge", 64);

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

    // Compare the argument to the true boolean value
    auto argOpnd = st.getWordOpnd(as, instr, 0, 8, scrRegs[0].opnd(8));
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
            BlockVersion block,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            final switch (shape)
            {
                case BranchShape.NEXT0:
                jne32Ref(as, vm, block, target1, 1);
                break;

                case BranchShape.NEXT1:
                je32Ref(as, vm, block, target0, 0);
                break;

                case BranchShape.DEFAULT:
                je32Ref(as, vm, block, target0, 0);
                jmp32Ref(as, vm, block, target1, 1);
            }
        }
    );
}

void JumpOp(size_t succIdx)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto branch = getBranchEdge(
        instr.getTarget(succIdx),
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
            BlockVersion block,
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
                jmp32Ref(as, vm, block, target0, 0);
            }
        }
    );
}

alias gen_jump = JumpOp!(0);
alias gen_jump_false = JumpOp!(1);

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
    auto vm = st.fun.vm;

    // Map the return value to its stack location
    st.mapToStack(instr);

    BranchCode contBranch;
    BranchCode excBranch = null;

    // Create a branch object for the continuation
    contBranch = getBranchEdge(
        instr.getTarget(0),
        st,
        false,
        delegate void(CodeBlock as, VM vm)
        {
            // If eager compilation is enabled
            if (opts.bbv_eager)
            {
                // Set the return address entry when compiling the
                // continuation block
                vm.setRetEntry(
                    instr,
                    contBranch,
                    excBranch
                );
            }

            // Move the return value into the instruction's output slot
            if (instr.hasUses)
            {
                as.setWord(instr.outSlot, retWordReg.opnd(64));
                as.setTag(instr.outSlot, retTagReg.opnd(8));
            }
        }
    );

    // Create the continuation branch object
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
                as.add(tspReg, Tag.sizeof);
                as.add(wspReg, Word.sizeof);
                as.getWord(scrRegs[0], -1);
                as.setWord(instr.outSlot, scrRegs[0].opnd(64));
                as.getTag(scrRegs[0].reg(8), -1);
                as.setTag(instr.outSlot, scrRegs[0].opnd(8));
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

    // If eager compilation is enabled
    if (opts.bbv_eager)
    {
        // Generate the call branch code
        ver.genBranch(
            as,
            contBranch,
            excBranch,
            genFn
        );
    }
    else
    {
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
    }

    //writeln("call block length: ", ver.length);
}

void gen_call_prim(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = st.fun.vm;

    // Function name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Increment the stat counter for this primitive
    as.incStatCnt(stats.getPrimCallCtr(to!string(nameStr)), scrRegs[0]);

    // Get the primitve function from the global object
    auto closVal = getProp(vm, vm.globalObj, nameStr);
    assert (
        closVal.tag is Tag.CLOSURE,
        "failed to resolve closure in call_prim"
    );
    assert (closVal.word.ptrVal !is null);
    auto fun = getFunPtr(closVal.word.ptrVal);

    //as.printStr(to!string(nameStr));

    // Check that the argument count matches
    auto numArgs = cast(int32_t)instr.numArgs - 1;
    assert (
        numArgs is fun.numParams,
        "incorrect argument count for call to primitive " ~ fun.getName
    );

    // Check that the hidden arguments are not used
    assert (
        (!fun.closVal || fun.closVal.hasNoUses) &&
        (!fun.thisVal || fun.thisVal.hasNoUses) &&
        (!fun.argcVal || fun.argcVal.hasNoUses),
        "call_prim: hidden args used"
    );

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
    {
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
        auto tagOpnd = st.getTagOpnd(
            as,
            instr,
            instrArgIdx,
            scrRegs[1].opnd(8),
            true
        );
        as.setTag(dstIdx, tagOpnd);
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

    // TODO
    // TODO: analysis to detect possible shape changes
    // TODO
    // Clear the known shape information
    st.clearShapes();

    // Push space for the callee arguments and locals
    as.sub(X86Opnd(tspReg), X86Opnd(fun.numLocals));
    as.sub(X86Opnd(wspReg), X86Opnd(8 * fun.numLocals));

    // Request an instance for the function entry block
    auto entryVer = getBlockVersion(
        fun.entryBlock,
        new CodeGenState(fun)
    );

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            BlockVersion block,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            // Get the return address slot of the callee
            auto raSlot = entryVer.block.fun.raVal.outSlot;
            assert (raSlot !is NULL_STACK);

            // Write the return address on the stack
            as.movAbsRef(vm, scrRegs[0], block, target0, 0);
            as.setWord(raSlot, scrRegs[0].opnd(64));

            // Jump to the function entry block
            jmp32Ref(as, vm, block, entryVer, 0);
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
    //
    // Function pointer extraction
    //

    // Get the type information for the closure value
    auto closType = st.getType(instr.getArg(0));

    // This may throw an exception if the callee is not a closure
    auto mayThrow = !closType.tagKnown || closType.tag !is Tag.CLOSURE;

    // Get the number of arguments supplied
    auto numArgs = cast(uint32_t)instr.numArgs - 2;

    // If the callee function is known
    if (closType.fptrKnown)
    {
        as.incStatCnt(&stats.numCallFast, scrRegs[0]);

        // Get the function pointer
        IRFunction fun = closType.fptr;

        // If the function is not yet compiled, compile it now
        if (fun.entryBlock is null)
        {
            try
            {
                astToIR(fun.vm, fun.ast, fun);
            }

            catch (Error err)
            {
                assert (
                    false,
                    "failed to generate IR for: \"" ~ fun.getName ~ "\"\n" ~
                    err.toString
                );
            }
        }

        // Compute the number of missing arguments
        auto numMissing = (fun.numParams > numArgs)? (fun.numParams - numArgs):0;

        // Compute the actual number of extra arguments
        auto numExtra = (numArgs > fun.numParams)? (numArgs - fun.numParams):0;

        // Compute the number of arguments we actually need to pass
        auto numPassed = numArgs + numMissing;

        // Compute the number of locals in this frame
        auto frameSize = fun.numLocals + numExtra;

        // Copy the function arguments supplied
        for (int32_t i = 0; i < numArgs; ++i)
        {
            auto instrArgIdx = 2 + i;
            auto dstIdx = -(numPassed - i);

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
            auto tagOpnd = st.getTagOpnd(
                as,
                instr,
                instrArgIdx,
                scrRegs[1].opnd(8),
                true
            );
            as.setTag(dstIdx, tagOpnd);
        }

        // Write undefined values for the missing arguments
        for (int32_t i = 0; i < numMissing; ++i)
        {
            auto dstIdx = -(i + 1);

            as.setWord(dstIdx, UNDEF.word.int8Val);
            as.setTag(dstIdx, UNDEF.tag);
        }

        // Write the argument count
        as.setWord(-numPassed - 1, numArgs);

        // Write the "this" argument
        if (fun.thisVal.hasUses)
        {
            auto thisReg = st.getWordOpnd(
                as,
                instr,
                1,
                64,
                scrRegs[1].opnd(64),
                true,
                false
            );
            as.setWord(-numPassed - 2, thisReg);
            auto tagOpnd = st.getTagOpnd(
                as,
                instr,
                1,
                scrRegs[1].opnd(8),
                true
            );
            as.setTag(-numPassed - 2, tagOpnd);
        }

        // Write the closure argument
        if (fun.closVal.hasUses)
        {
            auto closReg = st.getWordOpnd(
                as,
                instr,
                0,
                64,
                scrRegs[0].opnd(64),
                false,
                false
            );
            as.setWord(-numPassed - 3, closReg);
        }

        // Spill the values that are live after the call
        st.spillLiveBefore(as, instr);

        // Clear the known shape information
        st.clearShapes();

        // Push space for the callee arguments and locals
        as.sub(X86Opnd(tspReg), X86Opnd(frameSize));
        as.sub(X86Opnd(wspReg), X86Opnd(8 * frameSize));

        // Request an instance for the function entry block
        auto entryVer = getBlockVersion(
            fun.entryBlock,
            new CodeGenState(fun)
        );

        ver.genCallBranch(
            st,
            instr,
            as,
            delegate void(
                CodeBlock as,
                VM vm,
                BlockVersion block,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                // Get the return address slot of the callee
                auto raSlot = entryVer.block.fun.raVal.outSlot;
                assert (raSlot !is NULL_STACK);

                // Write the return address on the stack
                as.movAbsRef(vm, scrRegs[0], block, target0, 0);
                as.setWord(raSlot, scrRegs[0].opnd(64));

                // Jump to the function entry block
                jmp32Ref(as, vm, block, entryVer, 0);
            },
            false
        );

        return;
    }

    as.incStatCnt(&stats.numCallSlow, scrRegs[0]);

    // If an exception may be thrown
    if (mayThrow)
    {
        // Get the type tag for the closure value
        auto closTag = st.getTagOpnd(
            as,
            instr,
            0,
            scrRegs[1].opnd(8),
            false
        );

        // If the value is not a closure, bailout
        as.incStatCnt(stats.getTagTestCtr("is_closure"), scrRegs[2]);
        as.cmp(closTag, X86Opnd(Tag.CLOSURE));
        as.jne(Label.THROW);
    }

    // Free an extra register to use as scratch
    auto scrReg3 = st.freeReg(as, instr);

    // Get the closure pointer in a register
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

    // Initialize the missing arguments, if any
    as.mov(scrReg3.opnd(64), scrRegs[2].opnd(64));
    as.label(Label.LOOP);
    as.cmp(scrReg3.opnd(64), X86Opnd(0));
    as.jge(Label.LOOP_EXIT);
    as.mov(X86Opnd(64, wspReg, 0, 8, scrReg3), X86Opnd(UNDEF.word.int8Val));
    as.mov(X86Opnd(8, tspReg, 0, 1, scrReg3), X86Opnd(Tag.CONST));
    as.add(scrReg3.opnd(64), X86Opnd(1));
    as.jmp(Label.LOOP);
    as.label(Label.LOOP_EXIT);

    static void movArgWord(CodeBlock as, size_t argIdx, X86Opnd val)
    {
        as.mov(X86Opnd(64, wspReg, -8 * cast(int32_t)(argIdx+1), 8, scrRegs[2]), val);
    }

    static void movArgTag(CodeBlock as, size_t argIdx, X86Opnd val)
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
        auto tagOpnd = st.getTagOpnd(
            as,
            instr,
            instrArgIdx,
            scrReg3.opnd(8),
            true
        );
        movArgTag(as, i, tagOpnd);
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
    auto tagOpnd = st.getTagOpnd(
        as,
        instr,
        1,
        scrReg3.opnd(8),
        true
    );
    movArgTag(as, numArgs + 1, tagOpnd);

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

    // Clear the known shape information
    st.clearShapes();

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            BlockVersion block,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            // Write the return address on the stack
            as.movAbsRef(vm, scrReg3, block, target0, 0);
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
        mayThrow
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
        // Increment the number of calls performed using apply
        stats.numCallApply++;

        vm.setCurInstr(instr);

        auto closVal = vm.getArgVal(instr, 0);
        auto thisVal = vm.getArgVal(instr, 1);
        auto tblVal  = vm.getArgVal(instr, 2);
        auto argcVal = vm.getArgUint32(instr, 3);

        assert (
            tblVal.tag !is Tag.ARRAY,
            "invalid argument table"
        );

        assert (
            closVal.tag is Tag.CLOSURE,
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
            argVals[i].tag = cast(Tag)arrtbl_get_tag(tblPtr, i);
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

    // Spill the values that are live after the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    // Clear the known shape information
    st.clearShapes();

    ver.genCallBranch(
        st,
        instr,
        as,
        delegate void(
            CodeBlock as,
            VM vm,
            BlockVersion block,
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
            as.movAbsRef(vm, cargRegs[2], block, target0, 0);

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

            // Create a GC root for the function to prevent it from
            // being collected if the GC runs during its own compilation
            auto funPtr = GCRoot(vm, Word.funv(fun), Tag.FUNPTR);

            // Create a version instance object for the unit function entry
            auto entryInst = getBlockVersion(
                fun.entryBlock,
                new CodeGenState(fun)
            );

            // Compile the unit entry version
            vm.compile(instr);

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
            BlockVersion block,
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

            // Create a GC root for the function to prevent it from
            // being collected if the GC runs during its own compilation
            auto funPtr = GCRoot(vm, Word.funv(fun), Tag.FUNPTR);

            // Create a version instance object for the unit function entry
            auto entryInst = getBlockVersion(
                fun.entryBlock,
                new CodeGenState(fun)
            );

            // Compile the unit entry version
            vm.compile(instr);

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
            BlockVersion block,
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

/*
size_t[Tag] retCounts;
size_t undefCount;
size_t boolCount;

extern (C) void countRet(Word word, Tag tag, IRInstr instr)
{
    if (word == UNDEF.word && tag == UNDEF.tag)
        undefCount++;

    if ((word == TRUE.word && tag == TRUE.tag) || (word == FALSE.word && tag == FALSE.tag))
    {
        //writeln(instr.block.fun.getName);
        boolCount++;
    }


    if (tag == Tag.CLOSURE)
        writeln(instr.block.fun.getName);


    retCounts[tag]++;
}

static ~this()
{
    alias Tuple!(Tag, "tag", ulong, "cnt") Cnt;
    Cnt[] cnts;
    foreach (tag, count; retCounts)
        cnts ~= Cnt(tag, count);
    cnts.sort!"a.cnt > b.cnt";

    foreach (pair; cnts)
    {
        writeln(pair.tag, ": ", pair.cnt);
    }

    writeln("undef: ", undefCount);
    writeln("bool: ", boolCount);
}

as.pushRegs();
as.mov(cargRegs[0].opnd(64), retOpnd);
as.mov(cargRegs[1].opnd(8), tagOpnd);
as.ptr(cargRegs[2], instr);
as.ptr(cargRegs[3], &countRet);
as.call(cargRegs[3]);
as.popRegs();
*/

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
        retWordReg.opnd(64),
        true,
        false
    );

    // Get the return value type operand
    auto tagOpnd = st.getTagOpnd(
        as,
        instr,
        0,
        (retOpnd != retTagReg.opnd(64))? retTagReg.opnd(8):scrRegs[1].opnd(8),
        true
    );

    //as.printStr("ret from " ~ fun.getName);

    // Move the return word and tag to the return registers
    if (retWordReg.opnd != retOpnd)
        as.mov(retWordReg.opnd, retOpnd);
    if (retTagReg.opnd(8) != tagOpnd)
        as.mov(retTagReg.opnd(8), tagOpnd);

    // If this is a runtime primitive function
    if (fun.isPrim)
    {
        // Get the return address into r1
        as.getWord(scrRegs[1], raSlot);

        // Pop all local stack slots
        as.add(tspReg.opnd(64), X86Opnd(Tag.sizeof * numLocals));
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
    ver.markEnd(as, st.fun.vm);
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
    auto excTypeOpnd = st.getTagOpnd(as, instr, 0, X86Opnd.NONE, true);

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
    ver.markEnd(as, st.fun.vm);
}

void GetValOp(Tag tag, string fName)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto fSize = 8 * mixin("VM." ~ fName ~ ".sizeof");

    auto outOpnd = st.getOutOpnd(as, instr, fSize);
    assert (outOpnd.isReg);

    as.getMember!("VM." ~ fName)(outOpnd.reg, vmReg);

    st.setOutTag(as, instr, tag);
}

alias gen_get_obj_proto = GetValOp!(Tag.OBJECT, "objProto.word");
alias gen_get_arr_proto = GetValOp!(Tag.OBJECT, "arrProto.word");
alias gen_get_fun_proto = GetValOp!(Tag.OBJECT, "funProto.word");
alias gen_get_str_proto = GetValOp!(Tag.OBJECT, "strProto.word");
alias gen_get_global_obj = GetValOp!(Tag.OBJECT, "globalObj.word");
alias gen_get_heap_size = GetValOp!(Tag.INT32, "heapSize");
alias gen_get_gc_count = GetValOp!(Tag.INT32, "gcCount");

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

    st.setOutTag(as, instr, Tag.INT32);
}

void HeapAllocOp(Tag tag)(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr allocFallback(
        VM vm,
        IRInstr curInstr,
        uint32_t allocSize
    )
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

    as.incStatCnt(&stats.numHeapAllocs, scrRegs[0]);

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
    as.mov(outOpnd, cretReg.opnd);

    // Allocation done
    as.label(Label.DONE);

    // Set the output type tag
    st.setOutTag(as, instr, tag);
}

alias gen_alloc_refptr = HeapAllocOp!(Tag.REFPTR);
alias gen_alloc_object = HeapAllocOp!(Tag.OBJECT);
alias gen_alloc_array = HeapAllocOp!(Tag.ARRAY);
alias gen_alloc_closure = HeapAllocOp!(Tag.CLOSURE);
alias gen_alloc_string = HeapAllocOp!(Tag.STRING);
alias gen_alloc_rope = HeapAllocOp!(Tag.ROPE);

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
    auto heapSizeOpnd = st.getWordOpnd(as, instr, 0, 32, X86Opnd.NONE, true, false);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd(32), heapSizeOpnd);
    as.ptr(scrRegs[0], &op_gc_collect);
    as.call(scrRegs[0]);

    as.loadJITRegs();
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

    // Spill the values live before this instruction
    st.spillLiveBefore(as, instr);

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
    as.mov(outOpnd, cretReg.opnd);

    // The output is a reference pointer
    st.setOutTag(as, instr, Tag.STRING);
}

void gen_make_link(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = st.fun.vm;

    auto linkArg = cast(IRLinkIdx)instr.getArg(0);
    assert (linkArg !is null);

    if (linkArg.linkIdx is NULL_LINK)
    {
        linkArg.linkIdx = vm.allocLink();

        vm.setLinkWord(linkArg.linkIdx, NULL.word);
        vm.setLinkType(linkArg.linkIdx, NULL.tag);
    }

    // Set the output value
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(linkArg.linkIdx));

    // Set the output type
    st.setOutTag(as, instr, Tag.INT32);
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
    auto valType = st.getTagOpnd(as, instr, 1, scrRegs[1].opnd(8));
    as.getMember!("VM.tLinkTable")(scrRegs[2], vmReg);
    auto typeMem = X86Opnd(8, scrRegs[2], 0, Tag.sizeof, idxReg.reg);
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
    auto typeMem = X86Opnd(8, scrRegs[1], 0, Tag.sizeof, idxReg.reg);
    as.mov(scrRegs[1].opnd(8), typeMem);
    st.setOutTag(as, instr, scrRegs[1].reg(8));
}

void gen_break(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    assert (instr.getTarget(0) && instr.getTarget(1));
    assert (instr.getTarget(0).target is instr.getTarget(1).target);

    auto branch = getBranchEdge(instr.getTarget(0), st, false);

    // Generate the branch code
    ver.genBranch(
        as,
        branch,
        branch,
        delegate void(
            CodeBlock as,
            VM vm,
            BlockVersion block,
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
                break;

                case BranchShape.DEFAULT:
                jmp32Ref(as, vm, block, target0, 1);
            }
        }
    );
}

/// Inputs: any value x
/// Shifts us to version where the tag of the value is known
/// Implements a dynamic type tag dispatch mechanism
void gen_capture_tag(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    assert (instr.getTarget(0).args.length is 0);

    auto vm = st.fun.vm;

    // Get the argument value
    auto argVal = instr.getArg(0);

    // Get type information about the argument
    ValType argType = st.getType(argVal);

    // If the type tag is marked as known
    if (argType.tagKnown)
    {
        // Jump directly to the false successor block
        return gen_jump_false(ver, st, instr, as);
    }

    auto argDst = cast(IRDstValue)argVal;
    assert (argDst !is null);

    // Get the current argument value type tag
    auto argTag = argDst? vm.getTag(argDst.outSlot):argType.tag;

    // Get the type operand
    auto tagOpnd = st.getTagOpnd(as, instr, 0);

    // Increment the counter for this type tag test
    auto testName = "is_" ~ toLower(to!string(argTag));
    as.incStatCnt(stats.getTagTestCtr(testName), scrRegs[0]);

    // Compare this entry's type tag with the value's tag
    as.cmp(tagOpnd, X86Opnd(argTag));

    // On the recursive branch, no information is gained
    auto branchT = getBranchEdge(instr.getTarget(0), st, false);

    // Mark the value's type tag as known on the loop exit branch,
    // and queue this branch for immediate compilation (fall through)
    auto falseSt = new CodeGenState(st);
    falseSt.setTag(argDst, argTag);
    auto branchF = getBranchEdge(instr.getTarget(1), falseSt, true);

    // Generate the branch code
    ver.genBranch(
        as,
        branchT,
        branchF,
        delegate void(
            CodeBlock as,
            VM vm,
            BlockVersion block,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            final switch (shape)
            {
                case BranchShape.NEXT0:
                je32Ref(as, vm, block, target1, 1);
                break;

                case BranchShape.NEXT1:
                jne32Ref(as, vm, block, target0, 0);
                break;

                case BranchShape.DEFAULT:
                jne32Ref(as, vm, block, target0, 0);
                jmp32Ref(as, vm, block, target1, 1);
            }
        }
    );
}

/// Inputs: obj, propName
/// Capture the shape of the object
/// This shifts us to a different version where the obj shape is known
/// Implements a dynamic shape dispatch mechanism
void gen_capture_shape(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    assert (instr.getTarget(0).args.length is 0);

    auto vm = ver.block.fun.vm;

    // Get the object and shape argument values
    auto objVal = cast(IRDstValue)instr.getArg(0);
    auto shapeVal = cast(IRDstValue)instr.getArg(1);
    assert (objVal !is null);
    assert (shapeVal !is null);

    // Get type information about the object argument
    ValType objType = st.getType(objVal);

    // If the shape is marked as known
    if (objType.shapeKnown)
    {
        // Increment the count of known shape instances
        as.incStatCnt(&stats.numShapeKnown, scrRegs[0]);

        // Jump directly to the false successor block
        return gen_jump_false(ver, st, instr, as);
    }

    // Increment the count of shape tests
    as.incStatCnt(&stats.numShapeTests, scrRegs[0]);

    // Get the current shape argument word
    assert (shapeVal.block !is instr.block);
    auto shapeWord = vm.getWord(shapeVal.outSlot);

    // Get the shape argument operand
    auto shapeOpnd = st.getWordOpnd(as, instr, 1, 64);

    // Compare the shape operand with the observed shape
    as.ptr(scrRegs[0], shapeWord.ptrVal);
    as.cmp(shapeOpnd, scrRegs[0].opnd);

    // On the recursive branch, no information is gained
    auto branchT = getBranchEdge(instr.getTarget(0), st, false);

    // Mark the object shape as known on the false branch,
    // and queue this branch for immediate compilation (fall through)
    auto falseSt = new CodeGenState(st);
    falseSt.setShape(objVal, cast(ObjShape)shapeWord.shapeVal);
    auto branchF = getBranchEdge(instr.getTarget(1), falseSt, true);

    // Generate the branch code
    ver.genBranch(
        as,
        branchT,
        branchF,
        delegate void(
            CodeBlock as,
            VM vm,
            BlockVersion block,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            final switch (shape)
            {
                case BranchShape.NEXT0:
                je32Ref(as, vm, block, target1, 1);
                break;

                case BranchShape.NEXT1:
                jne32Ref(as, vm, block, target0, 0);
                break;

                case BranchShape.DEFAULT:
                jne32Ref(as, vm, block, target0, 0);
                jmp32Ref(as, vm, block, target1, 1);
            }
        }
    );
}

/// Reads the shape of an object, does nothing if the shape is known
/// Inputs: obj
void gen_obj_read_shape(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto objVal = cast(IRDstValue)instr.getArg(0);
    assert (objVal !is null);

    // Get the object operand
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64);
    assert (opnd0.isReg);

    // Get the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    assert (outOpnd.isReg);

    // TODO: find way to have instr in valMap without getting outOpnd?

    // If the shape is known, do nothing
    if (st.shapeKnown(objVal))
    {
        //as.mov(outOpnd, X86Opnd(0));
        st.setOutTag(as, instr, Tag.CONST);
        return;
    }

    // Get the object shape
    as.getField(outOpnd.reg, opnd0.reg, obj_ofs_shape(null));

    st.setOutTag(as, instr, Tag.SHAPEPTR);
}

/// Initializes an object to the empty shape
/// Inputs: obj
void gen_obj_init_shape(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) void op_obj_init_shape(VM vm, refptr objPtr, Tag protoTag)
    {
        // Get the initial object shape
        auto shape = vm.emptyShape.defProp(
            vm,
            "__proto__",
            ValType(protoTag),
            0,
            null
        );

        obj_set_shape(objPtr, cast(rawptr)shape);


        assert (
            vm.wUpperLimit > vm.wStack,
            "invalid wStack after init shape"
        );


    }

    auto vm = ver.state.fun.vm;

    // Get the object operand
    auto objOpnd = st.getWordOpnd(as, instr, 0, 64);
    assert (objOpnd.isReg);

    // Get the type operand for the prototype argument
    auto tagOpnd = st.getTagOpnd(as, instr, 1);

    // If the prototype tag is a constant
    if (tagOpnd.isImm)
    {
        // Get the initial object shape
        auto shape = vm.emptyShape.defProp(
            vm,
            "__proto__",
            ValType(cast(Tag)tagOpnd.imm.imm),
            0,
            null
        );

        // Set the object shape
        as.ptr(scrRegs[0], shape);
        as.setField(objOpnd.reg, obj_ofs_shape(null), scrRegs[0]);

        // Propagate the object shape
        st.setShape(cast(IRDstValue)instr.getArg(0), shape);
    }
    else
    {
        // Spill the values live before this instruction
        st.spillLiveBefore(as, instr);

        as.saveJITRegs();

        // Call the host function
        // Note: we move objOpnd first to avoid corruption
        as.mov(cargRegs[1].opnd(64), objOpnd);
        as.mov(cargRegs[0].opnd(64), vmReg.opnd);
        as.mov(cargRegs[2].opnd(8), tagOpnd);
        as.ptr(scrRegs[0], &op_obj_init_shape);
        as.call(scrRegs[0]);

        as.loadJITRegs();

        // Clear any known shape for this object
        st.clearShape(cast(IRDstValue)instr.getArg(0));
    }
}

/// Initializes an array to the initial shape
/// Inputs: arr
void gen_arr_init_shape(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto vm = ver.state.fun.vm;

    // Get the object operand
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64);
    assert (opnd0.isReg);

    // Load the array shape into r0
    as.getMember!("VM.arrayShape")(scrRegs[0], vmReg);

    // Set the object shape
    as.setField(opnd0.reg, obj_ofs_shape(null), scrRegs[0]);

    // Propagate the array shape
    st.setShape(cast(IRDstValue)instr.getArg(0), vm.arrayShape);
}

/// Sets the value of a property
/// Inputs: obj, propName, val
void gen_obj_set_prop(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static uint8_t op_shape_set_prop(IRInstr instr)
    {
        // Increment the host set prop stat
        ++stats.numSetPropHost;

        auto vm = instr.block.fun.vm;

        vm.setCurInstr(instr);

        auto objPair = vm.getArgVal(instr, 0);
        auto strPtr = vm.getArgStr(instr, 1);
        auto valPair = vm.getArgVal(instr, 2);

        auto propStr = extractWStr(strPtr);

        // Get the shape of the object
        auto objShape = cast(ObjShape)obj_get_shape(objPair.word.ptrVal);
        assert (objShape !is null);

        // Find the shape defining this property (if it exists)
        auto defShape = objShape.getDefShape(propStr);

        // Set the property value
        setProp(
            vm,
            objPair,
            propStr,
            valPair
        );

        vm.setCurInstr(null);

        return (!defShape || defShape.isGetSet is false)? 1:0;
    }

    static void gen_slow_path(
        BlockVersion ver,
        CodeGenState st,
        IRInstr instr,
        CodeBlock as
    )
    {
        // Get the object value
        auto objVal = cast(IRDstValue)instr.getArg(0);

        // Spill the values live before this instruction
        st.spillLiveBefore(as, instr);

        as.saveJITRegs();

        // Call the host function
        as.ptr(cargRegs[0], instr);
        as.ptr(scrRegs[0], &op_shape_set_prop);
        as.call(scrRegs[0]);

        as.loadJITRegs();

        // Clear any known shape for this object
        st.clearShape(objVal);

        // Check the success flag
        as.cmp(cretReg.opnd(8), X86Opnd(1));

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
                BlockVersion block,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                final switch (shape)
                {
                    case BranchShape.NEXT0:
                    jne32Ref(as, vm, block, target1, 1);
                    break;

                    case BranchShape.NEXT1:
                    je32Ref(as, vm, block, target0, 0);
                    break;

                    case BranchShape.DEFAULT:
                    je32Ref(as, vm, block, target0, 0);
                    jmp32Ref(as, vm, block, target1, 1);
                }
            }
        );
    }

    // Increment the number of set prop operations
    as.incStatCnt(&stats.numSetProp, scrRegs[1]);

    // Get the argument values
    auto objVal = cast(IRDstValue)instr.getArg(0);
    auto propVal = instr.getArg(2);

    // Extract the property name, if known
    auto propName = instr.getArgStrCst(1);

    // If the object shape is unknown, use the slow path
    if (!st.shapeKnown(objVal))
        return gen_slow_path(ver, st, instr, as);

    // If the property name is unknown, use the slow path
    if (propName is null)
        return gen_slow_path(ver, st, instr, as);

    // Get the type for the property value
    auto valType = st.getType(propVal).propType;

    // If we type of the property value is unknown, use the slow path
    if (!valType.tagKnown && !opts.shape_notagspec)
    {
        //as.printStr("val type unknown!");
        return gen_slow_path(ver, st, instr, as);
    }

    // Get the object and defining shapes
    auto objShape = st.getShape(objVal);
    assert (objShape !is null);

    // Try a lookup for an existing property
    auto defShape = objShape.getDefShape(propName);

    // If the defining shape was not found
    if (defShape is null)
    {
        // Create a new shape for the property
        defShape = objShape.defProp(
            st.fun.vm,
            propName,
            valType,
            ATTR_DEFAULT,
            null
        );
    }

    // If the property has accessors, jump to the false branch
    if (defShape.isGetSet)
        return gen_jump_false(ver, st, instr, as);

    // If the shape is not writable, do nothing, jump to the true branch
    if (!defShape.writable)
        return gen_jump(ver, st, instr, as);

    // Get the property slot index
    auto slotIdx = defShape.slotIdx;
    assert (slotIdx !is PROTO_SLOT_IDX);

    // Compute the minimum object capacity we can guarantee
    auto minObjCap = (
        (objVal is st.fun.globalVal)?
        obj_get_cap(st.fun.vm.globalObj.word.ptrVal):
        OBJ_MIN_CAP
    );

    // If the property exists on the object and is writable
    if (slotIdx <= objShape.slotIdx)
    {
        auto objOpnd = st.getWordOpnd(as, instr, 0, 64);
        auto valOpnd = st.getWordOpnd(as, instr, 2, 64, scrRegs[2].opnd(64), true);
        auto tagOpnd = st.getTagOpnd(as, instr, 2, X86Opnd.NONE, true);
        assert (objOpnd.isReg);

        // Check if we need to write the type tag
        bool writeTag = (valType.tag != defShape.type.tag) || !defShape.type.tagKnown;

        // If we need to write the type tag or check the object capacity
        if (writeTag || slotIdx >= minObjCap)
        {
            // Get the object capacity into r1
            as.getField(scrRegs[1].reg(32), objOpnd.reg, obj_ofs_cap(null));
        }

        auto tblOpnd = objOpnd;

        // If we can't guarantee that the slot index is within capacity,
        // generate the extension table code
        if (slotIdx >= minObjCap)
        {
            tblOpnd = scrRegs[0].opnd;

            // Move the object operand into r0
            as.mov(tblOpnd, objOpnd);

            // If the slot index is below capacity, skip the ext table code
            as.cmp(scrRegs[1].opnd, X86Opnd(slotIdx));
            as.jg(Label.SKIP);

            // Get the ext table pointer into r0
            as.getField(tblOpnd.reg, tblOpnd.reg, obj_ofs_next(null));

            // If we need to write the type tag
            if (writeTag)
            {
                // Get the ext table capacity into r1
                as.getField(scrRegs[1].reg(32), tblOpnd.reg, obj_ofs_cap(null));
            }

            as.label(Label.SKIP);
        }

        // Store the word value
        auto wordMem = X86Opnd(64, tblOpnd.reg, OBJ_WORD_OFS + 8 * slotIdx);
        as.genMove(wordMem, valOpnd);

        // If we need to write the type tag
        if (writeTag)
        {
            // Store the type tag
            auto typeMem = X86Opnd(8 , tblOpnd.reg, OBJ_WORD_OFS + slotIdx, 8, scrRegs[1]);
            as.genMove(typeMem, tagOpnd, scrRegs[2].opnd);
        }

        // If the value type doesn't match the shape type
        if (!valType.isSubType(defShape.type))
        {
            // Create a new shape for the property
            objShape = objShape.defProp(
                st.fun.vm,
                propName,
                valType,
                ATTR_DEFAULT,
                defShape
            );

            // Update the object shape
            as.ptr(scrRegs[2], objShape);
            as.setField(objOpnd.reg, obj_ofs_shape(null), scrRegs[2]);

            // Set the new object shape
            st.setShape(objVal, objShape);

            // Increment the number of shape changes due to type
            as.incStatCnt(&stats.numShapeFlips, scrRegs[0]);
        }

        // Property successfully set, jump to the true branch
        return gen_jump(ver, st, instr, as);
    }

    // This is a new property
    // If the slot index is within the guaranteed object capacity
    //
    // Note: we don't check if the property goes in the extended
    // table because we cant guarantee the object size is sufficient
    // or that the extended table even exists
    if (slotIdx < minObjCap)
    {
        auto objOpnd = st.getWordOpnd(as, instr, 0, 64);
        auto valOpnd = st.getWordOpnd(as, instr, 2, 64, scrRegs[0].opnd(64), true);
        auto tagOpnd = st.getTagOpnd(as, instr, 2, scrRegs[1].opnd(8), true);
        assert (objOpnd.isReg);

        // Get the object capacity into r2
        as.getField(scrRegs[2].reg(32), objOpnd.reg, obj_ofs_cap(null));

        // Set the word and tag values
        auto wordMem = X86Opnd(64, objOpnd.reg, OBJ_WORD_OFS + 8 * slotIdx);
        auto typeMem = X86Opnd(8 , objOpnd.reg, OBJ_WORD_OFS + slotIdx, 8, scrRegs[2]);
        as.mov(wordMem, valOpnd);
        as.mov(typeMem, tagOpnd);

        // Update the object shape
        as.ptr(scrRegs[0].reg, defShape);
        as.setField(objOpnd.reg, obj_ofs_shape(null), scrRegs[0].reg);

        // Set the new object shape
        st.setShape(objVal, defShape);

        // Property successfully set, jump to the true branch
        return gen_jump(ver, st, instr, as);
    }

    // Use the slow path
    return gen_slow_path(ver, st, instr, as);
}

/// Gets the value of a property
/// Inputs: obj, propName
void gen_obj_get_prop(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    struct OutVal
    {
        Word word;
        Tag tag;
        uint8_t success;
    }

    static assert (OutVal.sizeof == 2 * Word.sizeof);

    extern (C) static void op_obj_get_prop(
        OutVal* outVal,
        refptr objPtr,
        refptr strPtr
    )
    {
        // Increment the host get prop stat
        ++stats.numGetPropHost;

        // Get a temporary D string for the property name
        auto propStr = tempWStr(strPtr);

        // Get the shape of the object
        auto objShape = cast(ObjShape)obj_get_shape(objPtr);
        assert (objShape !is null);

        // Find the shape defining this property (if it exists)
        auto defShape = objShape.getDefShape(propStr);

        // If the property doesn't exist
        if (defShape is null)
        {
            outVal.word = UNDEF.word;
            outVal.tag = Tag.CONST;
            outVal.success = 0;
            return;
        }

        // Get the slot index and the object capacity
        uint32_t slotIdx = defShape.slotIdx;
        auto objCap = obj_get_cap(objPtr);

        if (slotIdx < objCap)
        {
            outVal.word = Word.int64v(obj_get_word(objPtr, slotIdx));
            outVal.tag = cast(Tag)obj_get_tag(objPtr, slotIdx);
        }
        else
        {
            auto extTbl = obj_get_next(objPtr);
            assert (slotIdx < obj_get_cap(extTbl));
            outVal.word = Word.int64v(obj_get_word(extTbl, slotIdx));
            outVal.tag = cast(Tag)obj_get_tag(extTbl, slotIdx);
        }

        outVal.success = (defShape.isGetSet is false)? 1:0;
    }

    static void gen_slow_path(
        BlockVersion ver,
        CodeGenState st,
        IRInstr instr,
        CodeBlock as
    )
    {
        // Spill the values live before this instruction
        st.spillLiveBefore(as, instr);

        // Get the object and string operands
        auto objOpnd = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);
        auto strOpnd = st.getWordOpnd(as, instr, 1, 64, scrRegs[0].opnd, false, false);

        auto outOpnd = st.getOutOpnd(as, instr, 64);

        as.saveJITRegs();

        // Stack allocate space for the value pair output
        as.sub(RSP, OutVal.sizeof);

        // Call the host function
        as.mov(cargRegs[0].opnd, RSP.opnd);
        as.mov(cargRegs[1].opnd, objOpnd);
        as.mov(cargRegs[2].opnd, strOpnd);
        as.ptr(scrRegs[0], &op_obj_get_prop);
        as.call(scrRegs[0]);

        // Free the extra stack space
        as.mov(scrRegs[0].opnd, RSP.opnd);
        as.add(RSP, OutVal.sizeof);

        as.loadJITRegs();

        auto wordMem = X86Opnd(64, scrRegs[0], OutVal.word.offsetof);
        auto tagMem = X86Opnd(8, scrRegs[0], OutVal.tag.offsetof);
        auto flagMem = X86Opnd(8, scrRegs[0], OutVal.success.offsetof);

        // Set the output word and tag
        as.mov(outOpnd, wordMem);
        as.mov(scrRegs[1].opnd(8), tagMem);
        st.setOutTag(as, instr, scrRegs[1].reg(8));

        // Check the success flag
        as.cmp(flagMem, X86Opnd(1));

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
                BlockVersion block,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                final switch (shape)
                {
                    case BranchShape.NEXT0:
                    jne32Ref(as, vm, block, target1, 1);
                    break;

                    case BranchShape.NEXT1:
                    je32Ref(as, vm, block, target0, 0);
                    break;

                    case BranchShape.DEFAULT:
                    je32Ref(as, vm, block, target0, 0);
                    jmp32Ref(as, vm, block, target1, 1);
                }
            }
        );
    }

    // Increment the number of get prop operations
    as.incStatCnt(&stats.numGetProp, scrRegs[1]);

    // Get the object argument
    auto objVal = cast(IRDstValue)instr.getArg(0);

    // Extract the property name, if known
    auto propName = instr.getArgStrCst(1);

    // If the object shape is unknown, use the slow path
    if (!st.shapeKnown(objVal))
        return gen_slow_path(ver, st, instr, as);

    // If the property name is unknown, use the slow path
    if (propName is null)
        return gen_slow_path(ver, st, instr, as);

    // Get the object and defining shapes
    auto objShape = st.getShape(objVal);
    assert (objShape !is null);

    // Try a lookup for an existing property
    auto defShape = objShape.getDefShape(propName);

    // If the property doesn't exist
    if (defShape is null)
    {
        auto outOpnd = st.getOutOpnd(as, instr, 64);

        // Set the output type tag to const (undefined)
        //as.mov(outOpnd, X86Opnd(UNDEF.word.int8Val));
        st.setOutTag(as, instr, Tag.CONST);

        // Jump to the false branch
        return gen_jump_false(ver, st, instr, as);
    }

    // Get the property slot index
    auto slotIdx = defShape.slotIdx;

    // Compute the minimum object capacity we can guarantee
    auto minObjCap = (
        (instr.getArg(0) is st.fun.globalVal)?
        obj_get_cap(st.fun.vm.globalObj.word.ptrVal):
        OBJ_MIN_CAP
    );

    // No need to get the shape operand
    auto objOpnd = st.getWordOpnd(as, instr, 0, 64);
    assert (objOpnd.isReg);
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    assert (outOpnd.isReg);

    // If we need to read the type tag or check the object capacity
    if (!defShape.type.tagKnown || slotIdx >= minObjCap)
    {
        // Get the object capacity into r1
        as.getField(scrRegs[1].reg(32), objOpnd.reg, obj_ofs_cap(null));
    }

    auto tblOpnd = objOpnd;

    // If we can't guarantee that the slot index is within capacity,
    // generate the extension table code
    if (slotIdx >= minObjCap)
    {
        tblOpnd = scrRegs[0].opnd;

        // Move the object operand into r0
        as.mov(tblOpnd, objOpnd);

        // If the slot index is below capacity, skip the ext table code
        as.cmp(scrRegs[1].opnd, X86Opnd(slotIdx));
        as.jg(Label.SKIP);

        // Get the ext table pointer into r0
        as.getField(tblOpnd.reg, tblOpnd.reg, obj_ofs_next(null));

        // If we need to read the type tag
        if (!defShape.type.tagKnown)
        {
            // Get the ext table capacity into r1
            as.getField(scrRegs[1].reg(32), tblOpnd.reg, obj_ofs_cap(null));
        }

        as.label(Label.SKIP);
    }

    // Load the word value
    auto wordMem = X86Opnd(64, tblOpnd.reg, OBJ_WORD_OFS + 8 * slotIdx);
    as.mov(outOpnd, wordMem);

    // If the property's type tag is known
    if (defShape.type.tagKnown)
    {
        // Propagate the shape type
        assert (!opts.shape_notagspec);
        st.setType(instr, defShape.type);
    }
    else
    {
        // Load the type value
        auto typeMem = X86Opnd(8, tblOpnd.reg, OBJ_WORD_OFS + slotIdx, 8, scrRegs[1]);
        as.mov(scrRegs[1].opnd(8), typeMem);
        st.setOutTag(as, instr, scrRegs[1].reg(8));
    }

    // If the property has accessors, jump to the false branch
    if (defShape.isGetSet)
        return gen_jump_false(ver, st, instr, as);

    // Normal property successfully read, jump to the true branch
    return gen_jump(ver, st, instr, as);
}

/// Get the prototype of an object
/// Inputs: obj
void gen_obj_get_proto(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // No need to get the shape operand
    auto objOpnd = st.getWordOpnd(as, instr, 0, 64);
    assert (objOpnd.isReg);
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    assert (outOpnd.isReg);

    // Get the object type
    auto objType = st.getType(instr.getArg(0));

    auto slotIdx = PROTO_SLOT_IDX;

    // If the object shape is known
    if (objType.shapeKnown)
    {
        auto defShape = objType.shape.getDefShape("__proto__");
        assert (defShape !is null);
        assert (defShape.slotIdx is slotIdx);

        // If the shape's type tag is known
        if (defShape.type.tagKnown)
        {
            // Load the word value
            auto wordMem = X86Opnd(64, objOpnd.reg, OBJ_WORD_OFS + 8 * slotIdx);
            as.mov(outOpnd, wordMem);

            // Set the output type tag
            st.setOutTag(as, instr, defShape.type.tag);

            return;
        }
    }

    // Get the object capacity into r1
    as.getField(scrRegs[1].reg(32), objOpnd.reg, obj_ofs_cap(null));

    // Load the word and tag values
    auto wordMem = X86Opnd(64, objOpnd.reg, OBJ_WORD_OFS + 8 * slotIdx);
    auto typeMem = X86Opnd(8 , objOpnd.reg, OBJ_WORD_OFS + slotIdx, 8, scrRegs[1]);
    as.mov(outOpnd, wordMem);
    as.mov(scrRegs[2].opnd(8), typeMem);

    // Set the output type tag
    st.setOutTag(as, instr, scrRegs[2].reg(8));
}

/// Define a constant property
/// Inputs: obj, propName, val, enumerable
void gen_obj_def_const(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static void op_shape_def_const(VM vm, IRInstr instr)
    {
        auto objPair = vm.getArgVal(instr, 0);
        auto strPtr = vm.getArgStr(instr, 1);
        auto valPair = vm.getArgVal(instr, 2);
        auto isEnum = vm.getArgBool(instr, 3);

        auto propStr = extractWStr(strPtr);

        // Attempt to define the constant
        defConst(
            vm,
            objPair,
            propStr,
            valPair,
            isEnum
        );
    }

    auto vm = st.fun.vm;

    // Get the object argument
    auto objDst = cast(IRDstValue)instr.getArg(0);
 
    // Spill the values live before this instruction
    st.spillLiveBefore(as, instr);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0].opnd(64), vmReg.opnd(64));
    as.ptr(cargRegs[1], instr);
    as.ptr(scrRegs[0], &op_shape_def_const);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Clear any known shape for this object
    st.clearShape(objDst);
}

/// Sets the attributes for a property
/// Inputs: obj, propName, attrBits
void gen_obj_set_attrs(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static void op_shape_set_attrs(VM vm, IRInstr instr)
    {
        auto objPair = vm.getArgVal(instr, 0);
        auto strPtr = vm.getArgStr(instr, 1);
        auto attrBits = vm.getArgUint32(instr, 2);

        auto propStr = extractWStr(strPtr);

        // Attempt to set the property attributes
        setPropAttrs(
            vm,
            objPair,
            propStr,
            cast(uint8_t)attrBits
        );
    }

    // Spill the values live before this instruction
    st.spillLiveBefore(as, instr);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0].opnd(64), vmReg.opnd(64));
    as.ptr(cargRegs[1], instr);
    as.ptr(scrRegs[0], &op_shape_set_attrs);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Clear any known shape for this object
    st.clearShape(cast(IRDstValue)instr.getArg(0));
}

/// Inputs: obj, propName
/// Get the shape associated with the property name (if any)
void gen_obj_prop_shape(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) ObjShape op_obj_prop_shape(
        refptr objPtr,
        refptr strPtr
    )
    {
        auto objShape = cast(ObjShape)obj_get_shape(objPtr);

        // Get a temporary D string for the property name
        auto propStr = tempWStr(strPtr);

        // Lookup the shape defining this property
        auto defShape = objShape.getDefShape(propStr);

        return defShape;
    }

    // Get the object argument value
    auto objVal = cast(IRDstValue)instr.getArg(0);

    // Extract the property name, if known
    auto propName = instr.getArgStrCst(1);

    // If the object shape and the property name are both known
    if (st.shapeKnown(objVal) && propName !is null)
    {
        //as.printStr("shape known");

        // Get the object shape
        auto objShape = st.getShape(objVal);
        assert (objShape !is null);

        // Get the output operand
        auto outOpnd = st.getOutOpnd(as, instr, 64);
        assert (outOpnd.isReg);

        // Get the defining shape for the property
        auto defShape = objShape.getDefShape(propName);

        as.ptr(outOpnd.reg, defShape);

        // Set the output type and shape for this instruction
        st.setOutTag(as, instr, Tag.SHAPEPTR);
        st.setShape(instr, defShape);

        return;
    }

    // Spill the values live before this instruction
    st.spillLiveBefore(as, instr);

    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);
    auto opnd1 = st.getWordOpnd(as, instr, 1, 64, scrRegs[0].opnd, false, false);
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0].opnd(64), opnd0);
    as.mov(cargRegs[1].opnd(64), opnd1);
    as.ptr(scrRegs[0], &op_obj_prop_shape);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    // Store the output value into the output operand
    as.mov(outOpnd, cretReg.opnd);

    // Set the output type for this instruction
    st.setOutTag(as, instr, Tag.SHAPEPTR);
}

/// Get the parent shape for a given shape
/// Inputs: shape
void gen_shape_get_parent(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static ObjShape op_shape_get_parent(ObjShape shape)
    {
        assert (shape !is null);
        return shape.parent;
    }

    // Spill the values live before this instruction
    st.spillLiveBefore(as, instr);

    auto shapeOpnd = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0].opnd(64), shapeOpnd);
    as.ptr(scrRegs[0], &op_shape_get_parent);
    as.call(scrRegs[0]);

    // Set the output value
    as.mov(outOpnd, cretReg.opnd);
    st.setOutTag(as, instr, Tag.SHAPEPTR);

    as.loadJITRegs();
}

/// Get the property name associated with a given shape
/// Inputs: shape
void gen_shape_prop_name(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr op_shape_prop_name(
        VM vm,
        IRInstr curInstr,
        ObjShape shape
    )
    {
        assert (shape !is null);

        vm.setCurInstr(curInstr);
        auto strObj = getString(vm, shape.propName);
        vm.setCurInstr(null);

        return strObj;
    }

    // Spill the values live before this instruction
    st.spillLiveBefore(as, instr);

    auto shapeOpnd = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.mov(cargRegs[2].opnd(64), shapeOpnd);
    as.ptr(scrRegs[0], &op_shape_prop_name);
    as.call(scrRegs[0]);

    // Set the output value
    as.mov(outOpnd, cretReg.opnd);
    st.setOutTag(as, instr, Tag.STRING);

    as.loadJITRegs();
}

/// Get the attributes associated with a given shape
/// Inputs: shape
void gen_shape_get_attrs(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static uint32 op_shape_get_attrs(ObjShape shape)
    {
        assert (shape !is null);
        return shape.attrs;
    }

    // Spill the values live before this instruction
    st.spillLiveBefore(as, instr);

    auto shapeOpnd = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, false, false);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0].opnd(64), shapeOpnd);
    as.ptr(scrRegs[0], &op_shape_get_attrs);
    as.call(scrRegs[0]);

    // Set the output value
    as.mov(outOpnd, cretReg.opnd(32));
    st.setOutTag(as, instr, Tag.INT32);

    as.loadJITRegs();
}

void gen_set_global(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static void op_set_global(VM vm, IRInstr instr)
    {
        // Property string (D string)
        auto strArg = cast(IRString)instr.getArg(0);
        assert (strArg !is null);
        auto propStr = strArg.str;

        auto valPair = vm.getArgVal(instr, 1);

        // Set the property value
        setProp(
            vm,
            vm.globalObj,
            propStr,
            valPair
        );

        assert (obj_get_cap(vm.globalObj.word.ptrVal) > 0);
    }

    // Spill the values that are live before the call
    st.spillValues(
        as,
        delegate bool(LiveInfo liveInfo, IRDstValue value)
        {
            return liveInfo.liveBefore(value, instr);
        }
    );

    as.saveJITRegs();

    // Call the host function
    as.mov(cargRegs[0].opnd(64), vmReg.opnd(64));
    as.ptr(cargRegs[1], instr);
    as.ptr(scrRegs[0], &op_set_global);
    as.call(scrRegs[0]);

    as.loadJITRegs();
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
        IRFunction fun
    )
    {
        vm.setCurInstr(curInstr);

        // If the function has no entry point code
        if (fun.entryCode is null)
        {
            // Store the entry code pointer
            fun.entryCode = getEntryStub(vm, false);
        }

        // Allocate the closure object
        auto closPtr = GCRoot(
            vm,
            newClos(
                vm,
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
    assert (funArg.fun !is null);

    as.saveJITRegs();

    as.mov(cargRegs[0], vmReg);
    as.ptr(cargRegs[1], instr);
    as.ptr(cargRegs[2], funArg.fun);
    as.ptr(scrRegs[0], &op_new_clos);
    as.call(scrRegs[0]);

    as.loadJITRegs();

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(cretReg));

    // Set the output type and mark the function pointer as known
    ValType outType = ValType(Tag.CLOSURE);
    outType.fptrKnown = true;
    outType.fptr = funArg.fun;
    st.setType(instr, outType);
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

void gen_print_ptr(
    BlockVersion ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto opnd = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd, false, false);

    as.printPtr(opnd);
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
        long epochTime = 621355968000000000; // unixTimeToStdTime(0);
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
    st.setOutTag(as, instr, Tag.FLOAT64);
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
    st.setOutTag(as, instr, Tag.STRING);
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
            // FIXME: function entry stubs are currently a hack
            // Need to be specialized to the IRFunction, not assume
            // that numLocals is the minimum value
            // Can't have unspecialized stubs for interprocedural BBV anyway!
            auto numLocals = fun.numLocals;
            astToIR(vm, fun.ast, fun);
            fun.numLocals = numLocals;
            fun.entryBlock = null;
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
    st.setOutTag(as, instr, Tag.STRING);
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

        // If this function has compiled code
        if (fun.versionMap.length > 0)
        {
            // Request an instance for the function entry block
            auto entryVer = getBlockVersion(
                fun.entryBlock,
                new CodeGenState(fun)
            );

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
    st.setOutTag(as, instr, Tag.STRING);
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

        // Filename must be either a zero-terminated string or null
        auto filename = libname ? toStringz(libname) : null;

        // If filename is null the returned handle will be the main program
        auto lib = dlopen(filename, RTLD_LAZY | RTLD_LOCAL);

        if (lib is null)
        {
            return throwError(
                vm,
                instr,
                null,
                "ReferenceError",
                to!string(dlerror())
            );
        }

        vm.push(Word.ptrv(cast(rawptr)lib), Tag.RAWPTR);

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
    as.add(tspReg, Tag.sizeof);
    as.mov(outOpnd, scrRegs[0].opnd);
    st.setOutTag(as, instr, Tag.RAWPTR);
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
            libArg.tag == Tag.RAWPTR,
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
            libArg.tag == Tag.RAWPTR,
            "get_sym: invalid lib rawptr value"
        );

        // Symbol name string
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

        vm.push(Word.ptrv(cast(rawptr)sym), Tag.RAWPTR);

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
    as.add(tspReg, Tag.sizeof);
    as.mov(outOpnd, scrRegs[0].opnd);
    st.setOutTag(as, instr, Tag.RAWPTR);

}

// TODO: add support for new i types
// Mappings for arguments/return values
Tag[string] typeMap;
size_t[string] sizeMap;
static this()
{
    typeMap = [
        "i8"  : Tag.INT32,
        "i16" : Tag.INT32,
        "i32" : Tag.INT32,
        "i64" : Tag.INT64,
        "u8"  : Tag.INT32,
        "u16" : Tag.INT32,
        "u32" : Tag.INT32,
        "u64" : Tag.INT64,
        "f64" : Tag.FLOAT64,
        "*"   : Tag.RAWPTR
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
    auto vm = st.fun.vm;

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
    size_t[] stackArgs;

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
        st.setOutTag(as, instr, typeMap[retType]);
    }
    else if (retType == "void")
    {
        as.mov(outOpnd, X86Opnd(UNDEF.word.int8Val));
        st.setOutTag(as, instr, Tag.CONST);
    }
    else
    {
        as.mov(outOpnd, X86Opnd(RAX));
        st.setOutTag(as, instr, typeMap[retType]);
    }

    // Jump directly to the successor block
    return gen_jump(ver, st, instr, as);
}

