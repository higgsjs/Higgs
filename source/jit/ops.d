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

void gen_get_arg(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Get the first argument slot
    auto argSlot = instr.block.fun.argcVal.outSlot + 1;

    // Get the argument index
    auto idxOpnd = st.getWordOpnd(ctx, ctx.as, instr, 0, 64, scrRegs64[0], false);

    // Get the output operand
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    // TODO: optimize for immediate idx, register opndOut
    // Copy the word value
    auto wordSlot = new X86Mem(64, wspReg, argSlot * 8, cast(X86Reg)idxOpnd, 8);
    ctx.as.instr(MOV, scrRegs64[1], wordSlot);
    ctx.as.instr(MOV, opndOut, scrRegs64[1]);

    // Copy the type value
    auto typeSlot = new X86Mem(8, tspReg, argSlot * 1, cast(X86Reg)idxOpnd, 1);
    ctx.as.instr(MOV, scrRegs8[1], typeSlot);
    st.setOutType(ctx.as, instr, scrRegs8[1]);
}

void gen_set_str(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto linkVal = cast(IRLinkIdx)instr.getArg(1);
    assert (linkVal !is null);
    auto linkIdx = linkVal.linkIdx;

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

void gen_make_value(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Move the word value into the output word
    auto wordOpnd = st.getWordOpnd(ctx, ctx.as, instr, 0, 64, scrRegs64[0], true);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);
    ctx.as.instr(MOV, opndOut, wordOpnd);

    // Get the type value from the second operand
    auto typeOpnd = st.getWordOpnd(ctx, ctx.as, instr, 1, 8, scrRegs8[0]);
    st.setOutType(ctx.as, instr, cast(X86Reg)typeOpnd);
}

void gen_get_word(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto wordOpnd = st.getWordOpnd(ctx, ctx.as, instr, 0, 64, scrRegs64[0], true);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    ctx.as.instr(MOV, opndOut, wordOpnd);

    st.setOutType(ctx.as, instr, Type.INT64);
}

void gen_get_type(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto typeOpnd = st.getTypeOpnd(ctx.as, instr, 0, scrRegs8[0], true);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 32);

    if (cast(X86Imm)typeOpnd)
    {
        ctx.as.instr(MOV, opndOut, typeOpnd);
    }
    else if (cast(X86Reg)opndOut)
    {
        ctx.as.instr(MOVZX, opndOut, typeOpnd);
    }
    else
    {
        ctx.as.instr(MOVZX, scrRegs32[0], typeOpnd);
        ctx.as.instr(MOV, opndOut, scrRegs32[0]);
    }

    st.setOutType(ctx.as, instr, Type.INT32);
}

void gen_i32_to_f64(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = cast(X86Reg)st.getWordOpnd(ctx, ctx.as, instr, 0, 32, scrRegs32[0], false, false);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    // Sign-extend the 32-bit integer to 64-bit
    ctx.as.instr(MOVSXD, scrRegs64[1], opnd0);

    ctx.as.instr(CVTSI2SD, XMM0, opnd0);

    ctx.as.instr(MOVQ, opndOut, XMM0);
    st.setOutType(ctx.as, instr, Type.FLOAT64);
}

void gen_f64_to_i32(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opndReg = cast(X86Reg)st.getWordOpnd(ctx, ctx.as, instr, 0, 64, XMM0, false, false);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 32);

    if (opndReg.type !is X86Reg.XMM)
        ctx.as.instr(MOVQ, XMM0, opndReg);

    // Cast to int64 and truncate to int32 (to match JS semantics)
    ctx.as.instr(CVTSD2SI, scrRegs64[0], XMM0);
    ctx.as.instr(MOV, opndOut, scrRegs32[0]);

    st.setOutType(ctx.as, instr, Type.INT32);
}

void RMMOp(string op, size_t numBits, Type typeTag)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Should be mem or reg
    auto opnd0 = st.getWordOpnd(
        ctx, 
        ctx.as, 
        instr, 
        0, 
        numBits, 
        scrRegs64[0].ofSize(numBits),
        false
    );

    // May be reg or immediate
    auto opnd1 = st.getWordOpnd(
        ctx, 
        ctx.as, 
        instr, 
        1, 
        numBits,
        scrRegs64[1].ofSize(numBits),
        true
    );

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
    static if (op == "or")
        opPtr = OR;
    static if (op == "xor")
        opPtr = XOR;
    assert (opPtr !is null);

    if (opPtr == IMUL)
    {
        // IMUL does not support memory operands as output
        auto scrReg = scrRegs64[2].ofSize(numBits);
        ctx.as.instr(MOV, scrReg, opnd1);
        ctx.as.instr(opPtr, scrReg, opnd0);
        ctx.as.instr(MOV, opndOut, scrReg);
    }
    else
    {
        if (opnd0 == opndOut)
        {
            ctx.as.instr(opPtr, opndOut, opnd1);
        }
        else if (opnd1 == opndOut)
        {
            ctx.as.instr(opPtr, opndOut, opnd0);
        }
        else
        {
            // Neither input operand is the output
            ctx.as.instr(MOV, opndOut, opnd0);
            ctx.as.instr(opPtr, opndOut, opnd1);
        }
    }

    // If the instruction has an exception/overflow target
    if (instr.getTarget(0))
    {
        auto overLabel = new Label("ADD_OVER");
        auto contLabel = new Label("ADD_CONT");

        // On overflow, jump to the overflow target
        ctx.as.instr(JO, overLabel);

        // Set the output type
        st.setOutType(ctx.as, instr, typeTag);

        // Jump to the normal path
        ctx.as.instr(JMP, contLabel);

        // Get the fast target label last so the fast target is
        // more likely to get generated first (LIFO stack)
        ctx.genBranchEdge(ctx.ol, overLabel, instr.getTarget(1), st);
        ctx.genBranchEdge(ctx.as, contLabel, instr.getTarget(0), st);
    }
    else
    {
        // Set the output type
        st.setOutType(ctx.as, instr, typeTag);
    }
}

