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
import interp.object;
import interp.string;
import jit.codeblock;
import jit.assembler;
import jit.x86;
import jit.encodings;

/**
Compile a basic block into executable machine code
*/
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

    // Assembler for out of line code (slow paths)
    auto ol = new Assembler();

    // Label at the trace join point (exported)
    auto traceJoin = new Label("trace_join", true);

    // Label at the end of the block
    auto traceExit = new Label("trace_exit");

    // Create a code generation context
    auto ctx = CodeGenCtx(interp, as, ol, traceExit, block);

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
    as.ptr(R15, interp);

    // Load the stack pointers into RBX and RBP
    as.getMember!("Interp", "wsp")(RBX, R15);
    as.getMember!("Interp", "tsp")(RBP, R15);

    // Join point of the tracelet
    as.addInstr(traceJoin);

    // Increment the block execution count
    as.ptr(RAX, block);
    as.instr(INC, X86Opnd(8*block.execCount.sizeof, RAX, block.execCount.offsetof));

    // While there is a block to generate code from
    while (ctx.nextBlock !is null)
    {
        auto curBlock = ctx.nextBlock;
        ctx.nextBlock = null;
        ctx.depth++;

        // For each instruction of the block
        for (auto instr = curBlock.firstInstr; instr !is null; instr = instr.next)
        {
            auto opcode = instr.opcode;

            // If there is a codegen function for this opcode
            if (opcode in codeGenFns)
            {
                // Call the code generation function for the opcode
                codeGenFns[opcode](ctx, instr);
            }
            else
            {
                // Use the default code generation function
                defaultFn(as, ctx, instr);
                //writefln("using default for: %s (%s)", instr.toString(), instr.block.fun.getName());
            }

            // If we know the instruction will definitely leave 
            // this block, stop the block compilation
            if (opcode.isBranch)
            {
                break;
            }
        }
    }

    // Block end, exit of tracelet
    as.addInstr(traceExit);

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(R15, RBX);
    as.setMember!("Interp", "tsp")(R15, RBP);

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

    // Append the out of line code to the rest
    as.append(ol);

    // Assemble the machine code
    auto codeBlock = as.assemble();

    if (opts.dumpasm)
    {
        writefln(
            "%s\nblock length: %s bytes\n", 
            as.toString(true),
            codeBlock.length
        );
    }

    //writefln("depth: %s", ctx.depth);

    // Return a pointer to the compiled code
    return codeBlock;
}

/**
Code generation context
*/
struct CodeGenCtx
{
    /// Interpreter object
    Interp interp;

    /// Assembler into which to generate code
    Assembler as;

    /// Assembler for out of line code
    Assembler ol;

    /// Trace exit label
    Label traceExit;

    /// Block from which to continue code generation
    IRBlock nextBlock;

    /// Depth of code generation (block chain length)
    size_t depth = 0;
}

void ptr(TPtr)(Assembler as, X86RegPtr destReg, TPtr ptr)
{
    as.instr(MOV, destReg, X86Opnd(cast(void*)ptr));
}

void getField(Assembler as, X86RegPtr dstReg, X86RegPtr baseReg, size_t fSize, size_t fOffset)
{
    as.instr(MOV, dstReg, X86Opnd(8*fSize, baseReg, cast(int32_t)fOffset));
}

void setField(Assembler as, X86RegPtr baseReg, size_t fSize, size_t fOffset, X86RegPtr srcReg)
{
    as.instr(MOV, X86Opnd(8*fSize, baseReg, cast(int32_t)fOffset), srcReg);
}

void getMember(string className, string fName)(Assembler as, X86RegPtr dstReg, X86RegPtr baseReg)
{
    // FIXME: hack temporarily required because of a DMD compiler bug
    mixin(className ~ " ptr = null;");
    mixin("auto fSize = ptr." ~ fName ~ ".sizeof;");
    mixin("auto fOffset = ptr." ~ fName ~ ".offsetof;");

    return as.getField(dstReg, baseReg, fSize, fOffset);
}

