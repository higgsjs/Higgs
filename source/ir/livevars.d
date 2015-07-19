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

import core.memory;
import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.algorithm;
import ir.ir;
import util.string;

/**
Liveness information for a given function
*/
class LiveInfo
{
    /**
    Live variable set implementation
    */
    struct LiveSet
    {
        IRDstValue* arr;
        uint32_t arrLen;
        uint32_t numElems;

        void add(IRDstValue val)
        {
            // If the element is already present, stop
            for (size_t i = 0; i < numElems; ++i)
                if (arr[i] is val)
                    return;

            if (numElems + 1 > arrLen)
            {
                if (arrLen is 0)
                {
                    arrLen = 16;

                    arr = cast(IRDstValue*)GC.malloc(
                        (IRDstValue*).sizeof * arrLen,
                        GC.BlkAttr.NO_SCAN |
                        GC.BlkAttr.NO_INTERIOR
                    );
                }
                else
                {
                    auto newLen = 2 * arrLen;

                    auto newArr = cast(IRDstValue*)GC.malloc(
                        (IRDstValue*).sizeof * newLen,
                        GC.BlkAttr.NO_SCAN |
                        GC.BlkAttr.NO_INTERIOR
                    );

                    for (size_t i = 0; i < numElems; ++i)
                        newArr[i] = arr[i];

                    GC.free(arr);

                    arr = newArr;
                    arrLen = newLen;
                }
            }

            arr[numElems] = val;
            numElems += 1;
        }

        bool has(IRDstValue val)
        {
            for (size_t i = 0; i < numElems; ++i)
                if (arr[i] is val)
                    return true;

            return false;
        }

        IRDstValue[] elems()
        {
            return arr[0..numElems];
        }
    }

    /// Live sets indexed by instruction (values live after the instruction)
    private LiveSet[IRInstr] liveSets;

    /**
    Compile a list of all values live before a given instruction
    */
    public IRDstValue[] valsLiveBefore(IRInstr beforeInstr)
    {
        // Get the values live after this instruction
        auto liveSet = valsLiveAfter(beforeInstr);

        // Remove the instruction itself from the live set
        if (beforeInstr.hasUses)
            liveSet = array(liveSet.filter!(v => v !is beforeInstr)());

        // Add the instruction arguments to the live set
        for (size_t aIdx = 0; aIdx < beforeInstr.numArgs; ++aIdx)
        {
            if (auto dstArg = cast(IRDstValue)beforeInstr.getArg(aIdx))
                if (!liveSet.canFind(dstArg))
                    liveSet ~= dstArg;
        }

        return liveSet;
    }

    /**
    Compile a list of all values live after a given instruction
    */
    public IRDstValue[] valsLiveAfter(IRInstr afterInstr)
    {
        assert (afterInstr in liveSets);

        return liveSets[afterInstr].elems;
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
    Test if a value is live before a given instruction
    Note: this function is exposed outside of this analysis
    */
    public bool liveBefore(IRDstValue val, IRInstr beforeInstr)
    {
        // Values with no uses are never live
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
    }

    /**
    Test if a value is live after a given instruction
    Note: this function is exposed outside of this analysis
    */
    public bool liveAfter(IRDstValue val, IRInstr afterInstr)
    {
        auto liveSet = afterInstr in liveSets;

        assert (
            liveSet !is null,
            "no live set for instr: " ~ afterInstr.toString
        );

        // Values with no uses are never live
        if (val.hasNoUses)
            return false;

        return (*liveSet).has(val);
    }

    /**
    Mark a value as live after a given instruction
    */
    private void markLiveAfter(IRDstValue val, IRInstr afterInstr)
    {
        auto liveSet = afterInstr in liveSets;

        assert (
            liveSet !is null,
            "no live set for instr: " ~ afterInstr.toString
        );

        // Add the value to the live set
        (*liveSet).add(val);
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

        //writeln(fun.getName);

        // Initialize the live sets for each instruction to the empty set
        for (auto block = fun.firstBlock; block !is null; block = block.next)
            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
                liveSets[instr] = LiveSet.init;

        // Stack of blocks for DFS traversal
        IRBlock[] stack;

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
                assert (
                    cast(PhiNode)defVal !is null,
                    format(
                        "value: %s\ndefined in block: %s\nnot found:\n%s",
                        defVal,
                        defVal.block.getName,
                        fun.toString
                    )
                );

                return;
            }

            // Queue the predecessor blocks
            for (size_t iIdx = 0; iIdx < block.numIncoming; ++iIdx)
            {
                stack.assumeSafeAppend() ~= block.getIncoming(iIdx).branch.block;
            }
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
                        stack.assumeSafeAppend() ~= branch.branch.block;
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
                auto block = stack.back();
                stack.length--;

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

        //writeln("  done");
    }
}

