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

module ir.livevars;

import std.stdio;
import std.array;
import std.string;
import ir.ir;
import util.bitset;
import util.string;

BitSet[IRInstr] compLiveVars(IRFunction fun)
{
    assert (
        fun.entryBlock !is null,
        "function has no IR"
    );

    // Sets of variables live after each instruction
    BitSet[IRInstr] liveSets;

    // Initialize the maps for each instruction
    for (auto block = fun.firstBlock; block !is null; block = block.next)
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
            liveSets[instr] = new BitSet(fun.numLocals);

    // Compute the list of predecessors for each block
    IRBlock[][IRBlock] preds;
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        auto branch = block.lastInstr;
        assert (branch.opcode.isBranch);
        if (branch.target)
            preds[branch.target] ~= block;
        if (branch.excTarget)
            preds[branch.excTarget] ~= block;
    }

    // Work list of blocks to process
    IRBlock[] workList;

    // Add all blocks to the work list
    for (auto block = fun.firstBlock; block !is null; block = block.next)
        workList ~= block;

    // Preallocate temporary live set objects
    auto liveSet = new BitSet(fun.numLocals);
    auto origSet = new BitSet(fun.numLocals);

    // Until the work list is empty
    while (workList.length > 0)
    {
        auto block = workList[$-1];
        workList.popBack();

        auto branch = block.lastInstr;
        assert (branch.opcode.isBranch);

        // Get a copy of the live set at the exit of this block
        //auto liveSet = new BitSet(liveSets[branch]);
        liveSet.assign(liveSets[branch]);

        // For each instruction, in reverse order
        for (auto instr = block.lastInstr; instr !is null; instr = instr.prev)
        {
            // Update the live set for after this instruction
            if (instr !is branch)
                liveSets[instr].assign(liveSet);

            // The output slot of the instruction is no longer live
            if (instr.outSlot != NULL_LOCAL)
                liveSet.remove(instr.outSlot);

            // All slots read by the instruction become live
            foreach (argIdx, arg; instr.args)
                if (instr.opcode.getArgType(argIdx) is OpArg.LOCAL)
                    liveSet.add(arg.localIdx);
        }
    
        // For each predecessor of this block
        foreach (pred; preds.get(block, []))
        {
            auto predBranch = pred.lastInstr;
            assert (predBranch !is null);
            auto predSet = liveSets[predBranch];

            // Save a copy of the predecessor's original live set
            //auto origSet = new BitSet(predSet);
            origSet.assign(predSet);

            // Merge the current live set into the predecessor's
            predSet.setUnion(liveSet);

            // If the live set changed, queue the predecessor
            if (predSet != origSet)
                workList ~= pred;
        }
    }

    /*
    if (!fun.getName.startsWith("$rt_typeof"))
        return liveSets;

    writefln("");
    writefln("%s", fun.getName());
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        writefln("%s", block.getName());

        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            writeln(indent(instr.toString(), "  "));

            liveSet = liveSets[instr];

            write("    ");
            for (size_t i = 0; i < liveSet.length; ++i)
                if (liveSet.has(i))
                    writef("$%s ", i);
            writeln();

        }

        writefln("");
    }
    writefln("");
    */

    return liveSets;
}

