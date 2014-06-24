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

module jit.util;

import std.stdio;
import std.string;
import std.array;
import std.stdint;
import std.conv;
import std.typecons;
import options;
import ir.ir;
import runtime.vm;
import runtime.object;
import jit.codeblock;
import jit.x86;
import jit.jit;

/**
Create a relative 32-bit jump to a code fragment
*/
void writeJcc32Ref(string mnem, opcode...)(
    CodeBlock as,
    VM vm,
    CodeFragment frag,
    size_t targetIdx = size_t.max
)
{
    // Write an ASM comment
    if (opts.jit_genasm)
        as.writeASM(mnem, frag.getName);

    as.writeBytes(opcode);

    vm.addFragRef(as.getWritePos(), 32, frag, targetIdx);

    as.writeInt(0, 32);
}

/// 32-bit relative jumps with fragment references
alias writeJcc32Ref!("ja"  , 0x0F, 0x87) ja32Ref;
alias writeJcc32Ref!("jae" , 0x0F, 0x83) jae32Ref;
alias writeJcc32Ref!("jb"  , 0x0F, 0x82) jb32Ref;
alias writeJcc32Ref!("jbe" , 0x0F, 0x86) jbe32Ref;
alias writeJcc32Ref!("jc"  , 0x0F, 0x82) jc32Ref;
alias writeJcc32Ref!("je"  , 0x0F, 0x84) je32Ref;
alias writeJcc32Ref!("jg"  , 0x0F, 0x8F) jg32Ref;
alias writeJcc32Ref!("jge" , 0x0F, 0x8D) jge32Ref;
alias writeJcc32Ref!("jl"  , 0x0F, 0x8C) jl32Ref;
alias writeJcc32Ref!("jle" , 0x0F, 0x8E) jle32Ref;
alias writeJcc32Ref!("jna" , 0x0F, 0x86) jna32Ref;
alias writeJcc32Ref!("jnae", 0x0F, 0x82) jnae32Ref;
alias writeJcc32Ref!("jnb" , 0x0F, 0x83) jnb32Ref;
alias writeJcc32Ref!("jnbe", 0x0F, 0x87) jnbe32Ref;
alias writeJcc32Ref!("jnc" , 0x0F, 0x83) jnc32Ref;
alias writeJcc32Ref!("jne" , 0x0F, 0x85) jne32Ref;
alias writeJcc32Ref!("jng" , 0x0F, 0x8E) jng32Ref;
alias writeJcc32Ref!("jnge", 0x0F, 0x8C) jnge32Ref;
alias writeJcc32Ref!("jnl" , 0x0F, 0x8D) jnl32Ref;
alias writeJcc32Ref!("jnle", 0x0F, 0x8F) jnle32Ref;
alias writeJcc32Ref!("jno" , 0x0F, 0x81) jno32Ref;
alias writeJcc32Ref!("jnp" , 0x0F, 0x8b) jnp32Ref;
alias writeJcc32Ref!("jns" , 0x0F, 0x89) jns32Ref;
alias writeJcc32Ref!("jnz" , 0x0F, 0x85) jnz32Ref;
alias writeJcc32Ref!("jo"  , 0x0F, 0x80) jo32Ref;
alias writeJcc32Ref!("jp"  , 0x0F, 0x8A) jp32Ref;
alias writeJcc32Ref!("jpe" , 0x0F, 0x8A) jpe32Ref;
alias writeJcc32Ref!("jpo" , 0x0F, 0x8B) jpo32Ref;
alias writeJcc32Ref!("js"  , 0x0F, 0x88) js32Ref;
alias writeJcc32Ref!("jz"  , 0x0F, 0x84) jz32Ref;
alias writeJcc32Ref!("jmp" , 0xE9) jmp32Ref;

/**
Move an absolute reference to a fragment's address into a register
*/
void movAbsRef(
    CodeBlock as,
    VM vm,
    X86Reg dstReg,
    CodeFragment frag,
    size_t targetIdx = size_t.max
)
{
    if (opts.jit_genasm)
        as.writeASM("mov", dstReg, frag.getName);

    as.mov(dstReg.opnd(64), X86Opnd(uint64_t.max));
    vm.addFragRef(as.getWritePos() - 8, 64, frag, targetIdx);
}

/// Load a pointer constant into a register
void ptr(TPtr)(CodeBlock as, X86Reg dstReg, TPtr ptr)
{
    as.mov(X86Opnd(dstReg), X86Opnd(X86Imm(cast(void*)ptr)));
}

/// Increment a global JIT stat counter variable
void incStatCnt(CodeBlock as, ulong* pCntVar, X86Reg scrReg, ulong incVal = 1)
{
    if (!opts.stats)
        return;

    as.ptr(scrReg, pCntVar);

    as.add(X86Opnd(8 * ulong.sizeof, scrReg), X86Opnd(incVal));
}

