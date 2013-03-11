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

module ir.init;

import std.stdio;
import std.string;
import std.array;
import std.stdint;
import ir.ir;

/**
Map of initialized stack slots
*/
class InitMap
{
    uint32_t[] initSlots;

    size_t numSlots;

    this(size_t numSlots)
    {
        this.initSlots.length = (numSlots / 32) + ((numSlots % 32)? 1:0);

        this.numSlots = numSlots;

        for (size_t i = 0; i < initSlots.length; ++i)
            initSlots[i] = 0;
    }

    InitMap set(LocalIdx idx)
    {
        auto intIdx = idx >> 5;
        auto bitIdx = idx & 31;

        // If the bit is already set, return this map unchanged
        if ((initSlots[intIdx] >> bitIdx) & 1)
            return this;

        auto newMap = new InitMap(numSlots);

        for (size_t i = 0; i < this.initSlots.length; ++i)
            newMap.initSlots[i] = this.initSlots[i];

        newMap.initSlots[intIdx] |= (1 << bitIdx);

        return newMap;
    }

    bool get(LocalIdx idx)
    {
        auto intIdx = idx >> 5;
        auto bitIdx = idx & 31;

        return (initSlots[intIdx] >> bitIdx) & 1;
    }

    /// Compare two maps for equality
    bool opEqual(InitMap that)
    {
        assert (this.numSlots == that.numSlots);

        for (size_t i = 0; i < this.initSlots.length; ++i)
            if (this.initSlots[i] != that.initSlots[i])
                return false;

        return true;
    }

    /// Merge operator (union)
    InitMap merge(InitMap that)
    {
        assert (this.numSlots == that.numSlots);

        for (size_t i = 0; i < this.initSlots.length; ++i)
        {
            if ((this.initSlots[i] | that.initSlots[i]) != this.initSlots[i])
            {
                auto newMap = new InitMap(numSlots);

                for (size_t j = 0; j < i; ++j)
                    newMap.initSlots[j] = this.initSlots[j];

                for (size_t j = i; j < this.initSlots.length; ++j)
                    newMap.initSlots[j] = (this.initSlots[j] | that.initSlots[j]);

                return newMap;
            }
        }

        return this;
    }
}

unittest
{
    InitMap m = new InitMap(100);

    assert (m.get(0) == false);
    assert (m.get(99) == false);
    assert (m.merge(m) == m);

    auto m2 = m.set(5);

    assert (m2.get(5) == true);
    assert (m2 != m);
    assert (m2.merge(m) == m2);
    assert (m2.get(5) == true);
    assert (m.get(5) == false);

    auto m3 = m.set(65);
    auto m4 = m2.merge(m3);

    assert (m4.get(0) == false);
    assert (m4.get(5) == true);
    assert (m4.get(65) == true);
}

void genInitMaps(IRFunction fun)
{
    assert (
        fun.entryBlock !is null,
        "function has no IR"
    );

    InitMap[IRBlock] entryMaps;
    InitMap[IRBlock] exitMaps;

    // Create a map for the function entry
    auto entryMap = new InitMap(fun.numLocals);
    for (size_t i = 0; i < fun.numParams + NUM_HIDDEN_ARGS; ++i)
        entryMap = entryMap.set(cast(LocalIdx)(fun.numLocals - 1 - i));

    // Initialize the slot init maps
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        entryMaps[block] = entryMap;
        exitMaps[block] = entryMap;
    }

    IRBlock[] workList = [fun.entryBlock];

    // Until the work list is empty
    while (workList.length > 0)
    {
        auto block = workList[$-1];
        workList.popBack();

        auto initMap = entryMaps[block];

        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // Store the init map at all call and allocation instructions
            if (instr.opcode == &CALL || 
                instr.opcode == &CALL_NEW || 
                instr.opcode == &CALL_APPLY || 
                instr.opcode == &HEAP_ALLOC)
            {
                fun.initMaps[instr] = initMap;
            }

            // If this instruction has an output slot, mark it as initialized
            if (instr.outSlot !is NULL_LOCAL)
            {
                initMap = initMap.set(instr.outSlot);
            }
        }

        // If the map at the exit changed
        if (exitMaps[block] != initMap)
        {
            exitMaps[block] = initMap;

            auto branch = block.lastInstr;
            assert (branch.opcode.isBranch);

            if (branch.target)
            {
                entryMaps[branch.target] = entryMaps[branch.target].merge(initMap);
                workList ~= branch.target;
            }
            if (branch.excTarget)
            {
                entryMaps[branch.excTarget] = entryMaps[branch.excTarget].merge(initMap);
                workList ~= branch.excTarget;
            }
        }
    }

    // Initialize the variables needing it
    // Go through blocks, if not init and successor has init, insert set_undef?
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        auto exitMap = exitMaps[block];

        auto branch = block.lastInstr;
        assert (branch.opcode.isBranch);

        // For each stack slot
        for (LocalIdx i = 0; i < fun.numLocals; ++i)
        {
            // If this slot is initialized, skip it
            if (exitMap.get(i) == true)
                continue;

            //continue;

            // If the a successor has this slot marked as initialized
            if ((branch.target && entryMaps[branch.target].get(i) == true) ||
                (branch.excTarget && entryMaps[branch.excTarget].get(i) == true))
            {
                block.addInstrBefore(
                    new IRInstr(&SET_UNDEF, i),
                    branch
                );
            }
        }
    }

    //writefln("%s", fun.numLocals);
    //writefln("%s", fun.numParams + NUM_HIDDEN_ARGS);
    //writefln("%s", fun.toString());
}

