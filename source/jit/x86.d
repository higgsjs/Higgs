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

module jit.x86;

import std.stdio;

struct X86Reg
{
    alias uint Type;
    enum : Type
    {
        GP,
        FP,
        XMM
    }

    uint type;

    uint regNo;

    // Size in bits
    uint size;
};

/// Register constants
auto eax = X86Reg(X86Reg.GP, 0, 32);
auto ecx = X86Reg(X86Reg.GP, 1, 32);
auto edx = X86Reg(X86Reg.GP, 2, 32);
auto ebx = X86Reg(X86Reg.GP, 3, 32);

struct X86Opnd
{
    /// Operand type enumeration
    alias uint Type;
    enum : Type
    {
        REG,
        MEM,
        IMM,
        LINK
    };

    // Operand type
    Type type;
    
    union
    {
        // Register
        X86Reg* reg;

        // Memory location
        struct { uint memSize; X86Reg* base; uint disp; X86Reg* index; uint scale; }

        // Immediate value
        ulong imm;

        // TODO: link-time value
    };
}

immutable size_t MAX_OPNDS = 4;




// Problem: currently, we try to find shortest encoding (if avail) given operands
// Would like to do the same now?
// May need different prefixes and encodings based on opnds
// Could possibly have generic encoding function?


// Probably want to first emit pseudo-x86 with loads and stores from stack slot operands
// Translate and patch up according to operand validity rules

// TODO: start implementing tracelet JIT, see what's needed first?



class X86Instr
{
    abstract void encode();

    abstract size_t length();

    X86Opnd[MAX_OPNDS] opnds;

    X86Instr prev;
    X86Instr next;
}










