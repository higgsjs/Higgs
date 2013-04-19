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
import ir.ir;
import util.bitset;

void genInitMaps(IRFunction fun)
{
    assert (
        fun.entryBlock !is null,
        "function has no IR"
    );

    BitSetCW[IRBlock] entryMaps;

    // Create an empty map
    auto emptyMap = new BitSetCW(fun.numLocals);

    // Create a map for the function entry where only
    // the hidden and visible arguments are initialized
    auto entryMap = emptyMap;
    for (size_t i = 0; i < fun.numParams + NUM_HIDDEN_ARGS; ++i)
        entryMap = entryMap.add(cast(LocalIdx)(fun.numLocals - 1 - i));

    // Initialize the maps for each block
    for (auto block = fun.firstBlock; block !is null; block = block.next)
        entryMaps[block] = (block is fun.entryBlock)? entryMap:emptyMap;
    
    // Create a bit set for the local variables
    auto varMap = new BitSet(fun.numLocals);
    foreach (localIdx; fun.localMap)
        varMap.add(localIdx);

    // Add the entry block to the work list
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
            // If this instruction has an output slot, mark it as initialized
            if (instr.outSlot !is NULL_LOCAL)
                initMap = initMap.add(instr.outSlot);

            assert (!(instr.opcode.isBranch && instr.next));
        }

        auto branch = block.lastInstr;
        assert (branch.opcode.isBranch);

        // If the target entry map is changed after merging
        if (branch.target)
        {
            auto targetMap = entryMaps[branch.target];
            auto mergedMap = targetMap.setUnion(initMap);

            if (mergedMap != targetMap)
            {
                entryMaps[branch.target] = mergedMap;
                workList ~= branch.target;
            }
        }

        // If the exception target entry map is changed after merging
        if (branch.excTarget)
        {
            auto targetMap = entryMaps[branch.excTarget];
            auto mergedMap = targetMap.setUnion(initMap);

            if (mergedMap != targetMap)
            {
                entryMaps[branch.excTarget] = mergedMap;
                workList ~= branch.excTarget;
            }
        }
    }

    //writefln("itr count: %s", itrCount);

    // Initialize the variables needing it
    // Go through blocks, if not init and successor has init, insert set_undef?
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        auto initMap = entryMaps[block];

        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // If this instruction reads an uninitialized variable,
            // initialize it to undefined before this instruction
            foreach (i, arg; instr.args)
            {
                if (instr.opcode.getArgType(i) == OpArg.LOCAL && 
                    initMap.has(instr.args[i].localIdx) == false)
                {
                    block.addInstrBefore(
                        new IRInstr(&SET_UNDEF, instr.args[i].localIdx),
                        instr
                    );
                }
            }

            // If this instruction has an output slot, mark it as initialized
            if (instr.outSlot !is NULL_LOCAL)
            {
                initMap = initMap.add(instr.outSlot);
                assert (initMap.has(instr.outSlot));
            }
        }

        auto branch = block.lastInstr;
        assert (branch.opcode.isBranch);

        // For each stack slot
        for (LocalIdx i = 0; i < fun.numLocals; ++i)
        {
            // If this slot is initialized, skip it
            if (initMap.has(i) == true)
                continue;

            // If this is not a local variable, skip it
            if (varMap.has(i) == false)
                continue; 

            // If the a successor has this slot marked as initialized
            if ((branch.target && entryMaps[branch.target].has(i) == true) ||
                (branch.excTarget && entryMaps[branch.excTarget].has(i) == true))
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

