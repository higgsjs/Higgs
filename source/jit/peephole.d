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

// TODO
/*
// Table of conditional jump instructions and their logical inverses
const jumpInvs = {
    'je': 'jne',
    'jg': 'jle',
    'jge': 'jl',
    'jl': 'jge',
    'jle': 'jg',
    'jne': 'je'
}
*/

/**
Perform peephole optimizations on a function's ASM code
*/
void optAsm(Assembler as)
{
    // ASM changed flag
    bool changed = true;

    /**
    Remove an instruction
    */
    void remInstr(ASMInstr instr)
    {
        /*
        assert (
            (instr instanceof x86.DataBlock) === false,
            'removing data block'
        );
        */

        //writefln("removing %s", instr);

        as.remInstr(instr);
        changed = true;
    }

    /**
    Add an instruction after another one
    */
    void addAfter(ASMInstr newInstr, ASMInstr prev)
    {
        as.addInstrAfter(newInstr, prev);
        changed = true;
    }

    bool jumpOpts(X86Instr instr, X86OpPtr op)
    {
        // If this is not a jump instruction, stop
        if (op !is JMP   &&
            op !is JL    &&
            op !is JLE   &&
            op !is JG    &&
            op !is JGE   &&
            op !is JE    &&
            op !is JNE)
            return false;

        // Get the jump label
        auto labelRef = cast(X86LabelRef)instr.opnds[0];

        // If this does not jump to a label, stop
        if (labelRef is null)
            return false;

        auto label = labelRef.label;

        // If the label immediately follows
        if (label is instr.nextNC)
        {
            remInstr(instr);
            return true;
        }

        // If this is a jump to a direct jump
        if (auto instr2 = cast(X86Instr)label.nextNC)
        {
            if (instr2.opcode is JMP)
            {
                auto j2LabelRef = cast(X86LabelRef)instr2.opnds[0]; 

                // If the second jump label is not the same as ours
                if (j2LabelRef && j2LabelRef.label && j2LabelRef.label !is label)
                {
                    // Jump directly to the second label
                    labelRef.label = j2LabelRef.label;
                    return true;
                }
            }
        }

        // If this is a direct jump
        if (op is JMP)
        {
            // Remove any instructions that immediately follow
            while (cast(X86Instr)instr.nextNC)
                remInstr(instr.nextNC);

            return true;
        }

        // No changes made
        return false;
    }

    // While changes are still occurring
    while (changed !is false)
    {
        changed = false;

        // Count the references to each label
        for (auto obj = as.getFirstInstr(); obj !is null; obj = obj.next)
        {
            if (auto instr = cast(X86Instr)obj)
            {
                foreach (opnd; instr.opnds)
                {
                    if (auto labelRef = cast(X86LabelRef)opnd)
                        labelRef.label.refCount++;

                    if (auto ipRel = cast(X86IPRel)opnd)
                        ipRel.label.refCount++;
                }
            }
        }

        // For each instruction
        INSTR_LOOP:
        for (auto obj = as.getFirstInstr(); obj !is null; obj = obj.next)
        {
            // If this is an instruction
            if (auto instr = cast(X86Instr)obj)
            {
                auto opcode = instr.opcode;

                if (jumpOpts(instr, opcode))
                    continue INSTR_LOOP;
            }

            // If this is a label
            else if (auto label = cast(Label)obj)
            {
                // If the reference count is 0 and this label is
                // not exported, remove it
                if (label.refCount == 0 && label.exported == false)
                    remInstr(label);

                // Reset the reference count for the label
                label.refCount = 0;
            }
        }
    }
}

