/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module jit.regalloc;

import std.stdio;
import std.array;
import std.stdint;
import ir.ir;
import ir.livevars;
import jit.x86;
import util.bitset;

X86Reg interpReg;
X86Reg wspReg;
X86Reg tspReg;
X86Reg cspReg;
X86Reg[] cargRegs;
X86Reg[] cfpArgRegs;
X86Reg[] scrRegs64;
X86Reg[] scrRegs32;
X86Reg[] scrRegs16;
X86Reg[] scrRegs8;
X86Reg[] allocRegs;

/**
Mapping of the x86 machine registers
*/
static this()
{
    /// R15: interpreter object pointer (C callee-save) 
    interpReg = R15;

    /// R14: word stack pointer (C callee-save)
    wspReg = R14;

    /// R13: type stack pointer (C callee-save)
    tspReg = R13;

    // RSP: C stack pointer (used for C calls only)
    cspReg = RSP;

    /// C argument registers
    cargRegs = [RDI, RSI, RDX, RCX, R8, R9];

    /// C fp argument registers
    cfpArgRegs = [XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7];

    /// RAX: scratch register, C return value
    /// RDI: scratch register, first C argument register
    /// RSI: scratch register, second C argument register
    scrRegs64 = [RAX, RDI, RSI];
    scrRegs32 = [EAX, EDI, ESI];
    scrRegs16 = [AX , DI , SI ];
    scrRegs8  = [AL , DIL, SIL];

    /// RCX, RBX, RBP, R8-R12: 9 allocatable registers
    allocRegs = [RCX, RDX, RBX, RBP, R8, R9, R10, R11, R12];
}

/// Mapping of locals to registers
alias X86Reg[LocalIdx] RegMapping;

RegMapping mapRegs(IRFunction fun, BitSet[IRInstr] liveSets)
{
    /*
    Slots with short live ranges should be colored first?

    - Go over basic blocks, count number of instrs where values interfere
      - Add counts to edges

    Slots that are live at the same time interfere
    Slots that interfere are assigned different regs if possible

    - Color slots with registers so as to minimize conflicts
      - Use greedy coloring algorithm
      - If already mapped register must be used, pick
        neighbor with least contention?
        - But hooooow?

    - Also color with XMM registers for FP values and spills
    */

    /*
    // Interference counts
    uint32_t[LocalIdx][LocalIdx] interfCounts;

    // For each live set
    foreach (instr, liveSet; liveSets)
    {
        for (LocalIdx i0 = 0; i0 < liveSet.length; ++i0)
        {
            if (liveSet.has(i0))
            {
                for (LocalIdx i1 = 0; i1 < liveSet.length; ++i1)
                {
                    if (liveSet.has(i1) && i1 != i0)
                    {
                        interfCounts[i0][i1]++;
                        interfCounts[i1][i0]++;
                    }
                }
            }
        }
    }
    */

    // Map of stack slots to registers
    RegMapping mapping;

    /*
    size_t numConflicts = 0;

    // For each local slot
    MAPPING_LOOP:
    for (LocalIdx idx = 0; idx < fun.numLocals; ++idx)
    {
        // If this slot interferes with nothing
        if (idx !in interfCounts)
        {
            //writefln("no interf for %s", idx);

            // Assign it the first allocatable register
            mapping[idx] = allocRegs[0];
            continue MAPPING_LOOP;
        }

        // Bit map of used registers
        uint16_t usedRegs = 0;

        // Register with the least interference count
        LocalIdx leastCnt = LocalIdx.max;
        X86Reg leastReg = null;

        // For each interfering slot
        foreach (interfIdx, count; interfCounts[idx])
        {
            // If that slot has an assigned register
            if (interfIdx in mapping)
            {
                // Mark that register as used
                auto reg = mapping[interfIdx];
                usedRegs |= (1 << reg.regNo);

                //writefln("reg taken: %s (%s) by %s", reg.toString(), (1 << reg.regNo), interfIdx);

                // Keep track of the register of the mapped slot
                // we least often interfere with
                if (count < leastCnt)
                {
                    leastCnt = count;
                    leastReg = reg;
                }
            }
        }

        // For each allocatable register
        foreach (reg; allocRegs)
        {
            // If this register is free
            if ((usedRegs & (1 << reg.regNo)) == 0)
            {
                // Assign the register to this slot
                mapping[idx] = reg;
                continue MAPPING_LOOP;
            }
        }

        //writefln("%s", interf.length);

        // Choose the register of the slot we
        // least often interfere with
        assert (leastReg !is null);
        mapping[idx] = leastReg;

        //writefln("%s conflict assign: %s", fun.getName(), leastReg.toString());
        numConflicts++;
    }
    */

    //writefln("%s num conflicts: %s", fun.getName(), numConflicts);

    /*    
    writefln("%s", fun.getName());
    for (LocalIdx idx = 0; idx < fun.numLocals; ++idx)
    {
        auto interf = interfCounts.get(idx, uint32_t[LocalIdx].init);

        writefln(
            "%s => %s (%s interf)", 
            idx, 
            mapping[idx].toString(),
            interf.length
        );

        foreach (idx1, count; interf)
            writefln("  %s (%s) ", idx1, mapping[idx1].toString());
    }
    writeln();
    */    

    return mapping;
}

