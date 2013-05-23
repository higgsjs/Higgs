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
import options;
import ir.ir;
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
import jit.jit;
import util.bitset;

void gen_set_true(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, TRUE.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_false(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, FALSE.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_undef(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{  
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, UNDEF.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_missing(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, MISSING.int8Val);
    st.setOutType(ctx.as, instr, Type.CONST);
}

void gen_set_null(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, NULL.int8Val);
    st.setOutType(ctx.as, instr, Type.REFPTR);
}

void gen_set_i32(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 32);
    ctx.as.instr(MOV, outOpnd, instr.args[0].int32Val);
    st.setOutType(ctx.as, instr, Type.INT32);
}

void gen_set_str(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto linkIdx = instr.args[1].linkIdx;

    assert (
        linkIdx !is NULL_LINK,
        "link not allocated for set_str"
    );

    ctx.as.getMember!("Interp", "wLinkTable")(scrRegs64[0], interpReg);
    ctx.as.instr(MOV, scrRegs64[0], new X86Mem(64, scrRegs64[0], 8 * linkIdx));

    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, scrRegs64[0]);
    st.setOutType(ctx.as, instr, Type.REFPTR);
}

void gen_move(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, 64);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    // Copy the value
    ctx.as.instr(MOV, opndOut, opnd0);

    // Copy the type tag
    auto argSlot = instr.args[0].localIdx;
    if (st.typeKnown(argSlot))
    {
        auto type = st.getType(argSlot);
        st.setOutType(ctx.as, instr, type);
    }
    else
    {
        ctx.as.getType(scrRegs8[0], argSlot);
        st.setOutType(ctx.as, instr, scrRegs8[0]);
    }
}

void IsTypeOp(Type type)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Get the type value
    auto typeOpnd = st.getTypeOpnd(ctx.as, instr.args[0].localIdx, scrRegs8[0]);

    // Compare against the tested type
    ctx.as.instr(CMP, scrRegs8[0], type);

    ctx.as.instr(MOV, scrRegs64[0], FALSE.int64Val);
    ctx.as.instr(MOV, scrRegs64[1], TRUE.int64Val);
    ctx.as.instr(CMOVE, scrRegs64[0], scrRegs64[1]);

    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, outOpnd, scrRegs64[0]);

    st.setOutType(ctx.as, instr, Type.CONST);
}

alias IsTypeOp!(Type.CONST) gen_is_const;
alias IsTypeOp!(Type.REFPTR) gen_is_refptr;
alias IsTypeOp!(Type.INT32) gen_is_i32;
alias IsTypeOp!(Type.FLOAT64) gen_is_f64;

/*
void gen_i32_to_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.instr(CVTSI2SD, XMM0, new X86Mem(32, wspReg, instr.args[0].localIdx * 8));

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT64);
}

void gen_f64_to_i32(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Cast to int64 and truncate to int32 (to match JS semantics)
    ctx.as.instr(CVTSD2SI, RAX, new X86Mem(64, wspReg, instr.args[0].localIdx * 8));
    ctx.as.instr(MOV, ECX, EAX);

    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}
*/

void RMMOp(string op, size_t numBits, Type typeTag)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // The register allocator should ensure that at
    // least one input is a register operand
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, numBits);
    auto opnd1 = st.getArgOpnd(ctx, ctx.as, instr, 1, numBits);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, numBits);

    X86OpPtr opPtr = null;
    static if (op == "add")
        opPtr = ADD;
    static if (op == "sub")
        opPtr = SUB;
    static if (op == "imul")
        opPtr = IMUL;
    static if (op == "and")
        opPtr = AND;
    assert (opPtr !is null);

    if (opnd0 == opndOut)
    {
        ctx.as.instr(opPtr, opndOut, opnd1);
    }

    else if (opnd1 == opndOut)
    {
        ctx.as.instr(opPtr, opndOut, opnd0);
    }

    else if (opPtr == IMUL && cast(X86Mem)opndOut)
    {
        // IMUL does not support memory operands as output
        auto scrReg0 = new X86Reg(X86Reg.GP, scrRegs64[0].regNo, numBits);
        ctx.as.instr(MOV, scrReg0, opnd0);
        ctx.as.instr(opPtr, scrReg0, opnd1);
        ctx.as.instr(MOV, opndOut, scrReg0);
    }

    else
    {
        // Neither input operand is the output
        ctx.as.instr(MOV, opndOut, opnd0);
        ctx.as.instr(opPtr, opndOut, opnd1);
    }

    st.setOutType(ctx.as, instr, typeTag);
}