alias RMMOp!("add" , 32, Type.INT32) gen_add_i32;
alias RMMOp!("imul", 32, Type.INT32) gen_mul_i32;
alias RMMOp!("and" , 32, Type.INT32) gen_and_i32;
alias RMMOp!("or"  , 32, Type.INT32) gen_or_i32;
alias RMMOp!("xor" , 32, Type.INT32) gen_xor_i32;

alias RMMOp!("add" , 32, Type.INT32) gen_add_i32_ovf;
alias RMMOp!("sub" , 32, Type.INT32) gen_sub_i32_ovf;
alias RMMOp!("imul", 32, Type.INT32) gen_mul_i32_ovf;

void gen_mod_i32(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getWordOpnd(ctx, ctx.as, instr, 0, 32, null, true);
    auto opnd1 = st.getWordOpnd(ctx, ctx.as, instr, 1, 32, scrRegs32[2], false, true);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 32);

    // Save RDX
    ctx.as.instr(MOV, scrRegs64[1], RDX);
    if (opnd1 == EDX)
        opnd1 = scrRegs32[1];

    // Move the dividend into EAX
    ctx.as.instr(MOV, EAX, opnd0);

    // Sign-extend EAX into EDX:EAX
    ctx.as.instr(CDQ);

    // Signed divide/quotient EDX:EAX by r/m32
    ctx.as.instr(IDIV, opnd1);

    if (opndOut != EDX)
    {
        // Store the remainder into the output operand
        ctx.as.instr(MOV, opndOut, EDX);

        // Restore RDX
        ctx.as.instr(MOV, RDX, scrRegs64[1]);
    }

    // Set the output type
    st.setOutType(ctx.as, instr, Type.INT32);

    /*
    writeln();
    writeln(instr.block);
    writeln("opnd0: ", opnd0);
    writeln("opnd1: ", opnd1);
    writeln();
    ctx.as.printTail(10);
    */
}

void ShiftOp(string op)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto opnd0 = st.getWordOpnd(ctx, ctx.as, instr, 0, 32, null, true);
    auto opnd1 = st.getWordOpnd(ctx, ctx.as, instr, 1, 8, null, true);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 32);

    X86OpPtr opPtr = null;
    static if (op == "sal")
        opPtr = SAL;
    static if (op == "sar")
        opPtr = SAR;
    assert (opPtr !is null);

    // Save RCX
    ctx.as.instr(MOV, scrRegs64[1], RCX);

    ctx.as.instr(MOV, scrRegs32[0], opnd0);
    ctx.as.instr(MOV, CL, opnd1);

    ctx.as.instr(opPtr, scrRegs32[0], CL);

    // Restore RCX
    ctx.as.instr(MOV, RCX, scrRegs64[1]);

    ctx.as.instr(MOV, opndOut, scrRegs32[0]);

    // Set the output type
    st.setOutType(ctx.as, instr, Type.INT32);
}

alias ShiftOp!("sal") gen_lsft_i32;
alias ShiftOp!("sar") gen_rsft_i32;

void FPOp(string op)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    X86Reg opnd0 = cast(X86Reg)st.getWordOpnd(ctx, ctx.as, instr, 0, 64, XMM0);
    X86Reg opnd1 = cast(X86Reg)st.getWordOpnd(ctx, ctx.as, instr, 1, 64, XMM1);
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    assert (opnd0 && opnd1);

    if (opnd0.type == X86Reg.GP)
        ctx.as.instr(MOVQ, XMM0, opnd0);
    if (opnd1.type == X86Reg.GP)
        ctx.as.instr(MOVQ, XMM1, opnd1);

    X86OpPtr opPtr = null;
    static if (op == "add")
        opPtr = ADDSD;
    static if (op == "sub")
        opPtr = SUBSD;
    static if (op == "mul")
        opPtr = MULSD;
    static if (op == "div")
        opPtr = DIVSD;
    assert (opPtr !is null);

    ctx.as.instr(opPtr, XMM0, XMM1);

    ctx.as.instr(cast(X86Reg)opndOut? MOVQ:MOVSD, opndOut, XMM0);

    // Set the output type
    st.setOutType(ctx.as, instr, Type.FLOAT64);
}

alias FPOp!("add") gen_add_f64;
alias FPOp!("sub") gen_sub_f64;
alias FPOp!("mul") gen_mul_f64;
alias FPOp!("div") gen_div_f64;

void LoadOp(size_t memSize, Type typeTag)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // The pointer operand must be a register
    auto opnd0 = cast(X86Reg)st.getWordOpnd(ctx, ctx.as, instr, 0, 64, scrRegs64[0]);

    // The offset operand may be a register or an immediate
    auto opnd1 = st.getWordOpnd(ctx, ctx.as, instr, 1, 32, scrRegs32[1], true);

    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    // Create the memory operand
    X86Mem memOpnd;
    if (auto immOffs = cast(X86Imm)opnd1)
    {
        memOpnd = new X86Mem(memSize, opnd0, cast(int32_t)immOffs.imm);
    }
    else if (auto regOffs = cast(X86Reg)opnd1)
    {
        // Zero-extend the offset from 32 to 64 bits
        ctx.as.instr(MOV, regOffs, regOffs);
        memOpnd = new X86Mem(memSize, opnd0, 0, regOffs.ofSize(64));
    }
    else
    {
        assert (false, "invalid offset operand");
    }

    // Select which load opcode to use
    X86OpPtr loadOp;
    static if (memSize == 8 || memSize == 16)
        loadOp = MOVZX;
    else
        loadOp = MOV;

    // If the output operand is a memory location
    if (cast(X86Mem)opndOut || memSize == 32)    
    {
        uint16_t scrSize = (memSize == 32)? 32:64;
        auto scrReg64 = scrRegs64[2];
        auto scrReg = new X86Reg(X86Reg.GP, scrReg64.regNo, scrSize);

        // Load to a scratch register and then move to the output
        ctx.as.instr(loadOp, scrReg, memOpnd);
        ctx.as.instr(MOV, opndOut, scrReg64);
    }
    else
    {
        // Load to the output register directly
        ctx.as.instr(loadOp, opndOut, memOpnd);
    }

    // Set the output type tag
    st.setOutType(ctx.as, instr, typeTag);
}

