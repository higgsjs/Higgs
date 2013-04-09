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

module jit.peephole;

import std.stdio;
import std.string;
import std.stdint;
import options;
import ir.ir;
import jit.assembler;
import jit.x86;
import jit.encodings;

/*
; $7 = is_int32 $15
mov al, [byte rbp + 15];                8A 45 0F
cmp al, 0;                              3C 00
mov rax, -14;                           48 C7 C0 F2 FF FF FF
mov rcx, -15;                           48 C7 C1 F1 FF FF FF
cmove rax, rcx;                         48 0F 44 C1
mov [qword rbx + 56], rax;              48 89 43 38
mov [byte rbp + 7], 4;                  C6 45 07 04
; if_true $7 => if_true(2DEF), if_false(2E05)
mov al, [byte rbx + 56];                8A 43 38
cmp al, -15;                            3C F1
jne IF_EXIT(1669);                      0F 85 2B 05 00 00

need almost the whole pattern, except for the initial load

can optimize to:
; $7 = is_int32 $15         
mov al, [byte rbp + 15];                8A 45 0F
cmp al, 0;                              3C 00
mov rax, -14;                           48 C7 C0 F2 FF FF FF
mov rcx, -15;                           48 C7 C1 F1 FF FF FF
cmove rax, rcx;                         48 0F 44 C1
mov [qword rbx + 56], rax;              48 89 43 38
mov [byte rbp + 7], 4;                  C6 45 07 04
; if_true $7 => if_true(2DEF), if_false(2E05)
; mov al, [byte rbx + 56];                8A 43 38
; cmp al, -15;                            3C F1
jne IF_EXIT(1669);                      0F 85 2B 05 00 00

Saves two instructions, one load
*/

/*
Redundant loads, more sophisticated
- If value still in a register, use the register directly

Can also eliminate redundant cmps

Both of these together implement a more powerful version of the above ***

Redundant load:
- Find write to a mem loc from register
- Scan until load from mem loc
  - Stop scan if anything writes to register or may touch register
- Eliminate load, replace use of load dest by init reg (if possible?)

PROBLEM: can't eliminate load unless we really know it's uses are dead!

*/

/// Test if two operands are registers with the same register number
bool sameRegNo(X86Opnd a, X86Opnd b)
{
    auto ra = cast(X86Reg)a;
    auto rb = cast(X86Reg)b;

    if (ra is null || rb is null)
        return false;

    return (ra.regNo is rb.regNo);
}

/// Test if an instruction writes to a given register
bool writesReg(X86Instr instr, X86Reg reg)
{
    if (reg is null)
        return false;

    return (
        sameRegNo(instr.opnds[0], reg) ||
        instr.opcode is MUL || 
        instr.opcode is IMUL || 
        instr.opcode is DIV || 
        instr.opcode is IDIV
    );
}

void optAsm(Assembler as)
{
    // While changes are still occurring
    for (bool changed = true; changed !is false; changed = false)
    {
        // For each instruction
        for (auto ins1 = as.getFirstInstr(); ins1 !is null; ins1 = ins1.next)
        {
            auto instr = cast(X86Instr)ins1;
            if (instr is null)
                continue;









            //optStoreLoad(instr, changed);
        }
    }
}

void optStoreLoad(X86Instr instr, ref bool changed)
{
    /*
    auto memLoc = cast(X86Mem)instr.opnds[0];
    auto reg = cast(X86Reg)instr.opnds[1];

    // If this is not a store instruction, stop
    if (instr.opcode != MOV || memLoc is null || reg is null)
        return;

    // TODO: limit the number of iterations

    for (auto ins1 = instr.next; ins1 !is null; ins1 = ins1.next)
    {
        auto instr = cast(X86Instr)ins1;
        if (instr is null)
            continue;

        // Stop if anything writes to the source register
        if (writesReg(instr1, reg))
            return;

        // Stop if anything writes to the memory location base
        if (writesReg(instr2, memLoc.base))
            return;

        // Stop if anything writes to the memory location
        if (instr2.opcode == MOV)
        {
            // TODO
        }

        // If this is a load from the same memory location
        if (instr2.opcode == MOV &&
            cast(X86Reg)instr2.opnds[0] && 
            cast(X86Mem)instr2.opnds[1] &&
            instr2.opnds[1] == memLoc)
        {



            writefln("match");

        }
    }

    // TODO
    */
}