alias RMMOp!("add" , 32, Type.INT32) gen_add_i32;
alias RMMOp!("imul", 32, Type.INT32) gen_mul_i32;
alias RMMOp!("and" , 32, Type.INT32) gen_and_i32;

/*
void gen_add_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(ADDSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT64);
}

void gen_sub_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(SUBSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT64);
}

void gen_mul_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(MULSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT64);
}

void gen_div_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(DIVSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT64);
}
*/

/*
void OvfOp(string op)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto OVF = new Label("OVF");

    ctx.as.getWord(ECX, instr.args[0].localIdx);
    ctx.as.getWord(EDX, instr.args[1].localIdx);

    static if (op == "add")
        ctx.as.instr(ADD, ECX, EDX);
    static if (op == "sub")
        ctx.as.instr(SUB, ECX, EDX);
    static if (op == "mul")
        ctx.as.instr(IMUL, ECX, EDX);

    ctx.as.instr(JO, OVF);

    // Set the output
    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.INT32);

    // If the target block isn't in the block list, jump to it
    if (!ctx.hasNextNode || ctx.nextBlock != instr.target)
        ctx.as.jump(ctx, instr.target);

    // *** The trace will continue at the target block ***

    // Out of line jump to the overflow target
    ctx.ol.addInstr(OVF);
    ctx.ol.jump(ctx, instr.excTarget);
}

alias OvfOp!("add") gen_add_i32_ovf;
alias OvfOp!("sub") gen_sub_i32_ovf;
alias OvfOp!("mul") gen_mul_i32_ovf;
*/

void CmpOp(string op, size_t numBits)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, numBits);
    auto opnd1 = st.getArgOpnd(ctx, ctx.as, instr, 1, numBits);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 32);

    // Compare the inputs
    ctx.as.instr(CMP, opnd0, opnd1);

    ctx.as.instr(MOV, scrRegs16[0], FALSE.int8Val);
    ctx.as.instr(MOV, scrRegs16[1], TRUE.int8Val);

    X86OpPtr cmovOp = null;
    static if (op == "eq")
        cmovOp = CMOVE;
    static if (op == "ne")
        cmovOp = CMOVNE;
    static if (op == "lt")
        cmovOp = CMOVL;
    static if (op == "le")
        cmovOp = CMOVLE;
    static if (op == "gt")
        cmovOp = CMOVG;
    static if (op == "ge")
        cmovOp = CMOVGE;

    ctx.as.instr(cmovOp, scrRegs32[0], scrRegs32[1]);

    ctx.as.instr(MOV, opndOut, scrRegs32[0]);

    st.setOutType(ctx.as, instr, Type.CONST);
}

alias CmpOp!("eq", 8) gen_eq_i8;
alias CmpOp!("lt", 32) gen_lt_i32;
//alias CmpOp!("i32", "ge") gen_ge_i32;
//alias CmpOp!("i32", "ne") gen_ne_i32;
alias CmpOp!("eq", 8) gen_eq_const;
//alias CmpOp!("i64", "eq") gen_eq_refptr;
//alias CmpOp!("i64", "ne") gen_ne_refptr;