alias LoadOp!(8 , Type.INT32) gen_load_u8;
alias LoadOp!(16, Type.INT32) gen_load_u16;
alias LoadOp!(32, Type.INT32) gen_load_u32;
alias LoadOp!(64, Type.INT64) gen_load_u64;
alias LoadOp!(64, Type.FLOAT64) gen_load_f64;
alias LoadOp!(64, Type.REFPTR) gen_load_refptr;
alias LoadOp!(64, Type.RAWPTR) gen_load_rawptr;

void StoreOp(size_t memSize, Type typeTag)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // The pointer operand must be a register
    auto opnd0 = cast(X86Reg)st.getWordOpnd(ctx, ctx.as, instr, 0, 64, scrRegs64[0]);

    // The offset operand may be a register or an immediate
    auto opnd1 = st.getWordOpnd(ctx, ctx.as, instr, 1, 32, scrRegs32[1], true);

    // The value operand may be a register or an immediate
    auto opnd2 = st.getWordOpnd(ctx, ctx.as, instr, 2, memSize, scrRegs64[2].ofSize(memSize), true);

    // Create the memory operand
    X86Mem memOpnd;
    if (auto immOffs = cast(X86Imm)opnd1)
    {
        memOpnd = new X86Mem(memSize, opnd0, cast(int32_t)immOffs.imm);
    }
    else if (auto regOffs = cast(X86Reg)opnd1)
    {
        // Zero-extend the offset from 32 to 64 bits
        ctx.as.instr(MOV, regOffs, regOffs);
        memOpnd = new X86Mem(memSize, opnd0, 0, regOffs.ofSize(64));
    }
    else
    {
        assert (false, "invalid offset operand");
    }

    // Store the value into the memory location
    ctx.as.instr(MOV, memOpnd, opnd2);
}

alias StoreOp!(8 , Type.INT32) gen_store_u8;
alias StoreOp!(16, Type.INT32) gen_store_u16;
alias StoreOp!(32, Type.INT32) gen_store_u32;
alias StoreOp!(64, Type.INT64) gen_store_u64;
alias StoreOp!(64, Type.FLOAT64) gen_store_f64;
alias StoreOp!(64, Type.REFPTR) gen_store_refptr;
alias StoreOp!(64, Type.RAWPTR) gen_store_rawptr;

void gen_get_global(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto idxArg = cast(IRCachedIdx)instr.getArg(1);
    assert (idxArg !is null);
    auto propIdx = idxArg.idx;

    // If no property index is cached, use the interpreter function
    if (propIdx is idxArg.idx.max)
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
    auto idxArg = cast(IRCachedIdx)instr.getArg(2);
    assert (idxArg !is null);
    auto propIdx = idxArg.idx;

    // If no property index is cached, use the interpreter function
    if (propIdx is idxArg.idx.max)
    {
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    // Allocate the input operand
    auto argOpnd = st.getWordOpnd(ctx, ctx.as, instr, 1, 64, scrRegs64[0], true);

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(scrRegs64[1], interpReg);

    // Get the global object size/capacity
    ctx.as.getField(scrRegs32[2], scrRegs64[1], 4, obj_ofs_cap(interp.globalObj));

    // Get the offset of the start of the word array
    auto wordOfs = obj_ofs_word(interp.globalObj, 0);

    // Set the word value
    auto wordMem = new X86Mem(64, scrRegs64[1], wordOfs + 8 * propIdx);
    ctx.as.instr(MOV, wordMem, argOpnd);

    // Set the type value
    auto typeOpnd = st.getTypeOpnd(ctx.as, instr, 1, scrRegs8[0], true);
    auto typeMem = new X86Mem(8, scrRegs64[1], wordOfs + propIdx, scrRegs64[2], 8);
    ctx.as.instr(MOV, typeMem, typeOpnd);
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

/*
void gen_heap_alloc(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Label for the bailout case
    auto BAILOUT = new Label("ALLOC_BAILOUT");

    // Label for the exit
    auto DONE = new Label("ALLOC_DONE");

    // Get the allocation size operand
    auto szOpnd = st.getWordOpnd(ctx, ctx.as, instr, 0, 64, null, true);

    ctx.as.getMember!("Interp", "allocPtr")(scrRegs64[0], interpReg);
    ctx.as.getMember!("Interp", "heapLimit")(scrRegs64[1], interpReg);

    // r2 = allocPtr + size
    ctx.as.instr(MOV, scrRegs64[2], scrRegs64[0]);
    ctx.as.instr(ADD, scrRegs64[2], szOpnd);

    // if (allocPtr + size > heapLimit) bailout
    ctx.as.instr(CMP, scrRegs64[2], scrRegs64[1]);
    ctx.as.instr(JG, BAILOUT);

    // Clone the state for the bailout case, which will spill for GC
    auto bailSt = new CodeGenState(st);

    // Get the output operand
    auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);

    // Move the allocation pointer to the output
    ctx.as.instr(MOV, opndOut, scrRegs64[0]);

    // Align the incremented allocation pointer
    ctx.as.instr(ADD, scrRegs64[2], 7);
    ctx.as.instr(AND, scrRegs64[2], -8);

    // Store the incremented and aligned allocation pointer
    ctx.as.setMember!("Interp", "allocPtr")(interpReg, scrRegs64[2]);

    // Allocation done
    ctx.as.addInstr(DONE);

    // The output is a reference pointer
    st.setOutType(ctx.as, instr, Type.REFPTR);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(BAILOUT);

    // Save our allocated registers
    if (allocRegs.length % 2 != 0)
        ctx.ol.instr(PUSH, allocRegs[0]);
    foreach (reg; allocRegs)
        ctx.ol.instr(PUSH, reg);

    ctx.ol.printStr("alloc bailout ***");

    // Fallback to interpreter execution
    // Spill all values, including arguments
    // Call the interpreter alloc instruction
    defaultFn(ctx.ol, ctx, bailSt, instr);

    //ctx.ol.printStr("alloc bailout done ***");

    // Restore the allocated registers
    foreach_reverse(reg; allocRegs)
        ctx.ol.instr(POP, reg);
    if (allocRegs.length % 2 != 0)
        ctx.ol.instr(POP, allocRegs[0]);

    // If the output operand is a register
    if (cast(X86Reg)opndOut)
    {
        // Load the stack value into the register
        auto stackOpnd = bailSt.getWordOpnd(instr, 64);
        ctx.ol.instr(MOV, opndOut, stackOpnd);
    }

    // Allocation done
    ctx.ol.instr(JMP, DONE);
}
*/

/**
Generates the conditional branch for an if_true instruction with the given
conditional jump operations. Assumes a comparison between input operands has
already been inserted.
*/
void genCondBranch(
    CodeGenCtx ctx, 
    IRInstr ifInstr, 
    X86OpPtr trueOp, 
    X86OpPtr falseOp,
    CodeGenState trueSt,
    CodeGenState falseSt
)
{
    auto trueTarget = ifInstr.getTarget(0);
    auto falseTarget = ifInstr.getTarget(1);

    BranchDesc fastTarget;
    BranchDesc slowTarget;
    CodeGenState fastSt;
    CodeGenState slowSt;
    X86OpPtr jumpOp;

    // If the true branch is more often executed
    if (trueTarget.succ.execCount > falseTarget.succ.execCount)
    {
        // False result causes a jump
        fastTarget = trueTarget;
        slowTarget = falseTarget;
        fastSt = trueSt;
        slowSt = falseSt;
        jumpOp = falseOp; 
    }
    else
    {
        // True result causes a jump
        fastTarget = falseTarget;
        slowTarget = trueTarget;
        fastSt = falseSt;
        slowSt = trueSt;
        jumpOp = trueOp;
    }

    auto slowLabel = new Label("IF_UNLIKELY");
    auto fastLabel = new Label("IF_LIKELY");

    // Jump conditionally to the slow label
    ctx.as.instr(jumpOp, slowLabel);

    // Jump directly to the fast label
    ctx.as.instr(JMP, fastLabel);

    // Get the fast target label last so the fast target is
    // more likely to get generated first (LIFO stack)
    ctx.genBranchEdge(ctx.as, slowLabel, slowTarget, slowSt);
    ctx.genBranchEdge(ctx.as, fastLabel, fastTarget, fastSt);
}

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
        instr.prev.opcode.boolVal &&
        instr.prev.opcode in codeGenFns
    );
}

