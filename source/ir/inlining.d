/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module ir.inlining;

import std.stdio;
import std.string;
import ir.ir;

/**
Inline a callee function at a call site
*/
void inlineCall(IRInstr callSite, IRFunction callee)
{
    // Not support for new for now, avoids complicated return logic
    assert (callSite.opcode is &CALL);

    // No support for inlinin within try blocks for now
    assert (callSite.excTarget is null);

    // No support fo rfunctions with arguments
    assert (callee.ast.usesArguments == false);

    // Get the caller function
    auto caller = callSite.block.fun;
    assert (caller !is null);



    // Map of pre-inlining local indices to post-inlining local indices 
    // Only for locals of the caller function
    LocalIdx[LocalIdx] localMap;

    // TODO: extend caller frame, remap locals
    // - Map of stack indices to stack indices









    // TODO: should copy caller blocks?
    // TODO: reprocess blocks

    IRBlock[IRBlock] blockMap;

    // Copy the callee blocks
    for (auto block = callee.firstBlock; block !is null; block = block.next)
    {
        auto newBlock = block.dup;
        blockMap[block] = newBlock;
        caller.addBlock(newBlock);
    }

    // For each copied block
    foreach (orig, block; blockMap)
    {
        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // TODO:
            //  - Map of call instrs to lists of functions
            if (instr.opcode.isCall)
            {

            }



            // Translate local indices
            // TODO




            // Tanslate targets
            if (instr.target)
                instr.target = blockMap[instr.target];
            if (instr.excTarget)
                instr.excTarget = blockMap[instr.excTarget];
        }
    }








    // TODO: extend caller frame to store all callee locals
    // - rename caller locals (make offset higher)
    // ISSUE: inlining multiple functions, don't want to add more locals each time
    // Can we pre-extend the caller frame? Not very convenient
    // Could extend at each inlining, compact frame in separate pass
    // - compute liveness, perform allocation/coloring
    // Can do many inlinings, extend stack frame a lot, compact at the end?







    // TODO: test for callee before jumping
    // Need to test that the IRFunction matches
    // clos_get_fptr? Don't want to add another function call, dude
    // - need to load it directly from the closure, need fixed offset
    // eq_rawptr




    // TODO: translate the return slot
    auto retSlot = callSite.outSlot;


    // TODO: copy callee code into caller
    // - move args into locals
    // - write undef into missing args
    // - move return value into ret slot








}