void LoadOp(size_t memSize, Type typeTag)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getArgOpnd(ctx, ctx.as, instr, 0, 64);
    auto opnd1 = st.getArgOpnd(ctx, ctx.as, instr, 1, 32);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    X86Reg opnd0Reg = cast(X86Reg)opnd0;

    // Zero extend the offset input into a scratch register
    X86Reg opnd1Reg = scrRegs64[0];
    ctx.as.instr(MOV, scrRegs32[0], opnd1);

    assert (
        opnd0Reg && opnd1Reg, 
        "both inputs must be in registers"
    );

    X86OpPtr loadOp;
    static if (memSize == 8 || memSize == 16)
        loadOp = MOVZX;
    else
        loadOp = MOV;

    // If the output operand is a memory location
    if (cast(X86Mem)opndOut || memSize == 32)    
    {
        uint16_t scrSize = (memSize == 32)? 32:64;
        auto scrReg64 = scrRegs64[1];
        auto scrReg = new X86Reg(X86Reg.GP, scrReg64.regNo, scrSize);
        auto memOpnd = new X86Mem(memSize, opnd0Reg, 0, opnd1Reg);

        // Load to a scratch register and then move to the output
        ctx.as.instr(loadOp, scrReg, memOpnd);
        ctx.as.instr(MOV, opndOut, scrReg64);
    }
    else
    {
        // Load to the output register directly
        ctx.as.instr(loadOp, opndOut, new X86Mem(memSize, opnd0Reg, 0, opnd1Reg));
    }

    // Set the output type tag
    st.setOutType(ctx.as, instr, typeTag);
}

alias LoadOp!(8 , Type.INT32) gen_load_u8;
//alias LoadOp!(uint16, Type.INT32) gen_load_u16;
alias LoadOp!(32, Type.INT32) gen_load_u32;
alias LoadOp!(64, Type.INT64) gen_load_u64;
//alias LoadOp!(64, Type.FLOAT64) gen_load_f64;
alias LoadOp!(64, Type.REFPTR) gen_load_refptr;
//alias LoadOp!(rawptr, Type.RAWPTR) gen_load_rawptr;
//alias LoadOp!(IRFunction, Type.FUNPTR) gen_load_funptr;

void gen_jump(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Jump to the target block
    auto blockLabel = ctx.getBlockLabel(instr.target, st);
    ctx.as.instr(JMP, blockLabel);
}

void gen_if_true(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Compare the argument to the true value
    auto argOpnd = st.getArgOpnd(ctx, ctx.as, instr, 0, 8);
    ctx.as.instr(CMP, argOpnd, TRUE.int8Val);

    X86OpPtr jumpOp;
    IRBlock fTarget;
    IRBlock sTarget;

    if (instr.target.execCount > instr.excTarget.execCount)
    {
        fTarget = instr.target;
        sTarget = instr.excTarget;
        jumpOp = JNE;
    }
    else
    {
        fTarget = instr.excTarget;
        sTarget = instr.target;
        jumpOp = JE;
    }

    // Get the fast target label last so the fast target is
    // more likely to get generated first (LIFO stack)
    auto sLabel = ctx.getBlockLabel(sTarget, st);
    auto fLabel = ctx.getBlockLabel(fTarget, st);

    ctx.as.instr(jumpOp, sLabel);
    ctx.as.instr(JMP, fLabel);
}

void gen_get_global(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[1].int32Val;

    // If no property index is cached, use the interpreter function
    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    // Allocate the output operand
    auto outOpnd = st.getOutOpnd(ctx, ctx.as, instr, 64);

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(scrRegs64[0], interpReg);

    // Get the global object size/capacity
    ctx.as.getField(scrRegs32[1], scrRegs64[0], 4, obj_ofs_cap(interp.globalObj));

    // Get the offset of the start of the word array
    auto wordOfs = obj_ofs_word(interp.globalObj, 0);

    // Get the word value from the object
    auto wordMem = new X86Mem(64, scrRegs64[0], wordOfs + 8 * propIdx);
    if (cast(X86Reg)outOpnd)
    {
        ctx.as.instr(MOV, outOpnd, wordMem);
    }
    else
    {
        ctx.as.instr(MOV, scrRegs64[2], wordMem);
        ctx.as.instr(MOV, outOpnd, scrRegs64[2]);
    }

    // Get the type value from the object
    auto typeMem = new X86Mem(8, scrRegs64[0], wordOfs + propIdx, scrRegs64[1], 8);
    ctx.as.instr(MOV, scrRegs8[2], typeMem);

    // Set the type value
    st.setOutType(ctx.as, instr, scrRegs8[2]);
}