void IsTypeOp(Type type)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto argVal = instr.getArg(0);

    // If the type of the argument is known
    if (st.typeKnown(argVal))
    {
        // Mark the value as a known constant
        // This will defer writing the value
        auto knownType = st.getType(argVal);
        st.setOutBool(instr, type is knownType);

        return;
    }

    // Increment the type test stat counter
    ctx.as.incStatCnt!("stats.numTypeTests")(scrRegs64[0]);

    // Get an operand for the value's type
    auto typeOpnd = st.getTypeOpnd(ctx.as, instr, 0);

    // Compare against the tested type
    ctx.as.instr(CMP, typeOpnd, type);

    // If this instruction has many uses or is not followed by an if
    if (instr.hasManyUses || ifUseNext(instr) is false)
    {
        // We must have a register for the output (so we can use cmov)
        auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);
        auto outReg = cast(X86Reg)opndOut;
        if (outReg is null)
            outReg = scrRegs64[0];
        auto outReg32 = outReg.ofSize(32);

        ctx.as.instr(MOV    , outReg32      , FALSE.int8Val);
        ctx.as.instr(MOV    , scrRegs32[1]  , TRUE.int8Val );
        ctx.as.instr(CMOVE  , outReg32      , scrRegs32[1] );

        // If the output is not a register
        if (opndOut !is outReg)
            ctx.as.instr(MOV, opndOut, outReg);

        // Set the output type
        st.setOutType(ctx.as, instr, Type.CONST);
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
        ctx.genCondBranch(instr.next, JE, JNE, trueSt, st);
    }
}

alias IsTypeOp!(Type.CONST) gen_is_const;
alias IsTypeOp!(Type.REFPTR) gen_is_refptr;
alias IsTypeOp!(Type.RAWPTR) gen_is_rawptr;
alias IsTypeOp!(Type.INT32) gen_is_i32;
alias IsTypeOp!(Type.INT64) gen_is_i64;
alias IsTypeOp!(Type.FLOAT64) gen_is_f64;

