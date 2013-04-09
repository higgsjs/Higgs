/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011, Maxime Chevalier-Boisvert. All rights reserved.
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

module interp.ffi;

import std.stdio;
import std.string;
import std.stdint;
import std.conv;
import interp.interp;
import jit.jit;
import jit.x86;
import jit.assembler;
import jit.codeblock;
import jit.encodings;
static import ir.ir;

alias extern (C) void function(void*) FFICall;

FFICall genFFICall(ir.ir.Interp interp, ir.ir.IRInstr instr)
{
    // Mappings for arguments/return values
    X86Reg[] iArgRegs = [RDI, RSI, RDX, RCX, R8, R9];
    X86Reg[] fArgRegs = [XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7];
    auto iArgIdx = 0;
    auto fArgIdx = 0;
    Type[string] typeMap;
    typeMap["i8"] = Type.INT32;
    typeMap["i16"] = Type.INT32;
    typeMap["i32"] = Type.INT32;
    typeMap["f64"] = Type.FLOAT;
    typeMap["*"] = Type.RAWPTR;

    // Type info (D string)
    auto typeinfo = to!string(instr.args[1].stringVal);
    // Args after the first two go to the FFI call
    auto args = instr.args[2..$];
    auto types = split(typeinfo, ",");
    // Return type of the FFI call
    auto retType = types[0];
    // Argument types the call expects
    auto argTypes = types[1..$];
    // Arguments to pass via the stack
    ir.ir.LocalIdx[] stackArgs;

    auto as = new Assembler();

    assert (
        args.length == argTypes.length,
        "invalid number of args in ffi call"
    );

    // Store the GP registers
    as.instr(PUSH, RBX);
    as.instr(PUSH, RBP);
    as.instr(PUSH, R12);
    as.instr(PUSH, R13);
    as.instr(PUSH, R14);
    as.instr(PUSH, R15);

    // Store a pointer to the interpreter in R15
    as.instr(MOV, R15, new X86Imm(cast(void*)interp));

    // Fun* goes in R14
    as.instr(MOV, R14, RDI);

    // Load the stack pointers into RBX and RBP
    as.getMember!("Interp", "wsp")(RBX, R15);
    as.getMember!("Interp", "tsp")(RBP, R15);

    // preserve registers the callee may trash
    as.instr(PUSH, RCX);
    as.instr(PUSH, RDX);
    as.instr(PUSH, RSI);
    as.instr(PUSH, RDI);
    as.instr(PUSH, R8);
    as.instr(PUSH, R9);
    as.instr(PUSH, R10);
    as.instr(PUSH, R11);

    // Set up arguments
    foreach(int i, a; args)
    {
        // Either put the arg in the appropriate register
        // or set it to be pushed to the stack later
        if (argTypes[i] == "f64" && fArgIdx < fArgRegs.length)
            as.getWord(fArgRegs[fArgIdx++], a.localIdx);
        else if (argTypes[i] != "f64" && iArgIdx < iArgRegs.length)
            as.getWord(iArgRegs[iArgIdx++], a.localIdx);
        else
            stackArgs ~= a.localIdx;
    }

    // Make sure there is an even number of pushes
    if (stackArgs.length % 2 != 0)
        as.instr(PUSH, R11);

    foreach_reverse (idx; stackArgs)
    {
        as.getWord(R11, idx);
        as.instr(PUSH, R11);
    }

    // Fun* call
    as.instr(CALL, R14);

    // Send return value/type to interp
    if (retType == "f64")
    {
        as.setWord(instr.outSlot, XMM0);
        as.setType(instr.outSlot, typeMap[retType]);
    }
    else if (retType == "void")
    {
        as.setWord(instr.outSlot, UNDEF.int8Val);
        as.setType(instr.outSlot, Type.CONST);
    }
    else
    {
        as.setWord(instr.outSlot, RAX);
        as.setType(instr.outSlot, typeMap[retType]);
    }

    // Remove stackArgs
    foreach (idx; stackArgs)
        as.instr(POP, R11);

    // Make sure there is an even number of pops
    if (stackArgs.length % 2 != 0)
        as.instr(POP, R11);

    // Restore registers the callee may trash
    as.instr(POP, R11);
    as.instr(POP, R10);
    as.instr(POP, R9);
    as.instr(POP, R8);
    as.instr(POP, RDI);
    as.instr(POP, RSI);
    as.instr(POP, RDX);
    as.instr(POP, RCX);

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(R15, RBX);
    as.setMember!("Interp", "tsp")(R15, RBP);

    // Restore the GP registers & return
    as.instr(POP, R15);
    as.instr(POP, R14);
    as.instr(POP, R13);
    as.instr(POP, R12);
    as.instr(POP, RBP);
    as.instr(POP, RBX);
    as.instr(RET);

    auto cb = as.assemble();
    auto callerfun = cast(FFICall)cb.getAddress();
    return callerfun;
}