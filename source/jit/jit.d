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
import std.string;
import std.array;
import std.stdint;
import options;
import ir.ir;
import interp.interp;
import interp.layout;
import jit.codeblock;
import jit.assembler;
import jit.x86;
import jit.encodings;

extern (C) void printUint(uint64_t v)
{
    writefln("%s", v);
}

CodeBlock compileBlock(Interp interp, IRBlock block)
{
    assert (
        block.firstInstr !is null,
        "first instr of block is null"
    );

    assert (
        block.fun !is null,
        "block fun ptr is null"
    );

    //writefln("compiling tracelet in %s:\n%s\n", block.fun.getName(), block.toString());

    // Assembler to write code into
    auto as = new Assembler();

    // Label at the trace join point (exported)
    auto traceJoin = new Label("trace_join", true);

    // Label at the end of the block
    auto traceExit = new Label("trace_exit");

    // Create a code generation context
    auto ctx = CodeGenCtx(interp, as, traceExit);

    // Align SP to a multiple of 16 bytes
    as.instr(SUB, RSP, 8);

    // Save the GP registers
    as.instr(PUSH, RBX);
    as.instr(PUSH, RBP);
    as.instr(PUSH, R12);
    as.instr(PUSH, R13);
    as.instr(PUSH, R14);
    as.instr(PUSH, R15);

    // Store a pointer to the interpreter in R15
    ctx.ptr(R15, interp);

    // Load the stack pointers into RBX and RBP
    ctx.getField(RBX, R15, interp.wsp.sizeof, interp.wsp.offsetof);
    ctx.getField(RBP, R15, interp.tsp.sizeof, interp.tsp.offsetof);

    // Join point of the tracelet
    as.addInstr(traceJoin);

    // Increment the block execution count
    ctx.ptr(RAX, block);
    as.instr(INC, X86Opnd(8*block.execCount.sizeof, RAX, block.execCount.offsetof));

    // For each instruction of the block
    for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
    {
        auto opcode = instr.opcode;

        // TODO: remove this
        // Unsupported opcodes abort the compilation
        if (opcode.isBranch && 
            opcode != &JUMP && 
            opcode != &ir.ir.RET && 
            opcode != &ir.ir.CALL &&
            opcode != &CALL_NEW &&
            opcode != &JUMP_TRUE &&
            opcode != &JUMP_FALSE)
            return null;

        // If there is a codegen function for this opcode
        if (opcode in codeGenFns)
        {
            // Call the code generation function for the opcode
            codeGenFns[opcode](ctx, instr);
        }
        else
        {
            // Use the default code generation function
            defaultFn(ctx, instr);
        }

        // If we know the instruction will definitely leave 
        // this block, stop the block compilation
        if (opcode == &JUMP         ||
            opcode == &ir.ir.CALL   || 
            opcode == &CALL_NEW     || 
            opcode == &ir.ir.RET    || 
            opcode == &THROW)
            break;
    }

    // Block end, exit of tracelet
    as.addInstr(traceExit);

    // TODO: Store back wsp, tsp in the interpreter
    // TODO: store only if they changed

    // Restore the GP registers
    as.instr(POP, R15);
    as.instr(POP, R14);
    as.instr(POP, R13);
    as.instr(POP, R12);
    as.instr(POP, RBP);
    as.instr(POP, RBX);

    // Pop the stack alignment padding
    as.instr(ADD, RSP, 8);

    // Return to the interpreter
    as.instr(jit.encodings.RET);

    if (opts.dumpasm)
        writefln("\n%s\n", as.toString(true));

    // Assemble the machine code
    auto codeBlock = as.assemble();

    // Return a pointer to the compiled code
    return codeBlock;
}

struct CodeGenCtx
{
    /// Interpreter object
    Interp interp;

    /// Assembler into which to generate code
    Assembler as;

    /// Trace exit label
    Label traceExit;

    void ptr(TPtr)(X86RegPtr destReg, TPtr ptr)
    {
        as.instr(MOV, destReg, X86Opnd(cast(void*)ptr));
    }

    void getField(X86RegPtr dstReg, X86RegPtr baseReg, size_t fSize, size_t fOffset)
    {
        as.instr(MOV, dstReg, X86Opnd(8*fSize, baseReg, cast(int32_t)fOffset));
    }

    void setField(X86RegPtr baseReg, size_t fSize, size_t fOffset, X86RegPtr srcReg)
    {
        as.instr(MOV, X86Opnd(8*fSize, baseReg, cast(int32_t)fOffset), srcReg);
    }

    // TODO: getWord, getType





    void jump(IRBlock target)
    {
        auto interpJump = new Label("interp_jump");

        // TODO: directly patch a jump to the trace join point if found
        // mov rax, ptr
        // mov [rip - k], rax

        // Get a pointer to the branch target
        ptr(RAX, target);

        // If there is a trace join point, jump to it directly
        getField(RCX, RAX, target.traceJoin.sizeof, target.traceJoin.offsetof);
        as.instr(CMP, RCX, 0);
        as.instr(JE, interpJump);
        as.instr(JMP, RCX);
        
        // Make the interpreter jump to the target
        as.addInstr(interpJump);
        setField(R15, interp.target.sizeof, interp.target.offsetof, RAX);
        ptr(RAX, target.firstInstr);
        setField(R15, interp.ip.sizeof, interp.ip.offsetof, RAX);
        as.instr(JMP, traceExit);
    }
}

void gen_set_int32(ref CodeGenCtx ctx, IRInstr instr)
{
    // wsp[outSlot] = int32Val
    ctx.as.instr(MOV, X86Opnd(32, RBX, instr.outSlot * 8), instr.args[0].int32Val);

    // tsp[outSlot] = Type.INT32
    ctx.as.instr(MOV, X86Opnd(8, RBP, instr.outSlot), Type.INT32);
}