void gen_set_global(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[2].int32Val;

    // If no property index is cached, used the interpreter function
    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    // Allocate the input operand
    auto argOpnd = st.getArgOpnd(ctx, ctx.as, instr, 1, 64);

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(scrRegs64[0], interpReg);

    // Get the global object size/capacity
    ctx.as.getField(scrRegs32[1], scrRegs64[0], 4, obj_ofs_cap(interp.globalObj));

    // Get the offset of the start of the word array
    auto wordOfs = obj_ofs_word(interp.globalObj, 0);

    // Set the word value
    auto wordMem = new X86Mem(64, scrRegs64[0], wordOfs + 8 * propIdx);
    if (cast(X86Reg)argOpnd)
    {
        ctx.as.instr(MOV, wordMem, argOpnd);
    }
    else
    {
        ctx.as.instr(MOV, scrRegs64[2], argOpnd);
        ctx.as.instr(MOV, wordMem, scrRegs64[2]);
    }

    // Set the type value
    auto typeOpnd = st.getTypeOpnd(ctx.as, instr.args[1].localIdx, scrRegs8[2]);
    auto typeMem = new X86Mem(8, scrRegs64[0], wordOfs + propIdx, scrRegs64[1], 8);
    ctx.as.instr(MOV, typeMem, typeOpnd);
}

