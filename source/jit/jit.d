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
import options;
import ir.ir;
import ir.livevars;
import interp.interp;
import interp.layout;
import interp.object;
import interp.string;
import interp.gc;
import jit.assembler;
import jit.x86;
import jit.moves;
import jit.ops;

/**
Context in which code is being compiled
*/
class CodeGenCtx
{
    /// Parent context (if inlined)
    CodeGenCtx parent = null;

    /// Call site inlined at (if inlined)
    IRInstr inlineSite = null;

    /// Number of extra locals (if inlined)
    size_t extraLocals = 0;

    /// Function this code belongs to
    IRFunction fun;
}

// TODO: revise
/// Register allocation information value
alias uint16_t AllocState;
const AllocState RA_STACK = (1 << 7);
const AllocState RA_GPREG = (1 << 6);
const AllocState RA_CONST = (1 << 5);
const AllocState RA_REG_MASK = (0x0F);

// TODO: revise
// Type information value
alias uint16_t TypeState;
const TypeState TF_KNOWN = (1 << 7);
const TypeState TF_SYNC = (1 << 6);
const TypeState TF_BOOL_TRUE = (1 << 5);
const TypeState TF_BOOL_FALSE = (1 << 4);
const TypeState TF_TYPE_MASK = (0xF);

/**
Current code generation state. This includes register
allocation state and known type information.
*/
class CodeGenState
{
    /// Code generation context object
    CodeGenCtx ctx;

    /// Live value to register/slot mapping
    private AllocState[IRDstValue] allocMap;

    // Live value to known type info mapping
    private TypeState[IRDstValue] typeMap;

    /// Map of general-purpose registers to values
    /// The value is null if a register is free
    private IRDstValue[] gpRegMap;

    /// Map of stack slots to values
    private IRDstValue[LocalIdx] slotMap;

    // TODO
    /// List of delayed value writes

    // TODO
    /// List of delayed type tag writes

    /// Constructor for a default/entry code generation state
    this(IRFunction fun)
    {
        // All registers are initially free
        gpRegMap.length = 16;
        for (size_t i = 0; i < gpRegMap.length; ++i)
            gpRegMap[i] = null;
    }

    /// Copy constructor
    this(CodeGenState that)
    {
        // TODO
        this.allocMap = that.allocMap.dup;
        this.typeMap = that.typeMap.dup;
        this.gpRegMap = that.gpRegMap.dup;
        this.slotMap = that.slotMap.dup;
    }
}

/**
Basic-block version
*/
class BlockVersion
{
    static const size_t MAX_TARGETS = 2;

    /// Associated code generation state
    CodeGenState state;


    // TODO: code indices





}









/*
/// Load a pointer constant into a register
void ptr(TPtr)(Assembler as, X86Reg destReg, TPtr ptr)
{
    as.instr(MOV, destReg, new X86Imm(cast(void*)ptr));
}

/// Increment a global JIT stat counter variable
void incStatCnt(Assembler as, ulong* pCntVar, X86Reg scrReg)
{
    if (!opts.stats)
        return;

    as.ptr(scrReg, pCntVar);

    as.instr(INC, new X86Mem(8 * ulong.sizeof, RAX));
}

void getField(Assembler as, X86Reg dstReg, X86Reg baseReg, size_t fSize, size_t fOffset)
{
    as.instr(MOV, dstReg, new X86Mem(8*fSize, baseReg, cast(int32_t)fOffset));
}

void setField(Assembler as, X86Reg baseReg, size_t fSize, size_t fOffset, X86Reg srcReg)
{
    as.instr(MOV, new X86Mem(8*fSize, baseReg, cast(int32_t)fOffset), srcReg);
}

void getMember(string className, string fName)(Assembler as, X86Reg dstReg, X86Reg baseReg)
{
    mixin("auto fSize = " ~ className ~ "." ~ fName ~ ".sizeof;");
    mixin("auto fOffset = " ~ className ~ "." ~ fName ~ ".offsetof;");

    return as.getField(dstReg, baseReg, fSize, fOffset);
}

void setMember(string className, string fName)(Assembler as, X86Reg baseReg, X86Reg srcReg)
{
    mixin("auto fSize = " ~ className ~ "." ~ fName ~ ".sizeof;");
    mixin("auto fOffset = " ~ className ~ "." ~ fName ~ ".offsetof;");

    return as.setField(baseReg, fSize, fOffset, srcReg);
}

/// Read from the word stack
void getWord(Assembler as, X86Reg dstReg, int32_t idx)
{
    if (dstReg.type == X86Reg.GP)
        as.instr(MOV, dstReg, new X86Mem(dstReg.size, wspReg, 8 * idx));
    else if (dstReg.type == X86Reg.XMM)
        as.instr(MOVSD, dstReg, new X86Mem(64, wspReg, 8 * idx));
    else
        assert (false, "unsupported register type");
}

/// Read from the type stack
void getType(Assembler as, X86Reg dstReg, int32_t idx)
{
    as.instr(MOV, dstReg, new X86Mem(8, tspReg, idx));
}

/// Write to the word stack
void setWord(Assembler as, int32_t idx, X86Opnd src)
{
    auto memOpnd = new X86Mem(64, wspReg, 8 * idx);

    if (auto srcReg = cast(X86Reg)src)
    {
        if (srcReg.type == X86Reg.GP)
            as.instr(MOV, memOpnd, srcReg);
        else if (srcReg.type == X86Reg.XMM)
            as.instr(MOVSD, memOpnd, srcReg);
        else
            assert (false, "unsupported register type");
    }
    else if (auto srcImm = cast(X86Imm)src)
    {
        as.instr(MOV, memOpnd, srcImm);
    }
    else
    {
        assert (false, "unsupported src operand type");
    }
}

// Write a constant to the word type
void setWord(Assembler as, int32_t idx, int32_t imm)
{
    as.instr(MOV, new X86Mem(64, wspReg, 8 * idx), imm);
}

/// Write to the type stack
void setType(Assembler as, int32_t idx, X86Opnd srcOpnd)
{
    as.instr(MOV, new X86Mem(8, tspReg, idx), srcOpnd);
}

/// Write a constant to the type stack
void setType(Assembler as, int32_t idx, Type type)
{
    as.instr(MOV, new X86Mem(8, tspReg, idx), type);
}

/// Save caller-save registers on the stack before a C call
void pushRegs(Assembler as)
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
}

/// Restore caller-save registers from the after before a C call
void popRegs(Assembler as)
{
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
*/