void setMember(string className, string fName)(Assembler as, X86RegPtr baseReg, X86RegPtr srcReg)
{
    mixin(className ~ " ptr = null;");
    mixin("auto fSize = ptr." ~ fName ~ ".sizeof;");
    mixin("auto fOffset = ptr." ~ fName ~ ".offsetof;");

    return as.setField(baseReg, fSize, fOffset, srcReg);
}

/// Read from the word stack
void getWord(Assembler as, X86RegPtr dstReg, LocalIdx idx)
{
    if (dstReg.type == X86Reg.GP)
        as.instr(MOV, dstReg, X86Opnd(dstReg.size, RBX, 8 * idx));
    else if (dstReg.type == X86Reg.XMM)
        as.instr(MOVSD, dstReg, X86Opnd(64, RBX, 8 * idx));
    else
        assert (false, "unsupported register type");
}

/// Read from the type stack
void getType(Assembler as, X86RegPtr dstReg, LocalIdx idx)
{
    as.instr(MOV, dstReg, X86Opnd(8, RBP, idx));
}

/// Write to the word stack
void setWord(Assembler as, LocalIdx idx, X86RegPtr srcReg)
{
    if (srcReg.type == X86Reg.GP)
        as.instr(MOV, X86Opnd(64, RBX, 8 * idx), srcReg);
    else if (srcReg.type == X86Reg.XMM)
        as.instr(MOVSD, X86Opnd(64, RBX, 8 * idx), srcReg);
    else
        assert (false, "unsupported register type");
}

// Write a constant to the word type
void setWord(Assembler as, LocalIdx idx, int32_t imm)
{
    as.instr(MOV, X86Opnd(64, RBX, 8 * idx), imm);
}

/// Write to the type stack
void setType(Assembler as, LocalIdx idx, X86RegPtr srcReg)
{
    as.instr(MOV, X86Opnd(8, RBP, idx), srcReg);
}

/// Write a constant to the type stack
void setType(Assembler as, LocalIdx idx, Type type)
{
    as.instr(MOV, X86Opnd(8, RBP, idx), type);
}

void jump(Assembler as, CodeGenCtx ctx, IRBlock target)
{
    auto interpJump = new Label("interp_jump");

    // TODO: directly patch a jump to the trace join point if found
    // mov rax, ptr
    // mov [rip - k], rax

    // Get a pointer to the branch target
    as.ptr(RAX, target);

    // If there is a trace join point, jump to it directly
    as.getMember!("IRBlock", "traceJoin")(RCX, RAX);
    as.instr(CMP, RCX, 0);
    as.instr(JE, interpJump);
    as.instr(JMP, RCX);
    
    // Make the interpreter jump to the target
    as.addInstr(interpJump);
    as.setMember!("Interp", "target")(R15, RAX);
    as.instr(JMP, ctx.traceExit);
}

void jump(Assembler as, CodeGenCtx ctx, X86RegPtr targetAddr)
{
    assert (targetAddr != RCX);

    auto interpJump = new Label("interp_jump");

    // If there is a trace join point, jump to it directly
    as.getMember!("IRBlock", "traceJoin")(RCX, targetAddr);
    as.instr(CMP, RCX, 0);
    as.instr(JE, interpJump);
    as.instr(JMP, RCX);
    
    // Make the interpreter jump to the target
    as.addInstr(interpJump);
    as.setMember!("Interp", "target")(R15, targetAddr);
    as.instr(JMP, ctx.traceExit);
}

