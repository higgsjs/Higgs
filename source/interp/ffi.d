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
import jit.x86;
import jit.assembler;
import jit.codeblock;
import jit.encodings;
import jit.regalloc;
//import jit.jit;
import ir.ir;

Type[string] typeMap;
X86Reg funReg;
X86Reg scratchReg;

alias extern (C) void function(void*) FFIFn;

static this()
{
    // Mappings for arguments/return values
    typeMap["i8"]  = Type.INT32;
    typeMap["i16"] = Type.INT32;
    typeMap["i32"] = Type.INT32;
    typeMap["f64"] = Type.FLOAT64;
    typeMap["*"]   = Type.RAWPTR;

    // Registers used by the wrapper
    funReg = R12;
    scratchReg = R11;
}

/*
CodeBlock genFFIFn(Interp interp, string[] types, LocalIdx outSlot, LocalIdx[] argSlots)
{
    // Track register usage for args
    auto iArgIdx = 0;
    auto fArgIdx = 0;
    // Return type of the FFI call
    auto retType = types[0];
    // Argument types the call expects
    auto argTypes = types[1..$];
    // Arguments to pass via the stack
    LocalIdx[] stackArgs;

    auto as = new Assembler();

    // Store the GP registers
    as.instr(PUSH, RBX);
    as.instr(PUSH, RBP);
    as.instr(PUSH, R12);
    as.instr(PUSH, R13);
    as.instr(PUSH, R14);
    as.instr(PUSH, R15);

    // Store a pointer to the interpreter in interpReg
    as.instr(MOV, interpReg, new X86Imm(cast(void*)interp));

    // Fun* goes in R12
    as.instr(MOV, funReg, RDI);

    // Load the stack pointers into wspReg and tspReg
    as.getMember!("Interp", "wsp")(wspReg, interpReg);
    as.getMember!("Interp", "tsp")(tspReg, interpReg);

    // Set up arguments
    foreach(int i, idx; argSlots)
    {
        // Either put the arg in the appropriate register
        // or set it to be pushed to the stack later
        if (argTypes[i] == "f64" && fArgIdx < cfpArgRegs.length)
            as.getWord(cfpArgRegs[fArgIdx++], idx);
        else if (argTypes[i] != "f64" && iArgIdx < cargRegs.length)
            as.getWord(cargRegs[iArgIdx++], idx);
        else
            stackArgs ~= idx;
    }

    // Make sure there is an even number of pushes
    if (stackArgs.length % 2 != 0)
        as.instr(PUSH, scratchReg);

    foreach_reverse (idx; stackArgs)
    {
        as.getWord(scratchReg, idx);
        as.instr(PUSH, scratchReg);
    }

    // Fun* call
    as.instr(jit.encodings.CALL, funReg);

    // Send return value/type to interp
    if (retType == "f64")
    {
        as.setWord(outSlot, XMM0);
        as.setType(outSlot, typeMap[retType]);
    }
    else if (retType == "void")
    {
        as.setWord(outSlot, UNDEF.int8Val);
        as.setType(outSlot, Type.CONST);
    }
    else
    {
        as.setWord(outSlot, RAX);
        as.setType(outSlot, typeMap[retType]);
    }

    // Remove stackArgs
    foreach (idx; stackArgs)
        as.instr(POP, scratchReg);

    // Make sure there is an even number of pops
    if (stackArgs.length % 2 != 0)
        as.instr(POP, scratchReg);

    // Store the stack pointers back in the interpreter
    as.setMember!("Interp", "wsp")(interpReg, wspReg);
    as.setMember!("Interp", "tsp")(interpReg, tspReg);

    // Restore the GP registers & return
    as.instr(POP, R15);
    as.instr(POP, R14);
    as.instr(POP, R13);
    as.instr(POP, R12);
    as.instr(POP, RBP);
    as.instr(POP, RBX);

    as.instr(jit.encodings.RET);

    auto cb = as.assemble();
    return cb;
}
*/

// Dummy functions used for testing
extern (C) 
{
    void testVoidFun()
    {
        return;
    }

    int testIntFun()
    {
        return 5;
    }

    double testDoubleFun()
    {
        return 5.5;
    }

    int testIntAddFun(int a, int b)
    {
        return a + b;
    }

    double testDoubleAddFun(double a, double b)
    {
        return a + b;
    }

    int testIntArgsFun(int a, int b, int c, int d, int e, int f, int g)
    {
        return a + b + c + d + e + (f - g);
    }

    double testDoubleArgsFun(double a, double b, double c, double d, double e, double f, double g)
    {
        return a + b + c + d + e + (f - g);
    }

    void* testPtrFun()
    {
        return &testIntAddFun;
    }

    double testMixedArgsFun(int a, double b, int c, double d, int e, double f, int g)
    {
        return cast(double)(a + b + c + d + e + (f - g));
    }
}

// FIXME
/*
unittest
{
    writefln("FFI");

    auto interp = new Interp();
    interp.load("programs/ffi/ffi.js");
}
*/