void gen_call(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;
    auto numArgs = instr.args.length - 2;

    // Generate an entry point for the call continuation
    ctx.getEntryPoint(instr.target);

    // Find the most called callee function
    uint64_t maxCount = 0;
    IRFunction maxCallee = null;
    foreach (callee, count; ctx.fun.callCounts[instr])
    {
        if (count > maxCount)
        {
            maxCallee = callee;
            maxCount = count;
        }
    }

    // Get the callee function
    auto fun = maxCallee;
    assert (fun.entryBlock !is null);

    // If the argument count doesn't match
    if (numArgs != fun.numParams)
    {
        // Call the interpreter call instruction
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    // Get the closure and this registers before spilling
    X86Reg closReg = st.getReg(closIdx);
    X86Reg thisReg = st.getReg(thisIdx);

    // Get the argument registers before spilling
    X86Reg[] argRegs;
    argRegs.length = numArgs;
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto argSlot = instr.args[$-(1+i)].localIdx;
        argRegs[i] = st.getReg(argSlot);
    }

    // Spill the values that are live after the call
    st.spillRegs(
        ctx.as,
        delegate bool(size_t regNo, LocalIdx localIdx)
        {
            return (ctx.liveSets[instr].has(localIdx) == true);
        }
    );

    // Label for the bailout to interpreter cases
    auto BAILOUT = new Label("CALL_BAILOUT");

    //
    // Function pointer extraction
    //

    // Get the closure word off the stack if necessary
    if (closReg is null)
    {
        closReg = scrRegs64[0];
        ctx.as.getWord(closReg, closIdx);
    }

    // Get the function pointer from the closure object
    auto fptrMem = new X86Mem(64, closReg, CLOS_OFS_FPTR);
    ctx.as.instr(MOV, scrRegs64[2], fptrMem);

    //
    // Function call logic
    //

    // If this is not the closure we expect, bailout to the interpreter
    ctx.as.ptr(scrRegs64[3], fun);
    ctx.as.instr(CMP, scrRegs64[2], scrRegs64[3]);
    ctx.as.instr(JNE, BAILOUT);

    auto numPush = fun.numLocals;
    auto numVars = fun.numLocals - NUM_HIDDEN_ARGS - fun.numParams;

    //writefln("numPush: %s, numVars: %s", numPush, numVars);

    // Push space for the callee arguments and locals
    ctx.as.instr(SUB, wspReg, 8 * numPush);
    ctx.as.instr(SUB, tspReg, numPush);

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        //auto argSlot = instr.args[$-(1+i)].localIdx + (argDiff + i);
        auto argSlot = instr.args[$-(1+i)].localIdx;
        auto dstIdx = (numArgs - i - 1) + numVars + NUM_HIDDEN_ARGS;

        // If this argument is in a register
        if (argRegs[i] !is null)
        {
            //writefln("arg reg: %s %s", argRegs[i], i);
            ctx.as.setWord(cast(LocalIdx)dstIdx, argRegs[i]);
        }
        else
        {
            ctx.as.getWord(scrRegs64[3], argSlot + numPush); 
            ctx.as.setWord(cast(LocalIdx)dstIdx, scrRegs64[3]);
        }

        // Set the argument type
        auto typeOpnd = st.getTypeOpnd(ctx.as, argSlot, scrRegs8[3], numPush);
        ctx.as.setType(cast(LocalIdx)dstIdx, typeOpnd);
    }

    // Write the argument count
    ctx.as.setWord(cast(LocalIdx)(numVars + 3), cast(int32_t)numArgs);
    ctx.as.setType(cast(LocalIdx)(numVars + 3), Type.INT32);

    // If the callee uses its "this" argument, write it on the stack
    if (fun.ast.usesThis == true)
    {
        if (thisReg)
        {
            ctx.as.setWord(cast(LocalIdx)(numVars + 2), thisReg);
        }
        else
        {
            ctx.as.getWord(scrRegs64[2], thisIdx + numPush);
            ctx.as.setWord(cast(LocalIdx)(numVars + 2), scrRegs64[2]);
        }
        auto typeOpnd = st.getTypeOpnd(ctx.as, thisIdx, scrRegs8[3], numPush);
        ctx.as.setType(cast(LocalIdx)(numVars + 2), typeOpnd);
    }

    // If the callee uses its closure argument, write it on the stack
    if (fun.ast.usesClos == true)
    {
        ctx.as.setWord(cast(LocalIdx)(numVars + 1), closReg);
        ctx.as.setType(cast(LocalIdx)(numVars + 1), Type.REFPTR);
    }

    // Write the return address (caller instruction)
    ctx.as.ptr(scrRegs64[3], instr);
    ctx.as.setWord(cast(LocalIdx)(numVars + 0), scrRegs64[3]);
    ctx.as.setType(cast(LocalIdx)(numVars + 0), Type.INSPTR);

    // Jump to the callee entry point
    ctx.as.jump(ctx, st, fun.entryBlock);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(BAILOUT);

    // Fallback to interpreter execution
    // Spill all values, including arguments
    // Call the interpreter call instruction
    defaultFn(ctx.ol, ctx, st, instr);
}