void gen_is_int32(ref CodeGenCtx ctx, IRInstr instr)
{
    // Need to check if tsp[a0] == Type.INT32
    // Load it, do cmp, do conditional move into out slot?

    // RAX = tsp[a0]
    ctx.as.instr(MOV, AL, X86Opnd(8, RBP, instr.args[0].localIdx));

    // CMP RAX, Type.INT32
    ctx.as.instr(CMP, AL, Type.INT32);

    ctx.as.instr(MOV, RAX, FALSE.int64Val);
    ctx.as.instr(MOV, RCX, TRUE.int64Val);
    ctx.as.instr(CMOVE, RAX, RCX);

    ctx.as.instr(MOV, X86Opnd(64, RBX, instr.outSlot * 8), RAX);

    // tsp[outSlot] = Type.CONST
    ctx.as.instr(MOV, X86Opnd(8, RBP, instr.outSlot), Type.CONST);
}

void gen_and_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // EAX = wsp[o0]
    // ECX = wsp[o1]
    ctx.as.instr(MOV, EAX, X86Opnd(32, RBX, instr.args[0].localIdx * 8));
    ctx.as.instr(MOV, ECX, X86Opnd(32, RBX, instr.args[1].localIdx * 8));

    // EAX = and EAX, ECX
    ctx.as.instr(AND, EAX, ECX);

    // wsp[outSlot] = EAX
    ctx.as.instr(MOV, X86Opnd(32, RBX, instr.outSlot * 8), EAX);

    // tsp[outSlot] = Type.INT32
    ctx.as.instr(MOV, X86Opnd(8, RBP, instr.outSlot), Type.INT32);
}

void gen_jump(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.jump(instr.targets[0]);
}

void gen_jump_bool(ref CodeGenCtx ctx, IRInstr instr)
{
    auto jumpStay = new Label("jump_stay");

    // EAX = wsp[a0]
    ctx.as.instr(MOV, AL, X86Opnd(8, RBX, instr.args[0].localIdx * 8));

    ctx.as.instr(CMP, AL, cast(int8_t)TRUE.int32Val);
    ctx.as.instr((instr.opcode == &JUMP_TRUE)? JNE:JE, jumpStay);

    ctx.jump(instr.targets[0]);

    ctx.as.addInstr(jumpStay);
}

void gen_get_global(ref CodeGenCtx ctx, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[1].int32Val;

    if (propIdx < 0)
    {
        defaultFn(ctx, instr);
        return;
    }

    // Get the global object pointer
    ctx.getField(RAX, R15, interp.globalObj.sizeof, interp.globalObj.offsetof);

    ctx.getField(RDI, RAX, 8, obj_ofs_word(interp.globalObj, propIdx));
    ctx.getField(SIL, RAX, 1, obj_ofs_type(interp.globalObj, propIdx));
        
    // wsp[outSlot] = RDI
    ctx.as.instr(MOV, X86Opnd(64, RBX, instr.outSlot * 8), RDI);

    // tsp[outSlot] = SIL
    ctx.as.instr(MOV, X86Opnd(8, RBP, instr.outSlot), SIL);
}

void gen_set_global(ref CodeGenCtx ctx, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[2].int32Val;

    if (propIdx < 0)
    {
        defaultFn(ctx, instr);
        return;
    }

    // Get the global object pointer
    ctx.getField(RAX, R15, interp.globalObj.sizeof, interp.globalObj.offsetof);

    // RDI = wsp[outSlot]
    ctx.as.instr(MOV, RDI, X86Opnd(64, RBX, instr.args[1].localIdx * 8));

    // SIL = tsp[outSlot]
    ctx.as.instr(MOV, SIL, X86Opnd(8, RBP, instr.args[1].localIdx));

    ctx.setField(RAX, 8, obj_ofs_word(interp.globalObj, propIdx), RDI);
    ctx.setField(RAX, 1, obj_ofs_type(interp.globalObj, propIdx), SIL);
}

void defaultFn(ref CodeGenCtx ctx, IRInstr instr)
{
    // Get the function corresponding to this instruction
    // alias void function(Interp interp, IRInstr instr) OpFn;
    // RDI: first argument (interp)
    // RSI: second argument (instr)
    auto opFn = instr.opcode.opFn;

    // Move the interpreter pointer into RDI
    ctx.as.instr(MOV, RDI, R15);
    
    // Load a pointer to the instruction in RSI
    ctx.ptr(RSI, instr);

    // Set the interpreter's IP
    ctx.as.instr(MOV, X86Opnd(64, RDI, ctx.interp.ip.offsetof), RSI);

    // Call the op function
    ctx.as.instr(MOV, RAX, X86Opnd(cast(void*)opFn));
    ctx.as.instr(jit.encodings.CALL, RAX);
}

alias void function(ref CodeGenCtx ctx, IRInstr instr) CodeGenFn;

CodeGenFn[Opcode*] codeGenFns;

static this()
{
    codeGenFns[&SET_INT32]  = &gen_set_int32;

    codeGenFns[&IS_INT32]   = &gen_is_int32;

    codeGenFns[&AND_I32]    = &gen_and_i32;

    codeGenFns[&JUMP]       = &gen_jump;

    codeGenFns[&JUMP_TRUE]  = &gen_jump_bool;
    codeGenFns[&JUMP_FALSE] = &gen_jump_bool;

    codeGenFns[&GET_GLOBAL] = &gen_get_global;
    codeGenFns[&SET_GLOBAL] = &gen_set_global;
}