void getField(CodeBlock as, X86Reg dstReg, X86Reg baseReg, size_t fOffset)
{
    assert (dstReg.type is X86Reg.GP);
    as.mov(X86Opnd(dstReg), X86Opnd(dstReg.size, baseReg, cast(int32_t)fOffset));
}

void setField(CodeBlock as, X86Reg baseReg, size_t fOffset, X86Reg srcReg)
{
    assert (srcReg.type is X86Reg.GP);
    as.mov(X86Opnd(srcReg.size, baseReg, cast(int32_t)fOffset), X86Opnd(srcReg));
}

X86Opnd memberOpnd(string fName)(X86Reg baseReg)
{
    const auto elems = split(fName, ".");

    size_t fOffset;
    static if (elems.length is 3)
    {
        mixin(format(
            "const e1Type = typeof(%s.%s).stringof;", elems[0], elems[1]
        ));

        mixin(format(
            "fOffset = %s.%s.offsetof + %s.%s.offsetof;", 
            elems[0], elems[1],
            e1Type, elems[2]
        ));
    }
    else if (elems.length is 2)
    {
        mixin(format(
            "fOffset = %s.%s.offsetof;", 
            elems[0], elems[1]
        ));
    }
    else
    {
        assert (false);
    }

    mixin("auto fSize = " ~ fName ~ ".sizeof;");

    return X86Opnd(fSize * 8, baseReg, cast(int32_t)fOffset);
}

void getMember(string fName)(CodeBlock as, X86Reg dstReg, X86Reg baseReg)
{
    as.mov(X86Opnd(dstReg), memberOpnd!fName(baseReg));
}

void setMember(string fName)(CodeBlock as, X86Reg baseReg, X86Reg srcReg)
{
    as.mov(memberOpnd!fName(baseReg), X86Opnd(srcReg));
}

// Get a word stack operand
auto wordStackOpnd(int32_t idx, size_t numBits = 64)
{
    return X86Opnd(numBits, wspReg, cast(int32_t)Word.sizeof * idx);
}

// Get a type stack operand
auto typeStackOpnd(int32_t idx)
{
    return X86Opnd(8, tspReg, cast(int32_t)Type.sizeof * idx);
}

/// Read from the word stack
void getWord(CodeBlock as, X86Reg dstReg, int32_t idx)
{
    if (dstReg.type is X86Reg.GP)
        as.mov(X86Opnd(dstReg), wordStackOpnd(idx, dstReg.size));
    else if (dstReg.type is X86Reg.XMM)
        as.movsd(X86Opnd(dstReg), wordStackOpnd(idx, 64));
    else
        assert (false, "unsupported register type");
}

/// Read from the type stack
void getType(CodeBlock as, X86Reg dstReg, int32_t idx)
{
    as.mov(X86Opnd(dstReg), typeStackOpnd(idx));
}

/// Write to the word stack
void setWord(CodeBlock as, int32_t idx, X86Opnd src)
{
    auto memOpnd = wordStackOpnd(idx);

    if (src.isGPR)
        as.mov(memOpnd, src);
    else if (src.isXMM)
        as.movsd(memOpnd, src);
    else if (src.isImm)
        as.mov(memOpnd, src);
    else
        assert (false, "unsupported src operand type");
}

// Write a constant to the word type
void setWord(CodeBlock as, int32_t idx, int32_t imm)
{
    as.mov(wordStackOpnd(idx), X86Opnd(imm));
}

/// Write to the type stack
void setType(CodeBlock as, int32_t idx, X86Opnd srcOpnd)
{
    as.mov(typeStackOpnd(idx), srcOpnd);
}

/// Write a constant to the type stack
void setType(CodeBlock as, int32_t idx, Type type)
{
    as.mov(typeStackOpnd(idx), X86Opnd(type));
}

/// Store/save the JIT state register
void saveJITRegs(CodeBlock as)
{
    // Save word and type stack pointers on the VM object
    as.setMember!("VM.wsp")(vmReg, wspReg);
    as.setMember!("VM.tsp")(vmReg, tspReg);

    // Push the VM register on the stack
    as.push(vmReg);
    as.push(vmReg);
}

// Load/restore the JIT state registers
void loadJITRegs(CodeBlock as)
{
    // Pop the VM register from the stack
    as.pop(vmReg);
    as.pop(vmReg);

    // Load the word and type stack pointers from the VM object
    as.getMember!("VM.wsp")(wspReg, vmReg);
    as.getMember!("VM.tsp")(tspReg, vmReg);
}

