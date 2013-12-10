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

module jit.ops;

import std.stdio;
import std.string;
import std.array;
import std.stdint;
import std.conv;
import std.algorithm;
import options;
import stats;
import ir.ir;
import ir.ops;
import ir.ast;
import interp.interp;
import interp.layout;
import interp.object;
import interp.string;
import interp.gc;
import jit.codeblock;
import jit.x86;
import jit.jit;

/// Instruction code generation function
alias void function(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
) GenFn;

void gen_get_arg(
    VersionInst ver, 
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
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto linkVal = cast(IRLinkIdx)instr.getArg(1);
    assert (linkVal !is null);

    if (linkVal.linkIdx is NULL_LINK)
    {
        auto interp = st.ctx.interp;

        // Find the string in the string table
        auto strArg = cast(IRString)instr.getArg(0);
        assert (strArg !is null);
        auto strPtr = getString(interp, strArg.str);

        // Allocate a link table entry
        linkVal.linkIdx = interp.allocLink();

        interp.setLinkWord(linkVal.linkIdx, Word.ptrv(strPtr));
        interp.setLinkType(linkVal.linkIdx, Type.REFPTR);
    }

    as.getMember!("Interp.wLinkTable")(scrRegs[0], interpReg);
    as.mov(scrRegs[0].opnd(64), X86Opnd(64, scrRegs[0], 8 * linkVal.linkIdx));

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, scrRegs[0].opnd(64));

    st.setOutType(as, instr, Type.REFPTR);
}

void gen_make_value(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Move the word value into the output word
    auto wordOpnd = st.getWordOpnd(as, instr, 0, 64, scrRegs[0].opnd(64), true);
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, wordOpnd);

    // Get the type value from the second operand
    auto typeOpnd = st.getWordOpnd(as, instr, 1, 8, scrRegs[0].opnd(8));
    assert (typeOpnd.isGPR);
    st.setOutType(as, instr, typeOpnd.reg);
}

void gen_get_word(
    VersionInst ver, 
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
    VersionInst ver, 
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
    VersionInst ver, 
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
    VersionInst ver, 
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
    as.cvtsd2si(scrRegs[0].opnd(64), X86Opnd(XMM0));
    as.mov(outOpnd, scrRegs[0].opnd(32));

    st.setOutType(as, instr, Type.INT32);
}

