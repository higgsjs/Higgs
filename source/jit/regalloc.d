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
alias X86Reg[IRDstValue] RegMapping;

// TODO: Also color all values with XMM registers for FP values and spills

RegMapping mapRegs(IRFunction fun, LiveQueryFn isLiveAfter)
{
    // Map of values to registers
    RegMapping mapping;

    auto curRegIdx = 0;

    // For each block
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        // For each phi
        for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
        {
            if (phi.hasNoUses)
                continue;

            mapping[phi] = allocRegs[curRegIdx++];
        }

        // Fo each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            if (instr.hasNoUses)
                continue;

            mapping[instr] = allocRegs[curRegIdx++];
        }
    }

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

/*
    // Interference counts
    uint32_t[IRDstValue][IRDstValue] interfCounts;

    // Assemble a list of values we need to consider the liveness of
    IRDstValue[] values;
    for (auto b = fun.firstBlock; b !is null; b = b.next)
    {
        for (auto p = b.firstPhi; p !is null; p = p.next)
            if (p.hasNoUses is false)
                values ~= p;

        for (auto i = b.firstInstr; i !is null; i = i.next)
            if (i.hasNoUses is false)
                values ~= i;
    }

    // For block
    for (auto lBlock = fun.firstBlock; lBlock !is null; lBlock = lBlock.next)
    {
        // TODO: store a live set for after the phi nodes?

        // Mark the phi node values as interfering with each other
        for (auto p0 = lBlock.firstPhi; p0 !is null; p0 = p0.next)
        {
            for (auto p1 = lBlock.firstPhi; p1 !is null; p1 = p1.next)
            {
                if (p0 !is p1)
                {
                    interfCounts[p0][p1]++;
                    interfCounts[p1][p0]++;
                }
            }

        }

        // Mark arguments of the first instruction as interfering with
        // values live after the instruction and each other
        auto fInstr = lBlock.firstInstr;
        assert (fInstr !is null);
        for (size_t aIdx0 = 0; aIdx0 < fInstr.numArgs; ++aIdx0)
        {
            auto a0 = cast(IRDstValue)fInstr.getArg(aIdx0);
            if (a0 is null)
                continue;

            foreach (v; values)
            {
                if (a0 !is v && v !is fInstr && isLiveAfter(v, fInstr))
                {
                    interfCounts[a0][v]++;
                    interfCounts[v][a0]++;
                }
            }

            for (size_t aIdx1 = 0; aIdx1 < aIdx0; ++aIdx1)
            {
                auto a1 = cast(IRDstValue)fInstr.getArg(aIdx0);
                if (a1 is null)
                    continue;

                interfCounts[a0][a1]++;
                interfCounts[a1][a0]++;
            }
        }

        // For each post-instruction location in this block
        for (auto lInstr = lBlock.firstInstr; lInstr !is null; lInstr = lInstr.next)
        {
            // For each value
            foreach (v0; values)
            {
                // If the value isn't live after this point, skip it
                if (isLiveAfter(v0, lInstr) is false)
                    continue;

                // For each value
                foreach (v1; values)
                {
                    // If both v0 and v1 are live after this point,
                    // mark the pair of values as interfering
                    if (v1 !is v0 && isLiveAfter(v1, lInstr))
                    {
                        interfCounts[v0][v1]++;
                        interfCounts[v1][v0]++;
                    }
                }
            }
        }
    }

    // Map of values to registers
    RegMapping mapping;

    size_t numConflicts = 0;

    void allocReg(IRDstValue val)
    {
        // TODO: check uses of value, if use is phi, already mapped and doesn't interf, use same reg

        // If this phi node interferes with nothing
        if (phi !in interfCounts)
        {
            //writefln("no interf for %s", idx);

            // Assign it the first allocatable register
            mapping[phi] = allocRegs[0];
            return;
        }

        // Bit map of used registers
        uint16_t usedRegs = 0;

        // Register with the least interference count
        LocalIdx leastCnt = LocalIdx.max;
        X86Reg leastReg = null;

        // For each interfering value
        foreach (interfVal, count; interfCounts[idx])
        {
            // If that slot has an assigned register
            if (interfVal in mapping)
            {
                // Mark that register as used
                auto reg = mapping[interfVal];
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
                mapping[phi] = reg;
                continue PHI_LOOP;
            }
        }

        //writefln("%s", interf.length);

        // Choose the register of the slot we
        // least often interfere with
        assert (leastReg !is null);
        mapping[phi] = leastReg;

        //writefln("%s conflict assign: %s", fun.getName(), leastReg.toString());
        numConflicts++;
    }

    // Allocate registers to the phi nodes
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
        {
            if (!phi.hasNoUses)
                allocReg(phi);
        }
    }

    // Allocate registers to instructions
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            if (!instr.hasNoUses)
                allocReg(instr);
        }
    }
    */