/// Save the allocatable registers to the VM register save space
void saveAllocRegs(CodeBlock as)
{
    as.getMember!("VM.regSave")(scrRegs[1], vmReg);
    foreach (uint regIdx, reg; allocRegs)
    {
        //as.printStr("save " ~ reg.toString);
        //as.printUint(reg.opnd);

        auto memOpnd = X86Opnd(64, scrRegs[1], 8 * regIdx);
        as.mov(memOpnd, reg.opnd);
    }
}

/// Restore the allocatable registers from the VM register save space
void loadAllocRegs(CodeBlock as)
{
    as.getMember!("VM.regSave")(scrRegs[1], vmReg);
    foreach (uint regIdx, reg; allocRegs)
    {
        auto memOpnd = X86Opnd(64, scrRegs[1], 8 * regIdx);
        as.mov(reg.opnd, memOpnd);

        //as.printStr("restore " ~ reg.toString);
        //as.printUint(reg.opnd);
    }
}

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
    as.pushfq();
}

/// Restore caller-save registers from the after before a C call
void popRegs(CodeBlock as)
{
    as.popfq();
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

void printPtr(CodeBlock as, X86Opnd opnd)
{
    extern (C) void printPtrFn(uint64_t v)
    {
        writefln("%X", v);
    }

    as.pushRegs();

    as.mov(cargRegs[0].opnd(64), opnd);

    // Call the print function
    as.ptr(scrRegs[0], &printPtrFn);
    as.call(scrRegs[0]);

    as.popRegs();
}

void printUint(CodeBlock as, X86Opnd opnd)
{
    extern (C) void printUintFn(uint64_t v)
    {
        writefln("%s", v);
    }

    size_t opndSz;
    if (opnd.isImm)
        opndSz = 64;
    else if (opnd.isGPR)
        opndSz = opnd.reg.size;
    else if (opnd.isMem)
        opndSz = opnd.mem.size;
    else
        assert (false, "invalid opnd in printUint: " ~ opnd.toString);

    as.pushRegs();

    if (opndSz is 32)
        as.mov(cargRegs[0].opnd(32), opnd);
    else if (opndSz < 32)
        as.movzx(cargRegs[0].opnd(64), opnd);
    else
        as.mov(cargRegs[0].opnd(opndSz), opnd);

    // Call the print function
    as.ptr(scrRegs[0], &printUintFn);
    as.call(scrRegs[0]);

    as.popRegs();
}

void printInt(CodeBlock as, X86Opnd opnd)
{
    extern (C) void printIntFn(int64_t v)
    {
        writefln("%s", v);
    }

    size_t opndSz;
    if (opnd.isImm)
        opndSz = 64;
    else if (opnd.isGPR)
        opndSz = opnd.reg.size;
    else if (opnd.isMem)
        opndSz = opnd.mem.size;
    else
        assert (false);

    as.pushRegs();

    if (opndSz < 64)
        as.movsx(cargRegs[0].opnd(64), opnd);
    else
        as.mov(cargRegs[0].opnd(64), opnd);

    // Call the print function
    as.ptr(scrRegs[0], &printIntFn);
    as.call(scrRegs[0]);

    as.popRegs();
}

void printStr(CodeBlock as, string str)
{
    extern (C) static void printStrFn(char* pStr)
    {
        printf("%s\n", pStr);
    }

    as.comment("printStr(\"" ~ str ~ "\")");

    as.pushRegs();

    // Load the string address and jump over the string data
    as.lea(cargRegs[0], X86Mem(8, RIP, 5));
    as.jmp32(cast(int32_t)str.length + 1);

    // Write the string chars and a null terminator
    foreach (ch; str)
        as.writeInt(cast(uint)ch, 8);
    as.writeInt(0, 8);

    as.ptr(scrRegs[0], &printStrFn);
    as.call(scrRegs[0].opnd(64));

    as.popRegs();
}

void printStack(CodeBlock as, VM vm, IRInstr curInstr)
{
    extern (C) static void printStackFn(VM vm, IRInstr instr)
    {
        vm.setCurInstr(instr);

        //writeln(vm.stackSize);

        vm.visitStack(
            delegate void(
                IRFunction fun,
                Word* wsp,
                Type* tsp,
                size_t depth,
                size_t frameSize,
                IRInstr callInstr
            )
            {
                writeln(fun.getName);
            }
        );

        vm.setCurInstr(null);
    }

    as.comment("printStack()");

    as.pushRegs();
    as.saveJITRegs();

    as.mov(cargRegs[0].opnd, vmReg.opnd);
    as.ptr(cargRegs[1], curInstr);

    as.ptr(scrRegs[0], &printStackFn);
    as.call(scrRegs[0].opnd(64));

    as.loadJITRegs();
    as.popRegs();
}