void RMMOp(string op, size_t numBits, Type typeTag)(
    VersionInst ver, 
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
        false
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

    auto opndOut = st.getOutOpnd(as, instr, numBits);

    if (op == "imul")
    {
        // imul does not support memory operands as output
        auto scrReg = scrRegs[2].opnd(numBits);
        as.mov(scrReg, opnd1);
        mixin(format("as.%s(scrReg, opnd0);", op));
        as.mov(opndOut, scrReg);
    }
    else
    {
        if (opnd0 == opndOut)
        {
            mixin(format("as.%s(opndOut, opnd1);", op));
        }
        else if (opnd1 == opndOut)
        {
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
        auto branchNO = getBranchEdge(as, instr.getTarget(0), st, false);
        auto branchOV = getBranchEdge(as, instr.getTarget(1), st, false);

        // Generate the branch code
        ver.genBranch(
            as,
            instr,
            branchNO,
            branchOV,
            BranchShape.DEFAULT,
            function void(
                CodeBlock as,
                FragmentRef[]* refList,
                IRInstr instr,
                CodeFragment target0,
                CodeFragment target1,
                BranchShape shape
            )
            {
                jno32Ref(as, refList, target0);
                jmp32Ref(as, refList, target1);
            }
        );

        // Generate the edge code
        branchNO.genCode(as, st);
        branchOV.genCode(as, st);
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

void divOp(string op)(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto opnd0 = st.getWordOpnd(as, instr, 0, 32, X86Opnd.NONE, true);
    auto opnd1 = st.getWordOpnd(as, instr, 1, 32, scrRegs[2].opnd(32), false, true);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    // Save RDX
    as.mov(scrRegs[1].opnd(64), X86Opnd(RDX));
    if (opnd1.isReg && opnd1.reg == EDX)
        opnd1 = scrRegs[1].opnd(32);

    // Move the dividend into EAX
    as.mov(X86Opnd(EAX), opnd0);

    // Sign-extend EAX into EDX:EAX
    as.cdq();

    // Signed divide/quotient EDX:EAX by r/m32
    as.idiv(opnd1);

    if (!outOpnd.isReg || outOpnd.reg != EDX)
    {
        // Store the divisor or remainder into the output operand
        static if (op == "div")
            as.mov(outOpnd, X86Opnd(EAX));
        else if (op == "mod")
            as.mov(outOpnd, X86Opnd(EDX));
        else
            assert (false);

        // Restore RDX
        as.mov(X86Opnd(RDX), scrRegs[1].opnd(64));
    }

    // Set the output type
    st.setOutType(as, instr, Type.INT32);
}

alias divOp!("div") gen_div_i32;
alias divOp!("mod") gen_mod_i32;

void gen_not_i32(
    VersionInst ver,
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
    VersionInst ver,
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto opnd0 = st.getWordOpnd(as, instr, 0, 32, X86Opnd.NONE, true);
    auto opnd1 = st.getWordOpnd(as, instr, 1, 8, X86Opnd.NONE, true);
    auto outOpnd = st.getOutOpnd(as, instr, 32);

    // Save RCX
    as.mov(scrRegs[1].opnd(64), X86Opnd(RCX));

    as.mov(scrRegs[0].opnd(32), opnd0);
    as.mov(X86Opnd(CL), opnd1);

    static if (op == "sal")
        as.sal(scrRegs[0].opnd(32), X86Opnd(CL));
    else if (op == "sar")
        as.sar(scrRegs[0].opnd(32), X86Opnd(CL));
    else if (op == "shr")
        as.shr(scrRegs[0].opnd(32), X86Opnd(CL));
    else
        assert (false);

    // Restore RCX
    as.mov(X86Opnd(RCX), scrRegs[1].opnd(64));

    as.mov(outOpnd, scrRegs[0].opnd(32));

    // Set the output type
    st.setOutType(as, instr, Type.INT32);
}

alias ShiftOp!("sal") gen_lsft_i32;
alias ShiftOp!("sar") gen_rsft_i32;
alias ShiftOp!("shr") gen_ursft_i32;

void FPOp(string op)(
    VersionInst ver, 
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

void LoadOp(size_t memSize, Type typeTag)(
    VersionInst ver, 
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

    auto outOpnd = st.getOutOpnd(as, instr, 64);

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
    if (outOpnd.isMem || memSize == 32)    
    {
        size_t scrSize = (memSize == 32)? 32:64;
        auto scrReg64 = scrRegs[2].opnd(64);
        auto scrReg = X86Opnd(X86Reg(X86Reg.GP, scrReg64.reg.regNo, scrSize));

        // Load to a scratch register and then move to the output
        static if (memSize == 8 || memSize == 16)
            as.movzx(scrReg64, memOpnd);
        else
            as.mov(scrReg, memOpnd);

        as.mov(outOpnd, scrReg64);
    }
    else
    {
        // Load to the output register directly
        static if (memSize == 8 || memSize == 16)
            as.movzx(outOpnd, memOpnd);
        else
            as.mov(outOpnd, memOpnd);
    }

    // Set the output type tag
    st.setOutType(as, instr, typeTag);
}

alias LoadOp!(8 , Type.INT32) gen_load_u8;
alias LoadOp!(16, Type.INT32) gen_load_u16;
alias LoadOp!(32, Type.INT32) gen_load_u32;
alias LoadOp!(64, Type.INT64) gen_load_u64;
alias LoadOp!(64, Type.FLOAT64) gen_load_f64;
alias LoadOp!(64, Type.REFPTR) gen_load_refptr;
alias LoadOp!(64, Type.RAWPTR) gen_load_rawptr;
alias LoadOp!(64, Type.FUNPTR) gen_load_funptr;
alias LoadOp!(64, Type.MAPPTR) gen_load_mapptr;

void StoreOp(size_t memSize, Type typeTag)(
    VersionInst ver, 
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
alias StoreOp!(64, Type.FLOAT64) gen_store_f64;
alias StoreOp!(64, Type.REFPTR) gen_store_refptr;
alias StoreOp!(64, Type.RAWPTR) gen_store_rawptr;
alias StoreOp!(64, Type.FUNPTR) gen_store_funptr;
alias StoreOp!(64, Type.MAPPTR) gen_store_mapptr;

void gen_get_str(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) refptr getStr(Interp interp, refptr strPtr)
    {
        // Compute and set the hash code for the string
        auto hashCode = compStrHash(strPtr);
        str_set_hash(strPtr, hashCode);

        // Find the corresponding string in the string table
        return getTableStr(interp, strPtr);
    }

    // Get the string pointer
    auto opnd0 = st.getWordOpnd(as, instr, 0, 64, X86Opnd.NONE, true, false);

    // TODO: spill regs, may GC

    // Allocate the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.pushJITRegs();

    // Call the fallback implementation
    as.ptr(cargRegs[0], st.ctx.interp);
    as.mov(cargRegs[1].opnd(64), opnd0);
    as.ptr(scrRegs[0], &getStr);
    as.call(scrRegs[0]);

    as.popJITRegs();

    // Store the output value into the output operand
    as.mov(outOpnd, X86Opnd(RAX));

    // The output is a reference pointer
    st.setOutType(as, instr, Type.REFPTR);
}

void gen_get_global(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto interp = st.ctx.interp;

    // Name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Lookup the property index in the class
    // if the property slot doesn't exist, it will be allocated
    auto globalMap = cast(ObjMap)obj_get_map(interp.globalObj);
    assert (globalMap !is null);
    auto propIdx = globalMap.getPropIdx(nameStr, true);


    // TODO: if propIdx not found, need to do full lookup using getPropObj
    assert (propIdx !is uint32_t.max);







    // Allocate the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    // Get the global object pointer
    as.getMember!("Interp.globalObj")(scrRegs[0], interpReg);

    // Get the global object size/capacity
    as.getField(scrRegs[1].reg(32), scrRegs[0], 4, obj_ofs_cap(interp.globalObj));

    // Get the offset of the start of the word array
    auto wordOfs = obj_ofs_word(interp.globalObj, 0);

    // Get the word value from the object
    auto wordMem = X86Opnd(64, scrRegs[0], wordOfs + 8 * propIdx);
    if (outOpnd.isReg)
    {
        as.mov(outOpnd, wordMem);
    }
    else
    {
        as.mov(X86Opnd(scrRegs[2]), wordMem);
        as.mov(outOpnd, X86Opnd(scrRegs[2]));
    }

    // Get the type value from the object
    auto typeMem = X86Opnd(8, scrRegs[0], wordOfs + propIdx, 8, scrRegs[1]);
    as.mov(scrRegs[2].opnd(8), typeMem);

    // Set the type value
    st.setOutType(as, instr, scrRegs[2].reg(8));
}

void gen_set_global(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto interp = st.ctx.interp;

    // Name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Lookup the property index in the class
    // if the property slot doesn't exist, it will be allocated
    auto globalMap = cast(ObjMap)obj_get_map(interp.globalObj);
    assert (globalMap !is null);
    auto propIdx = globalMap.getPropIdx(nameStr, true);

    // TODO: preallocate slot in global object?
    // this would prevent GC at execution time

    // Allocate the input operand
    auto argOpnd = st.getWordOpnd(as, instr, 1, 64, scrRegs[0].opnd(64), true);

    // Get the global object pointer
    as.getMember!("Interp.globalObj")(scrRegs[1], interpReg);

    // Get the global object size/capacity
    as.getField(scrRegs[2].reg(32), scrRegs[1], 4, obj_ofs_cap(interp.globalObj));

    // Get the offset of the start of the word array
    auto wordOfs = obj_ofs_word(interp.globalObj, 0);

    // Set the word value
    auto wordMem = X86Opnd(64, scrRegs[1], wordOfs + 8 * propIdx);
    as.mov(wordMem, argOpnd);

    // Set the type value
    auto typeOpnd = st.getTypeOpnd(as, instr, 1, scrRegs[0].opnd(8), true);
    auto typeMem = X86Opnd(8, scrRegs[1], wordOfs + propIdx, 8, scrRegs[2]);
    as.mov(typeMem, typeOpnd);
}

void GetValOp(string fName)(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // Get the output operand. This must be a 
    // register since it's the only operand.
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    // FIXME
    //assert (outOpnd.isReg, "output is not a register");
    //ctx.as.getMember!("Interp", fName)(outOpnd, interpReg);

    as.getMember!("Interp." ~ fName)(scrRegs[0], interpReg);
    as.mov(outOpnd, scrRegs[0].opnd(64));

    st.setOutType(as, instr, Type.REFPTR);
}

alias GetValOp!("objProto") gen_get_obj_proto;
alias GetValOp!("arrProto") gen_get_arr_proto;
alias GetValOp!("funProto") gen_get_fun_proto;
alias GetValOp!("globalObj") gen_get_global_obj;

void gen_heap_alloc(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr allocFallback(Interp interp, uint32_t allocSize)
    {
        return heapAlloc(interp, allocSize);
    }

    // Get the allocation size operand
    auto szOpnd = st.getWordOpnd(as, instr, 0, 32, X86Opnd.NONE, true);

    // Get the output operand
    auto outOpnd = st.getOutOpnd(as, instr, 64);

    as.getMember!("Interp.allocPtr")(scrRegs[0], interpReg);
    as.getMember!("Interp.heapLimit")(scrRegs[1], interpReg);

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
    as.setMember!("Interp.allocPtr")(interpReg, scrRegs[2]);

    // Done allocating
    as.jmp(Label.DONE);

    // Clone the state for the bailout case, which will spill for GC
    auto bailSt = new CodeGenState(st);

    // Allocation fallback
    as.label(Label.FALLBACK);

    // TODO: proper spilling logic
    // need to spill delayed writes too

    // Save our allocated registers before the C call
    if (allocRegs.length % 2 != 0)
        as.push(allocRegs[0]);
    foreach (reg; allocRegs)
        as.push(reg);

    as.printStr("alloc bailout ***");

    // Call the fallback implementation
    as.ptr(cargRegs[0], st.ctx.interp);
    as.mov(cargRegs[1].opnd(32), szOpnd);
    as.ptr(RAX, &allocFallback);
    as.call(RAX);

    as.printStr("alloc bailout done ***");

    // Restore the allocated registers
    foreach_reverse(reg; allocRegs)
        as.pop(reg);
    if (allocRegs.length % 2 != 0)
        as.pop(allocRegs[0]);

    // Store the output value into the output operand
    as.mov(outOpnd, X86Opnd(RAX));

    // Allocation done
    as.label(Label.DONE);

    // The output is a reference pointer
    st.setOutType(as, instr, Type.REFPTR);
}

/*
void gen_get_link(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Get the link index operand
    auto idxReg = cast(X86Reg)st.getWordOpnd(ctx, ctx.as, instr, 0, 64, scrRegs64[0]);

    // Get the output operand
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);

    // Read the link word
    ctx.as.getMember!("Interp", "wLinkTable")(scrRegs64[1], interpReg);
    auto wordMem = new X86Mem(64, scrRegs64[1], 0, idxReg, Word.sizeof);
    ctx.as.instr(MOV, scrRegs64[1], wordMem);

    // Move the link word into the output operand
    ctx.as.instr(MOV, outOpnd, scrRegs64[1]);

    // Read the link type
    ctx.as.getMember!("Interp", "tLinkTable")(scrRegs64[1], interpReg);
    auto typeMem = new X86Mem(8, scrRegs64[1], 0, idxReg, Type.sizeof);
    ctx.as.instr(MOV, scrRegs8[1], typeMem);

    // Set the output type
    st.setOutType(ctx.as, instr, scrRegs8[1]);
}
*/

/**
Generates the conditional branch for an if_true instruction with the given
conditional jump operations. Assumes a comparison between input operands has
already been inserted.
*/
/*
void genCondBranch(
    CodeGenCtx ctx, 
    IRInstr ifInstr,
    CondOps condOps,
    CodeGenState trueSt,
    CodeGenState falseSt
)
{
    auto trueTarget = ifInstr.getTarget(0);
    auto falseTarget = ifInstr.getTarget(1);

    auto trueLabel = new Label("IF_TRUE");
    auto falseLabel = new Label("IF_FALSE");

    // If the true branch is more often executed
    if (trueTarget.target.execCount > falseTarget.target.execCount)
    {
        if (condOps.jccF[0])
        {
            // Jump out of line to the false case
            foreach (jccF; condOps.jccF)
                if (jccF) ctx.as.instr(jccF, falseLabel);

            // Jump directly to the true case
            ctx.as.instr(JMP, trueLabel);
        }
        else
        {
            // Jump conditionally to the true case
            assert (condOps.jccF[0]);
            foreach (jccT; condOps.jccT)
                if (jccT) ctx.as.instr(jccT, trueLabel);

            // Jump to the false case
            ctx.as.instr(JMP, falseLabel);
        }

        // Get the fast target label last so the fast target is
        // more likely to get generated first (LIFO stack)
        ctx.genBranchEdge(ctx.as, falseLabel, falseTarget, falseSt);
        ctx.genBranchEdge(ctx.as, trueLabel, trueTarget, trueSt);
    }
    else
    {
        if (condOps.jccT[0])
        {
            // Jump out of line to the true case
            foreach (jccT; condOps.jccT)
                if (jccT) ctx.as.instr(jccT, trueLabel);

            // Jump directly to the false case
            ctx.as.instr(JMP, falseLabel);
        }
        else
        {
            // Jump conditionally to the false case
            assert (condOps.jccF[0]);
            foreach (jccF; condOps.jccF)
                if (jccF) ctx.as.instr(jccF, falseLabel);

            // Jump to the true case
            ctx.as.instr(JMP, trueLabel);
        }

        // Get the fast target label last so the fast target is
        // more likely to get generated first (LIFO stack)
        ctx.genBranchEdge(ctx.as, trueLabel, trueTarget, trueSt);
        ctx.genBranchEdge(ctx.as, falseLabel, falseTarget, falseSt);
    }
}
*/

/**
Generate a boolean output value for an instruction based
on a preceding comparison instruction's output
*/
/*
void genBoolOut(
    CodeGenCtx ctx,
    CodeGenState st,
    IRInstr instr,
    CondOps condOps,
)
{
    // We must have a register for the output (so we can use cmov)
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);
    auto outReg = cast(X86Reg)opndOut;
    if (outReg is null)
        outReg = scrRegs64[0];
    auto outReg32 = outReg.reg(32);

    if (condOps.cmovT[0])
    {
        ctx.as.instr(MOV, outReg32, FALSE.int8Val);
        ctx.as.instr(MOV, scrRegs32[1], TRUE.int8Val);
        foreach (cmovT; condOps.cmovT)
            if (cmovT) ctx.as.instr(cmovT, outReg32, scrRegs32[1]);
    }
    else
    {
        assert (condOps.cmovF[0]);
        ctx.as.instr(MOV, outReg32, TRUE.int8Val);
        ctx.as.instr(MOV, scrRegs32[1], FALSE.int8Val);
        foreach (cmovF; condOps.cmovF)
            if (cmovF) ctx.as.instr(cmovF, outReg32, scrRegs32[1]);
    }

    // If the output is not a register
    if (opndOut !is outReg)
        ctx.as.instr(MOV, opndOut, outReg);

    // Set the output type
    st.setOutType(ctx.as, instr, Type.CONST);
}
*/

/**
Test if an instruction is followed by an if_true branching on its value
*/
bool ifUseNext(IRInstr instr)
{
    return (
        instr.next &&
        instr.next.opcode is &IF_TRUE &&
        instr.next.getArg(0) is instr
    );
}

/**
Test if our argument precedes and generates a boolean value
*/
bool boolArgPrev(IRInstr instr)
{
    return (
        instr.getArg(0) is instr.prev &&
        instr.prev.opcode.boolVal
    );
}

void IsTypeOp(Type type)(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto argVal = instr.getArg(0);

    /*
    // If the type of the argument is known
    if (st.typeKnown(argVal))
    {
        // Mark the value as a known constant
        // This will defer writing the value
        auto knownType = st.getType(argVal);
        st.setOutBool(instr, type is knownType);

        return;
    }
    */

    //ctx.as.printStr(instr.opcode.mnem ~ " (" ~ instr.block.fun.getName ~ ")");

    // Increment the stat counter for this specific kind of type test
    as.incStatCnt(stats.getTypeTestCtr(instr.opcode.mnem), scrRegs[0]);

    // Get an operand for the value's type
    auto typeOpnd = st.getTypeOpnd(as, instr, 0);




    // We must have a register for the output (so we can use cmov)
    auto outOpnd = st.getOutOpnd(as, instr, 64);
    X86Opnd outReg = outOpnd.isReg? outOpnd:scrRegs[0].opnd(64);

    // Compare against the tested type
    as.cmp(typeOpnd, X86Opnd(type));

    // Generate a boolean output value
    as.mov(outReg, X86Opnd(FALSE.int8Val));
    as.mov(scrRegs[1].opnd(64), X86Opnd(TRUE.int8Val));
    as.cmove(outReg.reg, scrRegs[1].opnd(64));

    // If the output register is not the output operand
    if (outReg != outOpnd)
        as.mov(outOpnd, outReg);

    // Set the output type
    st.setOutType(as, instr, Type.CONST);






    /*
    // If this instruction has many uses or is not followed by an if
    if (instr.hasManyUses || ifUseNext(instr) is false)
    {
        // Generate a boolean output
        ctx.genBoolOut(st, instr, CondOps.cmov(CMOVE, CMOVNE));
    }

    // If our only use is an immediately following if_true
    if (ifUseNext(instr) is true)
    {
        // If the test is true, we now known the value's type
        auto dstValue = cast(IRDstValue)argVal;
        assert (dstValue !is null);
        auto trueSt = new CodeGenState(st);
        trueSt.setKnownType(dstValue, type);

        // Generate the conditional branch and targets here
        ctx.genCondBranch(instr.next, CondOps.jcc(JE, JNE), trueSt, st);
    }
    */
}

alias IsTypeOp!(Type.CONST) gen_is_const;
alias IsTypeOp!(Type.REFPTR) gen_is_refptr;
alias IsTypeOp!(Type.RAWPTR) gen_is_rawptr;
alias IsTypeOp!(Type.INT32) gen_is_i32;
alias IsTypeOp!(Type.INT64) gen_is_i64;
alias IsTypeOp!(Type.FLOAT64) gen_is_f64;

void CmpOp(string op, size_t numBits)(
    VersionInst ver, 
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
    X86Opnd outReg = outOpnd.isReg? outOpnd:scrRegs[0].opnd(64);

    // Integer comparison
    static if (op == "eq")
    {
        as.cmp(opnd0, opnd1);
        as.mov(outReg, X86Opnd(FALSE.int8Val));
        as.mov(scrRegs[1].opnd(64), X86Opnd(TRUE.int8Val));
        as.cmove(outReg.reg, scrRegs[1].opnd(64));
    }
    else if (op == "ne")
    {
        as.cmp(opnd0, opnd1);
        as.mov(outReg, X86Opnd(FALSE.int8Val));
        as.mov(scrRegs[1].opnd(64), X86Opnd(TRUE.int8Val));
        as.cmovne(outReg.reg, scrRegs[1].opnd(64));
    }
    else if (op == "lt")
    {
        as.cmp(opnd0, opnd1);
        as.mov(outReg, X86Opnd(FALSE.int8Val));
        as.mov(scrRegs[1].opnd(64), X86Opnd(TRUE.int8Val));
        as.cmovl(outReg.reg, scrRegs[1].opnd(64));
    }

    else if (op == "le")
    {
        as.cmp(opnd0, opnd1);
        as.mov(outReg, X86Opnd(FALSE.int8Val));
        as.mov(scrRegs[1].opnd(64), X86Opnd(TRUE.int8Val));
        as.cmovle(outReg.reg, scrRegs[1].opnd(64));
    }
    else if (op == "gt")
    {
        as.cmp(opnd0, opnd1);
        as.mov(outReg, X86Opnd(FALSE.int8Val));
        as.mov(scrRegs[1].opnd(64), X86Opnd(TRUE.int8Val));
        as.cmovg(outReg.reg, scrRegs[1].opnd(64));
    }
    else if (op == "ge")
    {
        as.cmp(opnd0, opnd1);
        as.mov(outReg, X86Opnd(FALSE.int8Val));
        as.mov(scrRegs[1].opnd(64), X86Opnd(TRUE.int8Val));
        as.cmovge(outReg.reg, scrRegs[1].opnd(64));
    }

    // Floating-point comparisons
    // From the Intel manual, EFLAGS are:
    // UNORDERED:    ZF, PF, CF ← 111;
    // GREATER_THAN: ZF, PF, CF ← 000;
    // LESS_THAN:    ZF, PF, CF ← 001;
    // EQUAL:        ZF, PF, CF ← 100;
    /*
    static if (op == "feq")
    {
        // feq:
        // True: 100
        // False: 111 or 000 or 001
        // False: JNE + JP
        ctx.as.instr(UCOMISD, opnd0, opnd1);
        condOps.cmovF = [CMOVNE, CMOVP];
        condOps.jccF  = [JNE, JP];
    }
    static if (op == "fne")
    {
        // fne: 
        // True: 111 or 000 or 001
        // False: 100
        // True: JNE + JP
        ctx.as.instr(UCOMISD, opnd0, opnd1);
        condOps.cmovT = [CMOVNE, CMOVP];
        condOps.jccT  = [JNE, JP];
    }
    static if (op == "flt")
    {
        ctx.as.instr(UCOMISD, opnd1, opnd0);
        condOps.cmovT[0] = CMOVA;
        condOps.jccT [0] = JA;
        condOps.jccF [0] = JNA;
    }
    static if (op == "fle")
    {
        ctx.as.instr(UCOMISD, opnd1, opnd0);
        condOps.cmovT[0] = CMOVAE;
        condOps.jccT [0] = JAE;
        condOps.jccF [0] = JNAE;
    }
    static if (op == "fgt")
    {
        ctx.as.instr(UCOMISD, opnd0, opnd1);
        condOps.cmovT[0] = CMOVA;
        condOps.jccT [0] = JA;
        condOps.jccF [0] = JNA;
    }
    static if (op == "fge")
    {
        ctx.as.instr(UCOMISD, opnd0, opnd1);
        condOps.cmovT[0] = CMOVAE;
        condOps.jccT [0] = JAE;
        condOps.jccF [0] = JNAE;
    }
    */

    else
    {
        assert (false);
    }

    // If the output register is not the output operand
    if (outReg != outOpnd)
        as.mov(outOpnd, outReg);

    // Set the output type
    st.setOutType(as, instr, Type.CONST);





    /*
    // If this instruction has many uses or is not followed by an if
    if (instr.hasManyUses || ifUseNext(instr) is false)
    {
        // Generate a boolean output
        ctx.genBoolOut(st, instr, condOps);
    }

    // If our only use is an immediately following if_true
    if (ifUseNext(instr) is true)
    {
        // Generate the conditional branch and targets here
        ctx.genCondBranch(instr.next, condOps, st, st);
    }
    */
}

alias CmpOp!("eq", 8) gen_eq_i8;
alias CmpOp!("eq", 32) gen_eq_i32;
alias CmpOp!("ne", 32) gen_ne_i32;
alias CmpOp!("lt", 32) gen_lt_i32;
alias CmpOp!("le", 32) gen_le_i32;
alias CmpOp!("gt", 32) gen_gt_i32;
alias CmpOp!("ge", 32) gen_ge_i32;
alias CmpOp!("eq", 8) gen_eq_const;
alias CmpOp!("ne", 8) gen_ne_const;
alias CmpOp!("eq", 64) gen_eq_refptr;
alias CmpOp!("ne", 64) gen_ne_refptr;
alias CmpOp!("eq", 64) gen_eq_rawptr;
alias CmpOp!("ne", 64) gen_ne_rawptr;
//alias CmpOp!("feq", 64) gen_eq_f64;
//alias CmpOp!("fne", 64) gen_ne_f64;
//alias CmpOp!("flt", 64) gen_lt_f64;
//alias CmpOp!("fle", 64) gen_le_f64;
//alias CmpOp!("fgt", 64) gen_gt_f64;
//alias CmpOp!("fge", 64) gen_ge_f64;

void gen_if_true(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto argVal = instr.getArg(0);

    // TODO
    /*
    // If the argument is a known constant
    if (st.wordKnown(argVal))
    {
        auto targetT = instr.getTarget(0);
        auto targetF = instr.getTarget(1);

        auto argWord = st.getWord(argVal);
        auto target = (argWord == TRUE)? targetT:targetF;
        ctx.genBranchEdge(ctx.as, null, target, st);

        return;
    }
    */

    // If a boolean argument immediately precedes, the
    // conditional branch has already been generated
    //if (boolArgPrev(instr) is true)
    //    return;

    // Compare the argument to the true boolean value
    auto argOpnd = st.getWordOpnd(as, instr, 0, 8);
    as.cmp(argOpnd, X86Opnd(TRUE.int8Val));

    auto branchT = getBranchEdge(as, instr.getTarget(0), st, false);
    auto branchF = getBranchEdge(as, instr.getTarget(1), st, false);

    // Generate the branch code
    ver.genBranch(
        as,
        instr,
        branchT,
        branchF,
        BranchShape.DEFAULT,
        function void(
            CodeBlock as,
            FragmentRef[]* refList,
            IRInstr instr,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            je32Ref(as, refList, target0);
            jmp32Ref(as, refList, target1);
        }
    );

    // Generate the edge code
    branchT.genCode(as, st);
    branchF.genCode(as, st);
}

void gen_jump(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto branch = getBranchEdge(
        as,
        instr.getTarget(0),
        st,
        true
    );

    // Jump to the target block directly
    ver.genBranch(
        as,
        instr,
        branch,
        null,
        BranchShape.DEFAULT,
        function void(
            CodeBlock as,
            FragmentRef[]* refList,
            IRInstr instr,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            jmp32Ref(as, refList, target0);
        }
    );

    // Generate the branch edge code
    branch.genCode(as, st);
}

void gen_call(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    // TODO: just steal an allocatable reg to use as an extra temporary
    // force its contents to be spilled if necessary
    // maybe add State.freeReg method
    auto scrReg3 = allocRegs[$-1];

    // TODO : save the state before spilling?
    // TODO
    /*
    // Spill the values that are live after the call
    st.spillRegs(
        ctx.as,
        delegate bool(IRDstValue val)
        {
            return ctx.liveInfo.liveAfter(val, instr);
        }
    );
    */

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

    // TODO
    // If the value is not a reference, bailout to the interpreter
    //as.cmp(closType, Type.REFPTR);
    //as.jne(BAILOUT);

    // Get the word for the closure value
    auto closReg = st.getWordOpnd(
        as,
        instr, 
        0,
        64,
        scrRegs[0].opnd(64),
        true,
        false
    );
    assert (closReg.isGPR);

    // TODO
    // If the object is not a closure, bailout
    //as.mov(scrRegs32[1], new X86Mem(32, closReg, obj_ofs_header(null)));
    //as.cmp(scrRegs32[1], LAYOUT_CLOS);
    //as.jne(BAILOUT);

    // Get the IRFunction pointer from the closure object
    auto fptrMem = X86Opnd(64, closReg.reg, CLOS_OFS_FPTR);
    as.mov(scrRegs[1].opnd(64), fptrMem);

    //
    // Function call logic
    //

    auto numArgs = cast(uint32_t)instr.numArgs - 2;

    // Compute -extraArgs = numArgs - numArgs
    // This is the negation of the number of missing arguments
    // We use this as an offset when writing arguments to the stack
    as.getMember!("IRFunction.numParams")(scrReg3.reg(32), scrRegs[1]);
    as.mov(scrRegs[2].opnd(64), X86Opnd(numArgs));
    as.sub(scrRegs[2].opnd(64), scrReg3.opnd(64));
    as.cmp(scrRegs[2].opnd(64), X86Opnd(0));
    as.jle(Label.FALSE);
    as.xor(scrRegs[2].opnd(32), scrRegs[2].opnd(32));
    as.label(Label.FALSE);

    //writeln("numArgs=", numArgs);
    //as.printUint(scrRegs[2].opnd(64));

    // Initialize the missing arguments, if any
    as.mov(scrReg3.opnd(64), scrRegs[2].opnd(64));
    as.cmp(scrReg3.opnd(64), X86Opnd(0));
    as.jge(Label.LOOP_EXIT);
    as.mov(X86Opnd(64, wspReg, 0, 8, scrReg3), X86Opnd(UNDEF.int8Val));
    as.mov(X86Opnd(8, tspReg, 0, 1, scrReg3), X86Opnd(Type.CONST));
    as.add(scrReg3.opnd(64), X86Opnd(1));
    as.label(Label.LOOP_EXIT);



    //as.printUint(scrRegs[2].opnd(64));






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
    movArgType(as, numArgs + 0, X86Opnd(Type.INT32));

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
    assert (thisReg.isGPR);
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
    movArgType(as, numArgs + 2, X86Opnd(Type.REFPTR));

    // Request a branch object for the continuation
    auto contBranch = getBranchEdge(
        as,
        instr.getTarget(0),
        st,
        false
    );

    // TODO: exception branch, if any

    // Jump to the target block directly
    ver.genBranch(
        as,
        instr,
        contBranch,
        null,
        BranchShape.DEFAULT,
        function void(
            CodeBlock as,
            FragmentRef[]* refList,
            IRInstr instr,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            auto scrReg3 = allocRegs[$-1];
    
            auto numArgs = cast(uint32_t)instr.numArgs - 2;

            // Write the return address on the stack
            as.writeASM("mov", scrRegs[0], target0.getName);
            as.mov(scrRegs[0].opnd(64), X86Opnd(uint64_t.max));
            *refList ~= FragmentRef(as.getWritePos() - 8, target0, 64);
            as.mov(X86Opnd(64, wspReg, -8 * (numArgs + 4), 8, scrRegs[2]), scrRegs[0].opnd(64));
            as.mov(X86Opnd(8 , tspReg, -1 * (numArgs + 4), 1, scrRegs[2]), X86Opnd(Type.INSPTR));

            //as.printUint(scrRegs[0].opnd(64));

            // Compute the total number of locals and extra arguments
            as.getMember!("IRFunction.numLocals")(scrRegs[0].reg(32), scrRegs[1]);
            as.getMember!("IRFunction.numParams")(scrReg3.reg(32), scrRegs[1]);
            as.mov(scrRegs[2].opnd(32), X86Opnd(numArgs));
            as.sub(scrRegs[2].opnd(32), scrReg3.opnd(32));
            as.cmp(scrRegs[2].opnd(32), X86Opnd(0));
            as.jle(Label.FALSE2);
            as.add(scrRegs[0].opnd(32), scrRegs[2].opnd(32));
            as.label(Label.FALSE2);

            // Adjust the type stack pointer
            as.sub(X86Opnd(tspReg), scrRegs[0].opnd(64));

            //as.printUint(scrRegs[0].opnd(64));

            // Adjust the word stack pointer
            as.shl(scrRegs[0].opnd(64), X86Opnd(3));
            as.sub(X86Opnd(wspReg), scrRegs[0].opnd(64));

            // Jump to the function entry block
            as.getMember!("IRFunction.entryCode")(scrRegs[0], scrRegs[1]);
            as.jmp(scrRegs[0].opnd(64));
        }
    );

    //writeln("call block length: ", ver.length);

    // Add the return value move code to the continuation branch
    contBranch.markStart(as);
    as.setWord(instr.outSlot, retWordReg.opnd(64));
    as.setType(instr.outSlot, retTypeReg.opnd(8));

    // Generate the continuation branch edge code
    contBranch.genCode(as, st);

    // TODO: if not closure, call function to throw an exception
    // need to spill values before jumping to this
}

void gen_call_prim(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto interp = st.ctx.interp;

    // Function name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Get the primitve function from the global object
    auto globalMap = cast(ObjMap)obj_get_map(interp.globalObj);
    assert (globalMap !is null);
    auto propIdx = globalMap.getPropIdx(nameStr, true);
    assert (propIdx !is uint32_t.max);
    assert (propIdx < obj_get_cap(interp.globalObj));
    auto closPtr = cast(refptr)obj_get_word(interp.globalObj, propIdx);
    assert (valIsLayout(Word.ptrv(closPtr), LAYOUT_CLOS));
    auto fun = getClosFun(closPtr);

    // Check that the argument count matches
    auto numArgs = cast(int32_t)instr.numArgs - 2;
    assert (numArgs is fun.numParams);

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
    {
        //writeln("compiling");
        //writeln(core.memory.GC.addrOf(cast(void*)fun.ast));
        astToIR(fun.ast, fun);
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
    as.setType(-numArgs - 1, Type.INT32);

    // Set the "this" argument to null
    as.setWord(-numArgs - 2, NULL.int32Val);
    as.setType(-numArgs - 2, Type.REFPTR);

    // Set the closure argument to null
    as.setWord(-numArgs - 3, NULL.int32Val);
    as.setType(-numArgs - 3, Type.REFPTR);

    // TODO
    /*
    // Spill the values that are live after the call
    st.spillRegs(
        ctx.as,
        delegate bool(IRDstValue val)
        {
            return ctx.liveInfo.liveAfter(val, instr);
        }
    );
    */

    // Push space for the callee arguments and locals
    as.sub(X86Opnd(tspReg), X86Opnd(fun.numLocals));
    as.sub(X86Opnd(wspReg), X86Opnd(8 * fun.numLocals));

    // Request an instance for the function entry block
    auto entryVer = getBlockVersion(
        fun.entryBlock, 
        new CodeGenState(fun.getCtx(false, interp)),
        true
    );

    // Request a branch object for the continuation
    auto contBranch = getBranchEdge(
        as,
        instr.getTarget(0),
        st,
        false
    );

    // TODO: exception branch, if any

    // Jump to the target block directly
    ver.genBranch(
        as,
        instr,
        contBranch,
        entryVer,
        BranchShape.DEFAULT,
        function void(
            CodeBlock as,
            FragmentRef[]* refList,
            IRInstr instr,
            CodeFragment target0,
            CodeFragment target1,
            BranchShape shape
        )
        {
            // Get the return address slot of the callee
            auto entryVer = cast(BlockVersion)target1;
            assert (entryVer !is null);
            auto raSlot = entryVer.block.fun.raVal.outSlot;
            assert (raSlot !is NULL_LOCAL);

            // Write the return address on the stack
            as.writeASM("mov", scrRegs[0], target0.getName);
            as.mov(scrRegs[0].opnd(64), X86Opnd(uint64_t.max));
            *refList ~= FragmentRef(as.getWritePos() - 8, target0, 64);
            as.setWord(raSlot, scrRegs[0].opnd(64));
            as.setType(raSlot, Type.INSPTR);

            // Jump to the function entry block
            jmp32Ref(as, refList, target1);
        }
    );

    // Add the return value move code to the continuation branch
    contBranch.markStart(as);
    as.setWord(instr.outSlot, retWordReg.opnd(64));
    as.setType(instr.outSlot, retTypeReg.opnd(8));

    // Generate the continuation branch edge code
    contBranch.genCode(as, st);
}

void gen_ret(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    auto raSlot    = instr.block.fun.raVal.outSlot;
    auto argcSlot  = instr.block.fun.argcVal.outSlot;
    auto numParams = instr.block.fun.numParams;
    auto numLocals = instr.block.fun.numLocals;

    // If this is a unit-level function
    if (instr.block.fun.isUnit)
    {
        // Pop the locals, but leave one slot for the return value
        auto numPop = numLocals - 1;

        // Copy the return value word
        auto retOpnd = st.getWordOpnd(
            as, 
            instr, 
            0,
            64,
            scrRegs[0].opnd(64),
            true
        );

        as.mov(
            X86Opnd(64, wspReg, 8 * numPop),
            retOpnd
        );

        // Copy the return value type
        auto typeOpnd = st.getTypeOpnd(
            as, 
            instr,
            0, 
            scrRegs[0].opnd(8),
            true
        );
        as.mov(
            X86Opnd(8, tspReg, 1 * numPop),
            typeOpnd
        );

        // Pop local stack slots, but leave one slot for the return value
        as.add(tspReg, 1 * numPop);
        as.add(wspReg, 8 * numPop);

        // Store the stack pointers back in the interpreter
        as.setMember!("Interp.wsp")(interpReg, wspReg);
        as.setMember!("Interp.tsp")(interpReg, tspReg);

        // Restore the callee-save GP registers
        as.pop(R15);
        as.pop(R14);
        as.pop(R13);
        as.pop(R12);
        as.pop(RBP);
        as.pop(RBX);

        // Pop the stack alignment padding
        as.add(X86Opnd(RSP), X86Opnd(8));

        // Return to the interpreter
        as.ret();

        return;
    }

    //as.printStr("ret from " ~ instr.block.fun.getName);

    // TODO: support for return from new
    assert (st.ctx.ctorCall is false);

    // Get the actual argument count into r0
    as.getWord(scrRegs[0], argcSlot);

    // Compare the arg count against the expected count
    as.cmp(scrRegs[0].opnd(32), X86Opnd(numParams));

    // Compute the number of extra arguments into r0
    as.sub(scrRegs[0].opnd(32), X86Opnd(numParams));
    as.xor(scrRegs[1].opnd(32), scrRegs[1].opnd(32));
    as.cmovl(scrRegs[0], scrRegs[1].opnd(32));

    // Compute the number of stack slots to pop into r0
    as.add(scrRegs[0].opnd(32), X86Opnd(numLocals));

    // Copy the return value word
    auto retOpnd = st.getWordOpnd(
        as, 
        instr, 
        0,
        64,
        scrRegs[1].opnd(64),
        true,
        false
    );
    as.mov(retWordReg.opnd(64),retOpnd);

    // Copy the return value type
    auto typeOpnd = st.getTypeOpnd(
        as,
        instr, 
        0, 
        scrRegs[1].opnd(8),
        true
    );
    as.mov(retTypeReg.opnd(8), typeOpnd);

    // Get the return address into r1
    as.getWord(scrRegs[1], raSlot);

    // Pop all local stack slots and arguments
    as.add(tspReg.opnd(64), scrRegs[0].opnd(64));
    as.shl(scrRegs[0].opnd(64), X86Opnd(3));
    as.add(wspReg.opnd(64), scrRegs[0].opnd(64));

    //as.printUint(scrRegs[1].opnd(64));

    // Jump to the return address
    as.jmp(scrRegs[1].opnd(64));
}

void gen_make_map(
    VersionInst ver, 
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
        mapArg.map = new ObjMap(st.ctx.interp, numPropArg.int32Val);

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    auto outReg = outOpnd.isReg? outOpnd.reg:scrRegs[0];

    as.ptr(outReg, mapArg.map);
    if (!outOpnd.isReg)
        as.mov(outOpnd, X86Opnd(outReg));

    // Set the output type
    st.setOutType(as, instr, Type.MAPPTR);
}

void gen_new_clos(
    VersionInst ver, 
    CodeGenState st,
    IRInstr instr,
    CodeBlock as
)
{
    extern (C) static refptr newClosImpl(
        Interp interp, 
        IRFunction fun, 
        ObjMap closMap, 
        ObjMap protMap
    )
    {
        // If the function has no entry point code
        if (fun.entryCode is null)
        {
            // Store the entry code pointers
            fun.entryCode = getEntryStub(interp, false);
            fun.ctorCode = getEntryStub(interp, true);
        }

        // Allocate the closure object
        auto closPtr = GCRoot(
            interp,
            newClos(
                interp, 
                closMap,
                interp.funProto,
                cast(uint32)fun.ast.captVars.length,
                fun
            )
        );

        // Allocate the prototype object
        auto objPtr = GCRoot(
            interp,
            newObj(
                interp, 
                protMap,
                interp.objProto
            )
        );

        // Set the "prototype" property on the closure object
        auto protoStr = GCRoot(interp, getString(interp, "prototype"));
        setProp(
            interp,
            closPtr.ptr,
            protoStr.ptr,
            objPtr.pair
        );

        assert (
            clos_get_next(closPtr.ptr) == null,
            "closure next pointer is not null"
        );

        //writeln("final clos ptr: ", closPtr.ptr);

        return closPtr.ptr;
    }

    // TODO: make sure regs are properly spilled, this may trigger GC
    // c arg regs may also overlap allocated regs, args should be on stack

    auto funArg = cast(IRFunPtr)instr.getArg(0);
    assert (funArg !is null);

    auto closMapOpnd = st.getWordOpnd(as, instr, 1, 64, X86Opnd.NONE, false, false);
    auto protMapOpnd = st.getWordOpnd(as, instr, 2, 64, X86Opnd.NONE, false, false);

    as.ptr(cargRegs[0], st.ctx.interp);
    as.ptr(cargRegs[1], funArg.fun);
    as.mov(cargRegs[2].opnd(64), closMapOpnd);
    as.mov(cargRegs[3].opnd(64), protMapOpnd);
    as.ptr(RAX, &newClosImpl);
    as.call(RAX);

    auto outOpnd = st.getOutOpnd(as, instr, 64);
    as.mov(outOpnd, X86Opnd(RAX));

    st.setOutType(as, instr, Type.REFPTR);
}

void gen_print_str(
    VersionInst ver, 
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