void CmpOp(string op, size_t numBits)(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // The first operand must be memory or register, but not immediate
    auto opnd0 = st.getWordOpnd(
        ctx, 
        ctx.as, 
        instr, 
        0,
        numBits, 
        scrRegs64[0].ofSize(numBits),
        false
    );

    // The second operand may be an immediate
    auto opnd1 = st.getWordOpnd(
        ctx, 
        ctx.as, 
        instr, 
        1, 
        numBits, 
        scrRegs64[1].ofSize(numBits),
        true
    );

    // Compare the inputs
    ctx.as.instr(CMP, opnd0, opnd1);

    // Choose conditional instructions based on the comparison operator
    X86OpPtr cmovOp = null;
    X86OpPtr trueOp = null;
    X86OpPtr falseOp = null;
    static if (op == "eq")
    {
        cmovOp  = CMOVE;
        trueOp  = JE;
        falseOp = JNE;
    }
    static if (op == "ne")
    {
        cmovOp  = CMOVNE;
        trueOp  = JNE;
        falseOp = JE;
    }
    static if (op == "lt")
    {
        cmovOp  = CMOVL;
        trueOp  = JL;
        falseOp = JGE;
    }
    static if (op == "le")
    {
        cmovOp  = CMOVLE;
        trueOp  = JLE;
        falseOp = JG;
    }
    static if (op == "gt")
    {
        cmovOp = CMOVG;
        trueOp  = JG;
        falseOp = JLE;
    }
    static if (op == "ge")
    {
        cmovOp = CMOVGE;
        trueOp  = JGE;
        falseOp = JL;
    }

    // If this instruction has many uses or is not followed by an if
    if (instr.hasManyUses || ifUseNext(instr) is false)
    {
        // We must have a register for the output (so we can use cmov)
        auto opndOut = st.getOutOpnd(ctx, ctx.as, instr, 64);
        auto outReg = cast(X86Reg)opndOut;
        if (outReg is null)
            outReg = scrRegs64[0];
        auto outReg32 = outReg.ofSize(32);

        ctx.as.instr(MOV   , outReg32       , FALSE.int8Val);
        ctx.as.instr(MOV   , scrRegs32[1]   , TRUE.int8Val );
        ctx.as.instr(cmovOp, outReg32       , scrRegs32[1] );

        // If the output is not a register
        if (opndOut !is outReg)
            ctx.as.instr(MOV, opndOut, outReg);

        // Set the output type
        st.setOutType(ctx.as, instr, Type.CONST);
    }

    // If our only use is an immediately following if_true
    if (ifUseNext(instr) is true)
    {
        // Generate the conditional branch and targets here
        ctx.genCondBranch(instr.next, trueOp, falseOp, st, st);
    }
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

void gen_if_true(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto argVal = instr.getArg(0);

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

    // If a boolean argument immediately precedes, the
    // conditional branch has already been generated
    if (boolArgPrev(instr) is true)
        return;

    // Compare the argument to the true boolean value
    auto argOpnd = st.getWordOpnd(ctx, ctx.as, instr, 0, 8);
    ctx.as.instr(CMP, argOpnd, TRUE.int8Val);

    // Generate the conditional branch and targets
    ctx.genCondBranch(instr, JE, JNE, st, st);
}

void gen_if_eq_fun(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Label for the function not equal case
    auto NOT_EQ = new Label("FUN_NOT_EQ");

    // Get the type tag for the closure value
    auto closType = st.getTypeOpnd(
        ctx.as, 
        instr, 
        0, 
        scrRegs8[0],
        false
    );

    // If the value is not a reference, not equal
    ctx.as.instr(CMP, closType, Type.REFPTR);
    ctx.as.instr(JNE, NOT_EQ);

    // Get the word for the closure value
    auto closReg = cast(X86Reg)st.getWordOpnd(
        ctx, 
        ctx.as, 
        instr, 
        0,
        64,
        scrRegs64[0],
        true,
        false
    );
    assert (closReg !is null);

    // If the object is not a closure, not equal
    ctx.as.instr(MOV, scrRegs32[1], new X86Mem(32, closReg, obj_ofs_header(null)));
    ctx.as.instr(CMP, scrRegs32[1], LAYOUT_CLOS);
    ctx.as.instr(JNE, NOT_EQ);

    // Get the function pointer from the closure object
    auto fptrMem = new X86Mem(64, closReg, CLOS_OFS_FPTR);
    ctx.as.instr(MOV, scrRegs64[1], fptrMem);

    // If this is not the closure we expect, not equal
    auto funArg = cast(IRFunPtr)instr.getArg(1);
    assert (funArg !is null);
    ctx.as.ptr(scrRegs64[2], funArg.fun);
    ctx.as.instr(CMP, scrRegs64[1], scrRegs64[2]);
    ctx.as.instr(JNE, NOT_EQ);

    // Generate the slow branch out of line
    ctx.genBranchEdge(ctx.ol, NOT_EQ, instr.getTarget(1), st);

    // Get the fast target label last so the fast target is
    // more likely to get generated first (LIFO stack)
    // The equal case is generated directly inline
    ctx.genBranchEdge(ctx.as, null, instr.getTarget(0), st);
}

void gen_jump(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Jump to the target block
    ctx.genBranchEdge(ctx.as, null, instr.getTarget(0), st);
}

void gen_call(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Generate a JIT entry point for the call continuation
    ctx.genCallCont(instr);

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
    assert (fun !is null && fun.entryBlock !is null);

    // If the argument count doesn't match
    auto numArgs = cast(int32_t)instr.numArgs - 2;
    if (numArgs != fun.numParams)
    {
        ctx.as.incStatCnt!("stats.numCallBailouts")(scrRegs64[0]);

        // Call the interpreter call instruction
        defaultFn(ctx.as, ctx, st, instr);
        return;
    }

    // Save the current state before any values are spilled
    auto entrySt = new CodeGenState(st);

    // Label for the bailout to interpreter cases
    auto BAILOUT = new Label("CALL_BAILOUT");

    //
    // Function pointer extraction
    //

    // Get the type tag for the closure value
    auto closType = st.getTypeOpnd(
        ctx.as, 
        instr, 
        0, 
        scrRegs8[0],
        false
    );

    // If the value is not a reference, bailout to the interpreter
    ctx.as.instr(CMP, closType, Type.REFPTR);
    ctx.as.instr(JNE, BAILOUT);

    // Get the word for the closure value
    auto closReg = cast(X86Reg)st.getWordOpnd(
        ctx, 
        ctx.as, 
        instr, 
        0,
        64,
        scrRegs64[0],
        true,
        false
    );
    assert (closReg !is null);

    // If the object is not a closure, bailout
    ctx.as.instr(MOV, scrRegs32[1], new X86Mem(32, closReg, obj_ofs_header(null)));
    ctx.as.instr(CMP, scrRegs32[1], LAYOUT_CLOS);
    ctx.as.instr(JNE, BAILOUT);

    // Get the function pointer from the closure object
    auto fptrMem = new X86Mem(64, closReg, CLOS_OFS_FPTR);
    ctx.as.instr(MOV, scrRegs64[1], fptrMem);

    //
    // Function call logic
    //

    // If this is not the closure we expect, bailout to the interpreter
    ctx.as.ptr(scrRegs64[2], fun);
    ctx.as.instr(CMP, scrRegs64[1], scrRegs64[2]);
    ctx.as.instr(JNE, BAILOUT);

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto instrArgIdx = instr.numArgs - (1+i);
        auto dstIdx = -(cast(int32_t)i + 1);

        // Copy the argument word
        auto argOpnd = st.getWordOpnd(
            ctx, 
            ctx.as, 
            instr, 
            instrArgIdx,
            64,
            scrRegs64[2],
            true,
            false
        );
        ctx.as.setWord(dstIdx, argOpnd);

        // Copy the argument type
        auto typeOpnd = st.getTypeOpnd(
            ctx.as, 
            instr, 
            instrArgIdx, 
            scrRegs8[2], 
            true
        );
        ctx.as.setType(dstIdx, typeOpnd);
    }

    // Write the argument count
    ctx.as.setWord(-numArgs - 1, numArgs);
    ctx.as.setType(-numArgs - 1, Type.INT32);

    // If the callee uses its "this" argument, write it on the stack
    if (fun.ast.usesThis == true)
    {
        auto thisReg = cast(X86Reg)st.getWordOpnd(
            ctx, 
            ctx.as, 
            instr, 
            1,
            64,
            scrRegs64[2],
            true,
            false
        );
        assert (thisReg !is null);
        ctx.as.setWord(-numArgs - 2, thisReg);

        auto typeOpnd = st.getTypeOpnd(ctx.as, instr, 1, scrRegs8[2], true);
        ctx.as.setType(-numArgs - 2, typeOpnd);
    }

    // If the callee uses its closure argument, write it on the stack
    if (fun.ast.usesClos == true)
    {
        ctx.as.setWord(-numArgs - 3, closReg);
        ctx.as.setType(-numArgs - 3, Type.REFPTR);
    }

    // Write the return address (caller instruction)
    ctx.as.ptr(scrRegs64[2], instr);
    ctx.as.setWord(-numArgs - 4, scrRegs64[2]);
    ctx.as.setType(-numArgs - 4, Type.INSPTR);

    // Spill the values that are live after the call
    st.spillRegs(
        ctx.as,
        delegate bool(IRDstValue val)
        {
            return ctx.liveInfo.liveAfter(val, instr);
        }
    );

    // Push space for the callee arguments and locals
    ctx.as.getMember!("IRFunction", "numLocals")(scrRegs32[1], scrRegs64[1]);
    ctx.as.instr(SUB, tspReg, scrRegs64[1]);
    ctx.as.instr(SHL, scrRegs64[1], 3);
    ctx.as.instr(SUB, wspReg, scrRegs64[1]);

    // Label for the interpreter jump
    auto INTERP_JUMP = new Label("INTERP_JUMP");

    // Get a pointer to the branch target
    ctx.as.ptr(scrRegs64[0], fun.entryBlock);

    // If a JIT entry point exists, jump to it directly
    ctx.as.getMember!("IRBlock", "jitEntry")(scrRegs64[1], scrRegs64[0]);
    ctx.as.instr(CMP, scrRegs64[1], 0);
    ctx.as.instr(JE, INTERP_JUMP);
    ctx.as.instr(JMP, scrRegs64[1]);

    // Make the interpreter jump to the target
    ctx.ol.addInstr(INTERP_JUMP);
    ctx.ol.setMember!("Interp", "target")(interpReg, scrRegs64[0]);
    ctx.ol.instr(JMP, ctx.bailLabel);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(BAILOUT);
    //ctx.ol.printStr("call bailout in " ~ instr.block.fun.getName);

    ctx.ol.incStatCnt!("stats.numCallBailouts")(scrRegs64[0]);

    // Fallback to interpreter execution
    // Spill all values, including arguments
    // Call the interpreter call instruction
    defaultFn(ctx.ol, ctx, entrySt, instr);
}