void gen_ret(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.block.fun.raSlot;
    auto argcSlot  = instr.block.fun.argcSlot;
    auto thisSlot  = instr.block.fun.thisSlot;
    auto numParams = instr.block.fun.params.length;
    auto numLocals = instr.block.fun.numLocals;

    // Label for the bailout to interpreter cases
    auto BAILOUT = new Label("RET_BAILOUT");

    // Label for the point at which we pop the locals
    auto POP_LOCALS = new Label("POP_LOCALS");
    
    // Get the argument count
    // If it doesn't match the expected count, bailout
    ctx.as.getWord(scrRegs64[0], argcSlot);
    ctx.as.instr(CMP, scrRegs64[0], numParams);
    ctx.as.instr(JNE, BAILOUT);

    // Get the call instruction
    ctx.as.getWord(scrRegs64[0], raSlot);
    
    // If this is not a regular call, bailout
    ctx.as.getMember!("IRInstr", "opcode")(scrRegs64[1], scrRegs64[0]);
    ctx.as.ptr(scrRegs64[2], &ir.ir.CALL);
    ctx.as.instr(CMP, scrRegs64[1], scrRegs64[2]);
    ctx.as.instr(JNE, BAILOUT);

    // Get the output slot for the call instruction
    ctx.as.getMember!("IRInstr", "outSlot")(scrRegs32[1], scrRegs64[0]);
    ctx.as.instr(CMP, scrRegs32[1], NULL_LOCAL);
    ctx.as.instr(JE, POP_LOCALS);

    // Copy the return value word and type
    auto retReg = st.getReg(retSlot);
    if (retReg is null)
    {
        ctx.as.instr(MOV, scrRegs64[2], new X86Mem(64, wspReg, 8 * retSlot));
        retReg = scrRegs64[2];
    }
    ctx.as.instr(MOV, new X86Mem(64, wspReg, 8 * numLocals, scrRegs64[1], 8), retReg);
    auto typeOpnd = st.getTypeOpnd(ctx.as, retSlot, scrRegs8[2]);
    ctx.as.instr(MOV, new X86Mem(8, tspReg, numLocals, scrRegs64[1]), typeOpnd);

    // Pop all local stack slots and arguments
    ctx.as.addInstr(POP_LOCALS);
    ctx.as.instr(ADD, wspReg, numLocals * 8);
    ctx.as.instr(ADD, tspReg, numLocals);

    // Get the call continuation block
    ctx.as.getMember!("IRInstr", "target")(scrRegs64[0], scrRegs64[0]);

    // Jump to the call continuation block without spilling anything
    ctx.as.jump(ctx, new CodeGenState(ctx.fun), scrRegs64[0]);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(BAILOUT);

    // Fallback to interpreter execution
    // Spill all values, including arguments
    // Call the interpreter call instruction
    defaultFn(ctx.ol, ctx, st, instr);
}

void gen_get_global_obj(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Get the output operand. This must be a 
    // register since it's the only operand.
    auto opndOut = cast(X86Reg)st.getOutOpnd(ctx, ctx.as, instr, 64);
    assert (opndOut !is null, "output is not a register");

    ctx.as.getMember!("Interp", "globalObj")(opndOut, interpReg);

    st.setOutType(ctx.as, instr, Type.REFPTR);
}

void defaultFn(Assembler as, CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Get the function corresponding to this instruction
    // alias void function(Interp interp, IRInstr instr) OpFn;
    // RDI: first argument (interp)
    // RSI: second argument (instr)
    auto opFn = instr.opcode.opFn;

    // Spill all live values and instruction arguments
    auto liveSet = ctx.liveSets[instr];
    st.spillRegs(
        as,
        delegate bool(size_t regNo, LocalIdx localIdx)
        {
            if (instr.hasArg(localIdx))
                return true;

            if (liveSet.has(localIdx))
                return true;

            return false;
        }
    );

    // Move the interpreter pointer into the first argument
    as.instr(MOV, cargRegs[0], interpReg);
    
    // Load a pointer to the instruction in the second argument
    as.ptr(cargRegs[1], instr);

    // Set the interpreter's IP
    // Only necessary if we may branch or allocate
    if (instr.opcode.isBranch || instr.opcode.mayGC)
    {
        as.setMember!("Interp", "ip")(interpReg, cargRegs[1]);
    }

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(interpReg, wspReg);
    as.setMember!("Interp", "tsp")(interpReg, tspReg);

    // Call the op function
    as.ptr(scrRegs64[0], opFn);
    as.instr(jit.encodings.CALL, scrRegs64[0]);

    // If this is a branch instruction
    if (instr.opcode.isBranch == true)
    {
        // Reload the stack pointers, the instruction may have changed them
        as.getMember!("Interp", "wsp")(wspReg, interpReg);
        as.getMember!("Interp", "tsp")(tspReg, interpReg);

        // Bailout to the interpreter
        as.instr(JMP, ctx.bailLabel);

        if (opts.jit_dumpinfo)
            writefln("interpreter bailout");
    }

    // If the instruction has an output slot, mark its
    // output as being on the stack
    if (instr.outSlot !is NULL_LOCAL)
    {
        st.valOnStack(instr.outSlot);
    }
}