/*
void checkVal(Assembler as, X86Opnd wordOpnd, X86Opnd typeOpnd, string errorStr)
{
    as.pushRegs();

    auto STR_DATA = new Label("STR_DATA");
    auto AFTER_STR = new Label("AFTER_STR");

    as.instr(JMP, AFTER_STR);
    as.addInstr(STR_DATA);
    foreach (ch; errorStr)
        as.addInstr(new IntData(cast(uint)ch, 8));    
    as.addInstr(new IntData(0, 8));
    as.addInstr(AFTER_STR);

    as.instr(MOV, cargRegs[2].ofSize(8), typeOpnd);
    as.instr(MOV, cargRegs[1], wordOpnd);
    as.instr(MOV, cargRegs[0], interpReg);
    as.instr(LEA, cargRegs[3], new X86IPRel(8, STR_DATA));

    auto checkFn = &checkValFn;
    as.ptr(scrRegs64[0], checkFn);
    as.instr(jit.encodings.CALL, scrRegs64[0]);

    as.popRegs();
}
*/

extern (C) void checkValFn(Interp interp, Word word, Type type, char* errorStr)
{
    if (type != Type.REFPTR)
        return;

    if (interp.inFromSpace(word.ptrVal) is false)
    {
        writefln(
            "pointer not in from-space: %s\n%s",
            word.ptrVal,
            to!string(errorStr)
        );
    }
}

/*
void printUint(Assembler as, X86Opnd opnd)
{
    assert (
        opnd !is null,
        "invalid operand in printUint"
    );

    as.pushRegs();

    as.instr(MOV, cargRegs[0], opnd);

    // Call the print function
    alias extern (C) void function(uint64_t) PrintUintFn;
    PrintUintFn printUintFn = &printUint;
    as.ptr(RAX, printUintFn);
    as.instr(jit.encodings.CALL, RAX);

    as.popRegs();
}
*/

/**
Print an unsigned integer value. Callable from the JIT
*/
extern (C) void printUint(uint64_t v)
{
    writefln("%s", v);
}

/*
void printStr(Assembler as, string str)
{
    as.comment("printStr(\"" ~ str ~ "\")");

    as.pushRegs();

    auto STR_DATA = new Label("STR_DATA");
    auto AFTER_STR = new Label("AFTER_STR");

    as.instr(JMP, AFTER_STR);
    as.addInstr(STR_DATA);
    foreach (ch; str)
        as.addInstr(new IntData(cast(uint)ch, 8));    
    as.addInstr(new IntData(0, 8));
    as.addInstr(AFTER_STR);

    as.instr(LEA, cargRegs[0], new X86IPRel(8, STR_DATA));

    alias extern (C) void function(char*) PrintStrFn;
    PrintStrFn printStrFn = &printStr;
    as.ptr(scrRegs64[0], printStrFn);
    as.instr(jit.encodings.CALL, scrRegs64[0]);

    as.popRegs();
}
*/

/**
Print a C string value. Callable from the JIT
*/
extern (C) void printStr(char* pStr)
{
    printf("%s\n", pStr);
}