void gen_call_prim(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    // Generate a JIT entry point for the call continuation
    ctx.genCallCont(instr);

    // Get the cached function pointer
    auto funArg = cast(IRFunPtr)instr.getArg(1);
    assert (funArg !is null);
    auto fun = funArg.fun;
    assert (fun !is null);

    // Check that the argument count matches
    auto numArgs = cast(int32_t)instr.numArgs - 2;
    assert (numArgs is fun.numParams);

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto instrArgIdx = instr.numArgs - (1+i);
        auto dstIdx = -(cast(int32_t)i + 1);

        // Copy the argument word
        auto argOpnd = st.getWordOpnd(
            ctx, 
            ctx.as, 
            instr, 
            instrArgIdx,
            64,
            scrRegs64[1],
            true,
            false
        );
        ctx.as.setWord(dstIdx, argOpnd);

        // Copy the argument type
        auto typeOpnd = st.getTypeOpnd(
            ctx.as, 
            instr, 
            instrArgIdx, 
            scrRegs8[1], 
            true
        );
        ctx.as.setType(dstIdx, typeOpnd);
    }

    // Write the argument count
    ctx.as.setWord(-numArgs - 1, numArgs);
    ctx.as.setType(-numArgs - 1, Type.INT32);

    // Set the "this" argument to null
    ctx.as.setWord(-numArgs - 2, NULL.int32Val);
    ctx.as.setType(-numArgs - 2, Type.REFPTR);

    // Set the closure argument to null
    ctx.as.setWord(-numArgs - 3, NULL.int32Val);
    ctx.as.setType(-numArgs - 3, Type.REFPTR);

    // Write the return address (caller instruction)
    ctx.as.ptr(scrRegs64[0], instr);
    ctx.as.setWord(-numArgs - 4, scrRegs64[0]);
    ctx.as.setType(-numArgs - 4, Type.INSPTR);

    // Spill the values that are live after the call
    st.spillRegs(
        ctx.as,
        delegate bool(IRDstValue val)
        {
            return ctx.liveInfo.liveAfter(val, instr);
        }
    );

    // Push space for the callee arguments and locals
    ctx.as.ptr(scrRegs64[0], fun);
    ctx.as.getMember!("IRFunction", "numLocals")(scrRegs32[0], scrRegs64[0]);
    ctx.as.instr(SUB, tspReg, scrRegs64[0]);
    ctx.as.instr(SHL, scrRegs64[0], 3);
    ctx.as.instr(SUB, wspReg, scrRegs64[0]);

    // Label for the interpreter jump
    auto INTERP_JUMP = new Label("INTERP_JUMP");

    // Get a pointer to the branch target
    ctx.as.ptr(scrRegs64[0], fun.entryBlock);

    // If a JIT entry point exists, jump to it directly
    ctx.as.getMember!("IRBlock", "jitEntry")(scrRegs64[1], scrRegs64[0]);
    ctx.as.instr(CMP, scrRegs64[1], 0);
    ctx.as.instr(JE, INTERP_JUMP);
    ctx.as.instr(JMP, scrRegs64[1]);

    // Make the interpreter jump to the target
    ctx.ol.addInstr(INTERP_JUMP);
    ctx.ol.setMember!("Interp", "target")(interpReg, scrRegs64[0]);
    ctx.ol.instr(JMP, ctx.bailLabel);
}