void printUint(Assembler as, X86RegPtr reg)
{
    as.instr(PUSH, RAX);
    as.instr(PUSH, RCX);
    as.instr(PUSH, RDX);
    as.instr(PUSH, RSI);
    as.instr(PUSH, RDI);
    as.instr(PUSH, R8);
    as.instr(PUSH, R9);
    as.instr(PUSH, R10);
    as.instr(PUSH, R11);
    as.instr(PUSH, R11);

    as.instr(MOV, RDI, reg);
    as.ptr(RAX, &jit.jit.printUint);
    as.instr(jit.encodings.CALL, RAX);

    as.instr(POP, R11);
    as.instr(POP, R11);
    as.instr(POP, R10);
    as.instr(POP, R9);
    as.instr(POP, R8);
    as.instr(POP, RDI);
    as.instr(POP, RSI);
    as.instr(POP, RDX);
    as.instr(POP, RCX);
    as.instr(POP, RAX);
}

/**
Print an unsigned integer value. Callable from the JIT
*/
extern (C) void printUint(uint64_t v)
{
    writefln("%s", v);
}

void gen_set_true(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, cast(int8_t)TRUE.int64Val);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_set_false(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, cast(int8_t)FALSE.int64Val);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_set_undef(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, cast(int8_t)UNDEF.int64Val);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_set_null(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, cast(int8_t)NULL.int64Val);
    ctx.as.setType(instr.outSlot, Type.REFPTR);
}

