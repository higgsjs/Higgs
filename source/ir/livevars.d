/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2014, Maxime Chevalier-Boisvert. All rights reserved.
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
import std.stdint;
import ir.ir;
import util.bitset;
import util.string;

/**
Liveness information for a given function
*/
class LiveInfo
{
    // Indices for values we track the liveness of
    private uint32_t valIdxs[IRDstValue];

    // Indices for instructions we may query for liveness at
    private uint32_t locIdxs[IRInstr];

    // Internal bitset used to store liveness info
    private int32_t[] bitSet;

    /**
    Test if a value is live before a given instruction
    Note: this function is exposed outside of this analysis
    */
    public bool liveBefore(IRDstValue val, IRInstr beforeInstr)
    {
        if (val.hasNoUses)
            return false;

        // If the value is the instruction, it isn't live
        if (val is beforeInstr)
            return false;

        // If the value is an argument to the instruction, it is live
        if (beforeInstr.hasArg(val))
            return true;

        // If the value is live after the instruction, it is live before
        return liveAfter(val, beforeInstr);
    };

    /**
    Test if a value is live after a given instruction
    Note: this function is exposed outside of this analysis
    */
    public bool liveAfter(IRDstValue val, IRInstr afterInstr)
    {
        if (val.hasNoUses)
            return false;

        assert (
            val in valIdxs,
            "val not in liveness map: " ~ val.toString ~ " (" ~ val.idString ~ ")"
        );
        assert (
            afterInstr in locIdxs,
            "cannot query for liveness at instr: " ~ afterInstr.toString()
        );

        auto x = valIdxs[val];
        auto y = locIdxs[afterInstr];
        auto idx = y * valIdxs.length + x;

        auto bitIdx = idx & 31;
        auto intIdx = idx >> 5;
        assert (intIdx < bitSet.length);

        return ((bitSet[intIdx] >> bitIdx) & 1) == 1;
    };

    /**
    Test if a value is live after the phi nodes of a given block
    */
    public bool liveAfterPhi(IRDstValue val, IRBlock block)
    {
        assert (
            val !is null,
            "value is null in liveAtEntry"
        );

        assert (
            block.firstInstr !is null,
            "block contains no instructions"
        );

        // If the value is the first instruction, it isn't live
        if (val is block.firstInstr)
            return false;

        // If the value is an argument to the first block instruction, it is live
        for (size_t aIdx = 0; aIdx < block.firstInstr.numArgs; ++aIdx)
            if (val is block.firstInstr.getArg(aIdx))
                return true;

        // Test if the value is live after the first instruction
        return liveAfter(val, block.firstInstr);
    }

    /**
    Test if a value is live at a basic block's entry
    */
    public bool liveAtEntry(IRDstValue val, IRBlock block)
    {
        assert (
            val !is null,
            "value is null in liveAtEntry"
        );

        // If the value is a phi node argument, it must be live
        for (size_t pIdx = 0; pIdx < block.numIncoming; ++pIdx)
        {
            auto desc = block.getIncoming(pIdx);
            foreach (arg; desc.args)
                if (arg.value is val)
                    return true;
        }

        // If the value is from this block and is a phi node, it isn't live
        if (val.block is block && cast(PhiNode)val)
            return false;

        // Test if the value is live after the phi nodes
        return liveAfterPhi(val, block);
    }

    /**
    Mark a value as live after a given instruction
    */
    private void markLiveAfter(IRDstValue val, IRInstr afterInstr)
    {
        assert (val in valIdxs);
        assert (afterInstr in locIdxs);

        auto x = valIdxs[val];
        auto y = locIdxs[afterInstr];
        auto idx = y * valIdxs.length + x;

        auto bitIdx = idx & 31;
        auto intIdx = idx >> 5;
        assert (intIdx < bitSet.length);

        bitSet[intIdx] |= (1 << bitIdx);
    }

    /**
    Performs liveness analysis on a function body and
    returns a liveness query function (closure)
    */
    public this(IRFunction fun)
    {
        assert (
            fun.entryBlock !is null,
            "function has no IR"
        );

        for (auto block = fun.firstBlock; block !is null; block = block.next)
        {
            for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
            {
                // We can query for the liveness of this phi node if it has uses
                if (!phi.hasNoUses)
                    valIdxs[phi] = cast(uint32_t)valIdxs.length;
            }

            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
            {
                // We can query for the liveness of this instruction if it has uses
                if (!instr.hasNoUses)
                    valIdxs[instr] = cast(uint32_t)valIdxs.length;

                // We can query for liveness after any instruction
                locIdxs[instr] = cast(uint32_t)locIdxs.length;
            }
        }

        // Compute the size of the internal bit set
        auto numBits = valIdxs.length * locIdxs.length;
        auto numInts = (numBits / 32) + ((numBits % 32)? 1:0);

        // Allocate the internal bit set to store liveness information
        bitSet = new int32_t[numInts];

        // Stack of blocks for DFS traversal
        IRBlock stack[];

        /**
        Traverse a basic block as part of a liveness analysis
        */
        void traverseBlock(IRDstValue defVal, IRBlock block, IRInstr fromInstr)
        {
            // For each instruction, in reverse order
            for (auto instr = fromInstr; instr !is null; instr = instr.prev)
            {
                // Mark the value as live after this instruction
                markLiveAfter(defVal, instr);

                // If this is the definition point for the value, stop
                if (instr is defVal)
                    return;
            }

            // If the value is defined by a phi node from this block, stop
            if (defVal.block is block)
            {
                assert (cast(PhiNode)defVal !is null);
                return;
            }

            // Queue the predecessor blocks
            for (size_t iIdx = 0; iIdx < block.numIncoming; ++iIdx)
                stack ~= block.getIncoming(iIdx).branch.block;
        }

        /**
        Do the liveness traversal for a given use
        */
        void liveTraversal(IRDstValue defVal, IRDstValue useVal)
        {
            assert (defVal !is null);
            assert (useVal !is null);
            assert (stack.length is 0);

            // Get the block the use belongs to
            auto useBlock = useVal.block;
            assert (useBlock !is null);

            // If the use belongs to an instruction
            if (auto useInstr = cast(IRInstr)useVal)
            {
                // Traverse the block starting from the previous instruction
                traverseBlock(defVal, useBlock, useInstr.prev);
            }

            // If the use belongs to a phi node
            else if (auto usePhi = cast(PhiNode)useVal)
            {
                // Find the predecessors which supplies the value and queue them
                for (size_t iIdx = 0; iIdx < useBlock.numIncoming; ++iIdx)
                {
                    auto branch = useBlock.getIncoming(iIdx);
                    auto phiArg = branch.getPhiArg(usePhi);
                    if (phiArg is defVal)
                        stack ~= branch.branch.block;
                }
            }

            else
            {
                assert (false);
            }

            // Until the stack is empty
            while (stack.length > 0)
            {
                // Pop the top of the stack
                auto block = stack[$-1];
                stack.length -= 1;

                assert (block.lastInstr !is null);

                // If the value is live at the exit of this block, skip it
                if (liveAfter(defVal, block.lastInstr))
                    continue;

                // Traverse the block starting from the last instruction
                traverseBlock(defVal, block, block.lastInstr);
            }
        }

        // Compute the liveness of all values
        for (auto block = fun.firstBlock; block !is null; block = block.next)
        {
            for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
                for (auto use = phi.getFirstUse; use !is null; use = use.next)
                    liveTraversal(phi, use.owner);

            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
                for (auto use = instr.getFirstUse; use !is null; use = use.next)
                    liveTraversal(instr, use.owner);
        }
    }
}