void gen_ret(CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    auto raSlot    = instr.block.fun.raVal.outSlot;
    auto argcSlot  = instr.block.fun.argcVal.outSlot;
    auto numParams = instr.block.fun.numParams;
    auto numLocals = instr.block.fun.numLocals;

    // Find an extra scratch register
    auto curWordOpnd = st.getWordOpnd(instr.getArg(0), 64);
    X86Reg scrReg3;
    if (curWordOpnd == allocRegs[0])
        scrReg3 = allocRegs[1].ofSize(32);
    else
        scrReg3 = allocRegs[0].ofSize(32);

    // Label for the bailout to interpreter cases
    auto BAILOUT = new Label("RET_BAILOUT");

    //ctx.as.printStr("ret from " ~ instr.block.fun.getName);

    // Get the call instruction into r0
    ctx.as.getWord(scrRegs64[0], raSlot);

    // If this is a new/constructor call, bailout
    ctx.as.getMember!("IRInstr", "opcode")(scrRegs64[1], scrRegs64[0]);   
    ctx.as.ptr(scrRegs64[2], &ir.ops.CALL_NEW);
    ctx.as.instr(CMP, scrRegs64[1], scrRegs64[2]);
    ctx.as.instr(JE, BAILOUT);

    // Get the output slot for the call instruction into scratch r1
    ctx.as.getMember!("IRInstr", "outSlot")(scrRegs32[1], scrRegs64[0]);

    // Get the actual argument count into r2
    ctx.as.getWord(scrRegs32[2], argcSlot);

    // Compare the arg count against the expected count
    ctx.as.instr(CMP, scrRegs32[2], numParams);

    // Compute the number of extra arguments into r2
    ctx.as.instr(SUB, scrRegs32[2], numParams);
    ctx.as.instr(MOV, scrReg3, 0);
    ctx.as.instr(CMOVL, scrRegs32[2], scrReg3);

    // Adjust the output slot for extra arguments
    ctx.as.instr(ADD, scrRegs32[1], scrRegs32[2]);

    // Compute the number of stack slots to pop into r2
    ctx.as.instr(ADD, scrRegs32[2], numLocals);

    // Copy the return value word
    auto retOpnd = st.getWordOpnd(
        ctx, 
        ctx.as, 
        instr, 
        0,
        64,
        scrReg3.ofSize(64),
        true,
        false
    );
    ctx.as.instr(
        MOV, 
        new X86Mem(64, wspReg, 8 * numLocals, scrRegs64[1], 8),
        retOpnd
    );

    // Copy the return value type
    auto typeOpnd = st.getTypeOpnd(
        ctx.as, 
        instr, 
        0, 
        scrReg3.ofSize(8),
        true
    );
    ctx.as.instr(
        MOV, 
        new X86Mem(8, tspReg, numLocals, scrRegs64[1]),
        typeOpnd
    );

    // Pop all local stack slots and arguments
    ctx.as.instr(ADD, tspReg, scrRegs64[2]);
    ctx.as.instr(SHL, scrRegs64[2], 3);
    ctx.as.instr(ADD, wspReg, scrRegs64[2]);

    // Label for the interpreter jump
    auto INTERP_JUMP = new Label("INTERP_JUMP");

    // Function to make the interpreter jump to the call continuation
    extern (C) void interpBranch(Interp interp, IRInstr callInstr)
    {
        auto desc = callInstr.getTarget(0);

        /*
        writefln(
            "interp ret to %s (%s phis)", 
            callInstr.block.fun.getName,
            desc.args.length
        );
        */

        interp.branch(desc);
    }

    // If a JIT entry point exists, jump to it directly
    // Note: this will execute the phi node moves on entry
    ctx.as.getMember!("IRInstr", "jitCont")(scrRegs64[1], scrRegs64[0]);
    ctx.as.instr(CMP, scrRegs64[1], 0);
    ctx.as.instr(JE, INTERP_JUMP);
    //ctx.as.printStr("jit ret");
    ctx.as.instr(JMP, scrRegs64[1]);

    // Make the interpreter jump to the call continuation and bailout
    ctx.ol.addInstr(INTERP_JUMP);
    //ctx.ol.printStr("interp ret");
    ctx.ol.setMember!("Interp", "wsp")(interpReg, wspReg);
    ctx.ol.setMember!("Interp", "tsp")(interpReg, tspReg);
    ctx.ol.instr(MOV, RDI, interpReg);
    ctx.ol.instr(MOV, RSI, scrRegs64[0]);
    ctx.ol.ptr(scrRegs64[0], &interpBranch);
    ctx.ol.instr(jit.encodings.CALL, scrRegs64[0]);
    ctx.ol.instr(JMP, ctx.bailLabel);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(BAILOUT);
    //ctx.ol.printStr("ret bailout in " ~ instr.block.fun.getName ~ " (" ~ instr.block.getName ~ ")");

    ctx.ol.incStatCnt!("stats.numRetBailouts")(scrRegs64[0]);

    // Fallback to interpreter execution
    // Spill all values, including arguments
    // Call the interpreter call instruction
    defaultFn(ctx.ol, ctx, st, instr);
}