void gen_set_int32(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.setWord(instr.outSlot, instr.args[0].int32Val);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_move(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(RDI, instr.args[0].localIdx);
    ctx.as.getType(SIL, instr.args[0].localIdx);
    ctx.as.setWord(instr.outSlot, RDI);
    ctx.as.setType(instr.outSlot, SIL);
}

void IsTypeOp(Type type)(ref CodeGenCtx ctx, IRInstr instr)
{
    // AL = tsp[a0]
    ctx.as.getType(AL, instr.args[0].localIdx);

    // CMP RAX, Type.FLOAT
    ctx.as.instr(CMP, AL, type);

    ctx.as.instr(MOV, RAX, FALSE.int64Val);
    ctx.as.instr(MOV, RCX, TRUE.int64Val);
    ctx.as.instr(CMOVE, RAX, RCX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

alias IsTypeOp!(Type.CONST) gen_is_const;
alias IsTypeOp!(Type.REFPTR) gen_is_refptr;
alias IsTypeOp!(Type.INT32) gen_is_int32;
alias IsTypeOp!(Type.FLOAT) gen_is_float;

void gen_add_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // EAX = wsp[a0]
    // ECX = wsp[a1]
    ctx.as.getWord(EAX, instr.args[0].localIdx);
    ctx.as.getWord(ECX, instr.args[1].localIdx);

    // EAX = add EAX, ECX
    ctx.as.instr(ADD, EAX, ECX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_mul_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // EAX = wsp[o0]
    // ECX = wsp[o1]
    ctx.as.getWord(EAX, instr.args[0].localIdx);
    ctx.as.getWord(ECX, instr.args[1].localIdx);

    // EAX = and EAX, ECX
    ctx.as.instr(IMUL, EAX, ECX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_and_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    // EAX = wsp[o0]
    // ECX = wsp[o1]
    ctx.as.getWord(EAX, instr.args[0].localIdx);
    ctx.as.getWord(ECX, instr.args[1].localIdx);

    // EAX = and EAX, ECX
    ctx.as.instr(AND, EAX, ECX);

    ctx.as.setWord(instr.outSlot, RAX);
    ctx.as.setType(instr.outSlot, Type.INT32);
}

void gen_add_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(ADDSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_sub_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(SUBSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_mul_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(MULSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_div_f64(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(XMM0, instr.args[0].localIdx);
    ctx.as.getWord(XMM1, instr.args[1].localIdx);

    ctx.as.instr(DIVSD, XMM0, XMM1);

    ctx.as.setWord(instr.outSlot, XMM0);
    ctx.as.setType(instr.outSlot, Type.FLOAT);
}

void gen_lt_i32(ref CodeGenCtx ctx, IRInstr instr)
{
    ctx.as.getWord(ECX, instr.args[0].localIdx);
    ctx.as.getWord(EDX, instr.args[1].localIdx);

    ctx.as.instr(CMP, ECX, EDX);

    ctx.as.instr(MOV, RDI, FALSE.int64Val);
    ctx.as.instr(MOV, RSI, TRUE.int64Val);
    ctx.as.instr(CMOVL, RDI, RSI);

    ctx.as.setWord(instr.outSlot, RDI);
    ctx.as.setType(instr.outSlot, Type.CONST);
}

void gen_add_i32_ovf(ref CodeGenCtx ctx, IRInstr instr)
{
    auto ovf = new Label("ovf");

    ctx.as.getWord(ECX, instr.args[0].localIdx);
    ctx.as.getWord(EDX, instr.args[1].localIdx);

    ctx.as.instr(ADD, ECX, EDX);
    ctx.as.instr(JO, ovf);

    ctx.as.setWord(instr.outSlot, RCX);
    ctx.as.setType(instr.outSlot, Type.INT32);

    ctx.as.jump(ctx, instr.target);

    // Out of line jump to the overflow target
    ctx.ol.addInstr(ovf);
    ctx.ol.jump(ctx, instr.excTarget);
}

void gen_jump(ref CodeGenCtx ctx, IRInstr instr)
{
    // Continue code generation in the jump target
    ctx.nextBlock = instr.target;

    //ctx.as.jump(ctx, instr.target);
}

void gen_if_true(ref CodeGenCtx ctx, IRInstr instr)
{
    /*
    writefln(
        "%s\n  %s:%s\n  %s", 
        instr.block.toString(), 
        instr.target.execCount, instr.excTarget.execCount,
        instr.block.fun.getName()
    );
    */    

    auto ifTrue = new Label("if_true");
    auto ifFalse = new Label("if_false");

    // AL = wsp[a0]
    ctx.as.getWord(AL, instr.args[0].localIdx);
    ctx.as.instr(CMP, AL, cast(int8_t)TRUE.int32Val);
  
    if (instr.target.execCount > 10 * instr.excTarget.execCount)
    {
        ctx.as.instr(JNE, ifFalse);
     
        // Continue code generation in the true branch directly
        ctx.nextBlock = instr.target;
        //ctx.as.jump(ctx, instr.target);

        // The false branch is out of line
        ctx.ol.addInstr(ifFalse);
        ctx.ol.jump(ctx, instr.excTarget);
    }

    else if (instr.excTarget.execCount > 10 * instr.target.execCount)
    {
        //writefln("match");
        //writefln("%s", instr.block.fun.getName());

        ctx.as.instr(JE, ifTrue);
     
        // Continue code generation in the false branch directly
        ctx.nextBlock = instr.excTarget;
        //ctx.as.jump(ctx, instr.target);

        // The true branch is out of line
        ctx.ol.addInstr(ifTrue);
        ctx.ol.jump(ctx, instr.target);
    }

    else
    {
        ctx.as.instr(JNE, ifFalse);
        ctx.as.jump(ctx, instr.target);

        ctx.as.addInstr(ifFalse);
        ctx.as.jump(ctx, instr.excTarget);
    }
}

void gen_get_global(ref CodeGenCtx ctx, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[1].int32Val;

    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, instr);
        return;
    }

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(RAX, R15);

    ctx.as.getField(RDI, RAX, 8, obj_ofs_word(interp.globalObj, propIdx));
    ctx.as.getField(SIL, RAX, 1, obj_ofs_type(interp.globalObj, propIdx));

    ctx.as.setWord(instr.outSlot, RDI);
    ctx.as.setType(instr.outSlot, SIL);
}

void gen_set_global(ref CodeGenCtx ctx, IRInstr instr)
{
    auto interp = ctx.interp;

    // Cached property index
    auto propIdx = instr.args[2].int32Val;

    if (propIdx < 0)
    {
        defaultFn(ctx.as, ctx, instr);
        return;
    }

    // Get the global object pointer
    ctx.as.getMember!("Interp", "globalObj")(RAX, R15);

    ctx.as.getWord(RDI, instr.args[1].localIdx);
    ctx.as.getType(SIL, instr.args[1].localIdx);

    ctx.as.setField(RAX, 8, obj_ofs_word(interp.globalObj, propIdx), RDI);
    ctx.as.setField(RAX, 1, obj_ofs_type(interp.globalObj, propIdx), SIL);
}

void gen_call(ref CodeGenCtx ctx, IRInstr instr)
{
    // Label for the bailout to interpreter cases
    auto bailout = new Label("call_bailout");

    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;
    auto numArgs = instr.args.length - 2;

    // Try to find the function we are calling
    refptr closPtr = null;    
    for (auto curInstr = instr.prev; curInstr !is null; curInstr = curInstr.prev)
    {
        // If we are calling a global function
        if (curInstr.outSlot == closIdx && curInstr.opcode == &GET_GLOBAL)
        {
            auto propName = curInstr.args[0].stringVal;

            // Lookup the global function
            ValuePair val = getProp(
                ctx.interp,
                ctx.interp.globalObj,
                getString(ctx.interp, propName)
            );

            if (val.type == Type.REFPTR && valIsLayout(val.word, LAYOUT_CLOS))
                closPtr = val.word.ptrVal;

            break;
        }
    }

    // If the global closure was not found
    if (closPtr is null)
    {
        // Call the interpreter call instruction
        defaultFn(ctx.as, ctx, instr);
        return;
    }

    // Get a pointer to the IR function
    auto fun = cast(IRFunction)clos_get_fptr(closPtr);

    // If the function is not compiled or the argument count doesn't match
    if (fun.entryBlock is null || numArgs != fun.numParams)
    {
        // Call the interpreter call instruction
        defaultFn(ctx.as, ctx, instr);
        return;
    }

    //writefln("%s\n  %s %s %s", instr.block.toString(), fun.getName(), fun.numParams, numArgs);

    // Get the closure word
    ctx.as.getWord(RCX, closIdx);

    // If this is not the closure we expect, bailout to the interpreter
    ctx.as.ptr(RAX, closPtr);
    ctx.as.instr(CMP, RAX, RCX);
    ctx.as.instr(JNE, bailout);

    auto numPush = fun.numLocals;
    auto numVars = fun.numLocals - NUM_HIDDEN_ARGS - fun.numParams;

    //writefln("numPush: %s, numVars: %s", numPush, numVars);

    // Push space for the callee arguments and locals
    ctx.as.instr(SUB, RBX, 8 * numPush);
    ctx.as.instr(SUB, RBP, numPush);

    // Copy the function arguments in reverse order
    for (size_t i = 0; i < numArgs; ++i)
    {
        auto argSlot = instr.args[$-(1+i)].localIdx /*+ (argDiff + i)*/;

        ctx.as.getWord(RDI, argSlot + numPush); 
        ctx.as.getType(SIL, argSlot + numPush);

        auto dstIdx = (numArgs - i - 1) + numVars + NUM_HIDDEN_ARGS;

        ctx.as.setWord(cast(LocalIdx)dstIdx, RDI);
        ctx.as.setType(cast(LocalIdx)dstIdx, SIL);
    }

    // Write the argument count
    ctx.as.setWord(cast(LocalIdx)(numVars + 3), cast(int32_t)numArgs);
    ctx.as.setType(cast(LocalIdx)(numVars + 3), Type.INT32);

    // Copy the "this" argument
    ctx.as.getWord(RDI, thisIdx + numPush);
    ctx.as.getType(SIL, thisIdx + numPush);
    ctx.as.setWord(cast(LocalIdx)(numVars + 2), RDI);
    ctx.as.setType(cast(LocalIdx)(numVars + 2), SIL);

    // Write the closure argument
    ctx.as.setWord(cast(LocalIdx)(numVars + 1), RCX);
    ctx.as.setType(cast(LocalIdx)(numVars + 1), Type.REFPTR);

    // Write the return address (caller instruction)
    ctx.as.ptr(RAX, instr);
    ctx.as.setWord(cast(LocalIdx)(numVars + 0), RAX);
    ctx.as.setType(cast(LocalIdx)(numVars + 0), Type.INSPTR);

    // Initialize the variables to undefined
    for (LocalIdx i = 0; i < numVars; ++i)
    {
        ctx.as.instr(MOV, RAX, UNDEF.int64Val);
        ctx.as.setWord(i, RAX);
        ctx.as.setType(i, Type.CONST);
    }

    // TODO: evaluate when this is acceptable
    // Continue code generation in the function entry block    
    ctx.nextBlock = fun.entryBlock;

    // Jump to the function entry
    //ctx.as.ptr(RAX, fun.entryBlock);
    //ctx.as.jump(ctx, RAX);

    // Bailout to the interpreter (out of line)
    ctx.ol.addInstr(bailout);

    // Call the interpreter call instruction
    // Fallback to interpreter execution
    defaultFn(ctx.ol, ctx, instr);

    // Exit the trace
    ctx.ol.instr(JMP, ctx.traceExit);
}

void gen_ret(ref CodeGenCtx ctx, IRInstr instr)
{
    //writefln("compiling ret from %s", instr.block.fun.getName());

    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.block.fun.raSlot;
    auto argcSlot  = instr.block.fun.argcSlot;
    auto thisSlot  = instr.block.fun.thisSlot;
    auto numParams = instr.block.fun.params.length;
    auto numLocals = instr.block.fun.numLocals;

    // Label for returns from a new instruction
    auto retFromNew = new Label("ret_new");

    // Label for the end of the return logic
    auto retDone = new Label("ret_done");

    // Label for the stack locals popping
    auto popLocals = new Label("ret_pop");

    // Get the return value
    // RDI = wRet
    // SIL = tRet
    ctx.as.getWord(RDI, retSlot);
    ctx.as.getType(SIL, retSlot);

    // RAX = calling instruction
    ctx.as.getWord(RAX, raSlot);

    // RCX = opcode of the calling instruction
    ctx.as.getMember!("IRInstr", "opcode")(RCX, RAX);

    // If opcode == &CALL_NEW, jump to newRet
    ctx.as.ptr(RDX, &CALL_NEW);
    ctx.as.instr(CMP, RCX, RDX);
    ctx.as.instr(JE, retFromNew);

    // Pop the stack locals
    ctx.as.addInstr(popLocals);

    // EDX = number of stack slots to pop
    ctx.as.getWord(EDX, argcSlot);
    ctx.as.instr(SUB, EDX, numParams);
    ctx.as.instr(MOV, ECX, 0);
    ctx.as.instr(CMP, EDX, 0);
    ctx.as.instr(CMOVL, EDX, ECX);
    ctx.as.instr(ADD, EDX, numLocals);

    // Pop all local stack slots and arguments
    ctx.as.instr(ADD, RBP, RDX);
    ctx.as.instr(SHL, RDX, 3);
    ctx.as.instr(ADD, RBX, RDX);

    // ECX = output slot of the calling instruction
    ctx.as.getMember!("IRInstr", "outSlot")(ECX, RAX);

    // If the call instruction has no output slot, we are done
    ctx.as.instr(MOV, EDX, NULL_LOCAL);
    ctx.as.instr(CMP, ECX, EDX);
    ctx.as.instr(JE, retDone);

    // Set the return value
    ctx.as.instr(MOV, X86Opnd( 8, RBP, 0, RCX, 1), SIL);
    ctx.as.instr(MOV, X86Opnd(64, RBX, 0, RCX, 8), RDI);

    // Return done
    ctx.as.addInstr(retDone);

    // RCX = call continuation target
    ctx.as.getMember!("IRInstr", "target")(RDX, RAX);

    // Jump to the call continuation
    ctx.as.jump(ctx, RDX);

    // Return from new case
    ctx.as.addInstr(retFromNew);

    // If the return value is not undefined, return that value
    ctx.as.instr(CMP, SIL, Type.CONST);
    ctx.as.instr(JNE, popLocals);
    ctx.as.instr(CMP, DIL, cast(int8_t)UNDEF.int32Val);
    ctx.as.instr(JNE, popLocals);

    // Use the this value as the return value
    ctx.as.getWord(RDI, thisSlot);
    ctx.as.getType(SIL, thisSlot);
    ctx.as.instr(JMP, popLocals);
}

void defaultFn(Assembler as, ref CodeGenCtx ctx, IRInstr instr)
{
    // Get the function corresponding to this instruction
    // alias void function(Interp interp, IRInstr instr) OpFn;
    // RDI: first argument (interp)
    // RSI: second argument (instr)
    auto opFn = instr.opcode.opFn;

    // Move the interpreter pointer into RDI
    as.instr(MOV, RDI, R15);
    
    // Load a pointer to the instruction in RSI
    as.ptr(RSI, instr);

    // TODO: only necessary if we may alloc or branch?
    // Set the interpreter's IP
    as.setMember!("Interp", "ip")(RDI, RSI);

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(R15, RBX);
    as.setMember!("Interp", "tsp")(R15, RBP);

    // Call the op function
    as.instr(MOV, RAX, X86Opnd(cast(void*)opFn));
    as.instr(jit.encodings.CALL, RAX);

    // Load the stack pointers into RBX and RBP
    // if the instruction may have changed them
    if (instr.opcode.isBranch == true)
    {
        as.getMember!("Interp", "wsp")(RBX, R15);
        as.getMember!("Interp", "tsp")(RBP, R15);
    }
}

alias void function(ref CodeGenCtx ctx, IRInstr instr) CodeGenFn;

CodeGenFn[Opcode*] codeGenFns;

static this()
{
    codeGenFns[&SET_TRUE]       = &gen_set_true;
    codeGenFns[&SET_FALSE]      = &gen_set_false;
    codeGenFns[&SET_UNDEF]      = &gen_set_undef;
    codeGenFns[&SET_NULL]       = &gen_set_null;
    codeGenFns[&SET_INT32]      = &gen_set_int32;

    codeGenFns[&IS_CONST]       = &gen_is_const;
    codeGenFns[&IS_REFPTR]      = &gen_is_refptr;
    codeGenFns[&IS_INT32]       = &gen_is_int32;
    codeGenFns[&IS_FLOAT]       = &gen_is_float;

    codeGenFns[&MOVE]           = &gen_move;

    codeGenFns[&ADD_I32]        = &gen_add_i32;
    codeGenFns[&MUL_I32]        = &gen_mul_i32;
    codeGenFns[&AND_I32]        = &gen_and_i32;

    codeGenFns[&ADD_F64]        = &gen_add_f64;
    codeGenFns[&SUB_F64]        = &gen_sub_f64;
    codeGenFns[&MUL_F64]        = &gen_mul_f64;
    codeGenFns[&DIV_F64]        = &gen_div_f64;

    codeGenFns[&LT_I32]         = &gen_lt_i32;

    codeGenFns[&ADD_I32_OVF]    = &gen_add_i32_ovf;

    codeGenFns[&JUMP]           = &gen_jump;

    codeGenFns[&IF_TRUE]        = &gen_if_true;

    codeGenFns[&ir.ir.CALL]     = &gen_call;
    codeGenFns[&ir.ir.RET]      = &gen_ret;

    codeGenFns[&GET_GLOBAL]     = &gen_get_global;
    codeGenFns[&SET_GLOBAL]     = &gen_set_global;
}