alias void function(CodeGenCtx ctx, CodeGenState st, IRInstr instr) CodeGenFn;

CodeGenFn[Opcode*] codeGenFns;

static this()
{
    codeGenFns[&SET_TRUE]       = &gen_set_true;
    codeGenFns[&SET_FALSE]      = &gen_set_false;
    codeGenFns[&SET_UNDEF]      = &gen_set_undef;
    codeGenFns[&SET_MISSING]    = &gen_set_missing;
    codeGenFns[&SET_NULL]       = &gen_set_null;
    codeGenFns[&SET_I32]        = &gen_set_i32;
    codeGenFns[&SET_STR]        = &gen_set_str;

    codeGenFns[&MOVE]           = &gen_move;

    codeGenFns[&IS_CONST]       = &gen_is_const;
    codeGenFns[&IS_REFPTR]      = &gen_is_refptr;
    codeGenFns[&IS_I32]         = &gen_is_i32;
    codeGenFns[&IS_F64]         = &gen_is_f64;

    /*
    codeGenFns[&I32_TO_F64]     = &gen_i32_to_f64;
    codeGenFns[&F64_TO_I32]     = &gen_f64_to_i32;
    */

    codeGenFns[&ADD_I32]        = &gen_add_i32;
    codeGenFns[&MUL_I32]        = &gen_mul_i32;
    codeGenFns[&AND_I32]        = &gen_and_i32;

    /*
    codeGenFns[&ADD_F64]        = &gen_add_f64;
    codeGenFns[&SUB_F64]        = &gen_sub_f64;
    codeGenFns[&MUL_F64]        = &gen_mul_f64;
    codeGenFns[&DIV_F64]        = &gen_div_f64;

    codeGenFns[&ADD_I32_OVF]    = &gen_add_i32_ovf;
    codeGenFns[&SUB_I32_OVF]    = &gen_sub_i32_ovf;
    codeGenFns[&MUL_I32_OVF]    = &gen_mul_i32_ovf;
    */

    codeGenFns[&EQ_I8]          = &gen_eq_i8;
    codeGenFns[&LT_I32]         = &gen_lt_i32;
    //codeGenFns[&GE_I32]         = &gen_ge_i32;
    //codeGenFns[&NE_I32]         = &gen_ne_i32;
    codeGenFns[&EQ_CONST]       = &gen_eq_const;
    //codeGenFns[&EQ_REFPTR]      = &gen_eq_refptr;
    //codeGenFns[&NE_REFPTR]      = &gen_ne_refptr;

    codeGenFns[&LOAD_U8]        = &gen_load_u8;
    codeGenFns[&LOAD_U32]       = &gen_load_u32;
    codeGenFns[&LOAD_U64]       = &gen_load_u64;
    //codeGenFns[&LOAD_F64]       = &gen_load_f64;
    codeGenFns[&LOAD_REFPTR]    = &gen_load_refptr;

    codeGenFns[&JUMP]           = &gen_jump;

    codeGenFns[&IF_TRUE]        = &gen_if_true;

    codeGenFns[&ir.ir.CALL]     = &gen_call;
    codeGenFns[&ir.ir.RET]      = &gen_ret;

    codeGenFns[&GET_GLOBAL]     = &gen_get_global;
    codeGenFns[&SET_GLOBAL]     = &gen_set_global;

    codeGenFns[&GET_GLOBAL_OBJ] = &gen_get_global_obj;
}