void defaultFn(Assembler as, CodeGenCtx ctx, CodeGenState st, IRInstr instr)
{
    //ctx.as.printStr(instr.toString);

    // Spill all live values and instruction arguments
    st.spillRegs(
        as,
        delegate bool(IRDstValue value)
        {
            if (instr.hasArg(value))
                return true;

            if (ctx.liveInfo.liveAfter(value, instr))
                return true;

            return false;
        }
    );

    // Increment the unjitted instruction counter
    as.incStatCnt!("stats.numUnjitInstrs")(scrRegs64[0]);

    // Get the function corresponding to this instruction
    // alias void function(Interp interp, IRInstr instr) OpFn;
    // RDI: first argument (interp)
    // RSI: second argument (instr)
    auto opFn = instr.opcode.opFn;

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
        st.valOnStack(instr);
    }
}

alias void function(CodeGenCtx ctx, CodeGenState st, IRInstr instr) CodeGenFn;

CodeGenFn[Opcode*] codeGenFns;

static this()
{
    codeGenFns[&GET_ARG]        = &gen_get_arg;

    codeGenFns[&SET_STR]        = &gen_set_str;

    codeGenFns[&MAKE_VALUE]     = &gen_make_value;
    codeGenFns[&GET_WORD]       = &gen_get_word;
    codeGenFns[&GET_TYPE]       = &gen_get_type;

    codeGenFns[&I32_TO_F64]     = &gen_i32_to_f64;
    codeGenFns[&F64_TO_I32]     = &gen_f64_to_i32;

    codeGenFns[&ADD_I32]        = &gen_add_i32;
    codeGenFns[&MUL_I32]        = &gen_mul_i32;
    codeGenFns[&AND_I32]        = &gen_and_i32;
    codeGenFns[&OR_I32]         = &gen_or_i32;
    codeGenFns[&XOR_I32]        = &gen_xor_i32;

    codeGenFns[&ADD_I32_OVF]    = &gen_add_i32_ovf;
    codeGenFns[&SUB_I32_OVF]    = &gen_sub_i32_ovf;
    codeGenFns[&MUL_I32_OVF]    = &gen_mul_i32_ovf;

    codeGenFns[&MOD_I32]        = &gen_mod_i32;

    codeGenFns[&LSFT_I32]       = &gen_lsft_i32;
    codeGenFns[&RSFT_I32]       = &gen_rsft_i32;

    codeGenFns[&ADD_F64]        = &gen_add_f64;
    codeGenFns[&SUB_F64]        = &gen_sub_f64;
    codeGenFns[&MUL_F64]        = &gen_mul_f64;
    codeGenFns[&DIV_F64]        = &gen_div_f64;

    codeGenFns[&LOAD_U8]        = &gen_load_u8;
    codeGenFns[&LOAD_U16]       = &gen_load_u16;
    codeGenFns[&LOAD_U32]       = &gen_load_u32;
    codeGenFns[&LOAD_U64]       = &gen_load_u64;
    codeGenFns[&LOAD_F64]       = &gen_load_f64;
    codeGenFns[&LOAD_REFPTR]    = &gen_load_refptr;
    codeGenFns[&LOAD_RAWPTR]    = &gen_load_rawptr;

    codeGenFns[&STORE_U8]       = &gen_store_u8;
    codeGenFns[&STORE_U16]      = &gen_store_u16;
    codeGenFns[&STORE_U32]      = &gen_store_u32;
    codeGenFns[&STORE_U64]      = &gen_store_u64;
    codeGenFns[&STORE_F64]      = &gen_load_f64;
    codeGenFns[&STORE_REFPTR]   = &gen_store_refptr;
    codeGenFns[&STORE_RAWPTR]   = &gen_store_rawptr;

    codeGenFns[&GET_GLOBAL]     = &gen_get_global;
    codeGenFns[&SET_GLOBAL]     = &gen_set_global;

    codeGenFns[&GET_GLOBAL_OBJ] = &gen_get_global_obj;

    //codeGenFns[&HEAP_ALLOC]     = &gen_heap_alloc;

    codeGenFns[&IS_CONST]       = &gen_is_const;
    codeGenFns[&IS_REFPTR]      = &gen_is_refptr;
    codeGenFns[&IS_RAWPTR]      = &gen_is_rawptr;
    codeGenFns[&IS_I32]         = &gen_is_i32;
    codeGenFns[&IS_I64]         = &gen_is_i64;
    codeGenFns[&IS_F64]         = &gen_is_f64;

    codeGenFns[&EQ_I8]          = &gen_eq_i8;
    codeGenFns[&EQ_I32]         = &gen_eq_i32;
    codeGenFns[&NE_I32]         = &gen_ne_i32;
    codeGenFns[&LT_I32]         = &gen_lt_i32;
    codeGenFns[&LE_I32]         = &gen_le_i32;
    codeGenFns[&GT_I32]         = &gen_gt_i32;
    codeGenFns[&GE_I32]         = &gen_ge_i32;
    codeGenFns[&EQ_CONST]       = &gen_eq_const;
    codeGenFns[&NE_CONST]       = &gen_ne_const;
    codeGenFns[&EQ_REFPTR]      = &gen_eq_refptr;
    codeGenFns[&NE_REFPTR]      = &gen_ne_refptr;
    codeGenFns[&EQ_RAWPTR]      = &gen_eq_rawptr;

    codeGenFns[&IF_TRUE]        = &gen_if_true;
    codeGenFns[&IF_EQ_FUN]      = &gen_if_eq_fun;
    codeGenFns[&JUMP]           = &gen_jump;

    codeGenFns[&ir.ops.CALL]    = &gen_call;
    codeGenFns[&CALL_PRIM]      = &gen_call_prim;
    codeGenFns[&ir.ops.RET]     = &gen_ret;
}

