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

module jit.inlining;

import std.stdio;
import std.stdint;
import std.array;
import std.typecons;
import interp.interp;
import ir.ir;
import ir.ops;
import ir.inlining;
import ir.livevars;
import ir.peephole;
import ir.slotalloc;
import options;

// Maximum growth factor due to inlining
//const GROWTH_FACTOR = 30;
const GROWTH_FACTOR = 3;

// Minimum execution count frequency required for inlining
const CALL_MIN_FRAC = 4;

// Maximum inlinable callee size
const MAX_CALLEE_SIZE = 30;

/// Where a function is on the call stack
enum StackPos
{
    NOT,
    TOP,
    DEEP
}

/**
Test if a function is on the interpreter stack
*/
StackPos funOnStack(Interp interp, IRFunction fun)
{
    size_t maxDepth = size_t.max;

    auto visitFrame = delegate void(
        IRFunction curFun, 
        Word* wsp, 
        Type* tsp, 
        size_t depth,
        size_t frameSize,
        IRInstr callInstr
    )
    {
        if (curFun is fun)
            if (depth > maxDepth || maxDepth == size_t.max)
                maxDepth = depth;
    };

    interp.visitStack(visitFrame);

    if (maxDepth == size_t.max)
        return StackPos.NOT;
    else if (maxDepth == 0)
        return StackPos.TOP;
    else
        return StackPos.DEEP;
}

/// Inlining candidate site value
alias Tuple!(IRInstr, "callSite", IRFunction, "callee") InlSite;

/**
Find a call site and function to inline in a given function
*/
InlSite findInlSite(IRFunction caller)
{
    // Best inlining candidate found
    auto bestFound = InlSite(null, null);

    // Execution count for the best candidate
    size_t bestCount = 0;

    // For each block of the caller function
    for (auto block = caller.firstBlock; block !is null; block = block.next)
    {
        // If we have a better candidate already, skip it
        if (block.execCount <= bestCount)
            continue;

        // If this block was not executed often enough, skip it
        if (block.execCount * CALL_MIN_FRAC < caller.entryBlock.execCount)
            continue;

        // Get the last instruction of the block
        auto callSite = block.lastInstr;
        assert (callSite !is null, "last instr is null");

        // If this is is not a call site, skip it
        if (callSite.opcode.isCall is false)
            continue;

        // If there is not exactly one callee, skip it
        if (caller.callCounts[callSite].length != 1)
            continue;

        // Get the callee
        auto callee = caller.callCounts[callSite].keys[0];

        // If the callee is too big to be inlined, skip it
        if (callee.numBlocks > MAX_CALLEE_SIZE)
            continue;

        // If this combination is not inlinable, skip it
        if (inlinable(callSite, callee) is false)
            continue;

        // Update the best candidate found
        bestFound.callSite = callSite;
        bestFound.callee = callee;
    }

    // Return the best candidate found
    return bestFound;
}

/**
Selectively inline callees into a function
*/
void inlinePass(Interp interp, IRFunction fun)
{
    // Test if and where this function is on the call stack
    auto stackPos = funOnStack(interp, fun);

    // Don't inline if the function is deep on the stack
    if (stackPos is StackPos.DEEP)
        return;

    // Get the number of blocks and locals before inlining
    auto preNumBlocks = fun.numBlocks;
    auto preNumLocals = fun.numLocals;

    // Pre-inlining word and type stacks (temporary storage)
    Word[] preWS;
    Type[] preTS;

    // Pre-inlining stack frame mapping
    LocalIdx[IRDstValue] preIdxs;

    // If the function is mid-execution
    if (stackPos is StackPos.TOP && interp.target !is fun.entryBlock)
    {
        // Save the current stack frame
        preWS.length = preNumLocals;
        preTS.length = preNumLocals;
        memcpy(preWS.ptr, interp.wsp, preNumLocals * Word.sizeof);
        memcpy(preTS.ptr, interp.tsp, preNumLocals * Type.sizeof);

        // Save the current stack mapping of phi nodes and instructions
        for (auto block = fun.firstBlock; block !is null; block = block.next)
        {
            for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
                preIdxs[phi] = phi.outSlot;
            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
                preIdxs[instr] = instr.outSlot;
        }
    }

    //writeln(fun.toString());

    // Number of inlinings performed
    auto numInlinings = 0;

    // Map of inlined call sites to return phi nodes
    PhiNode[IRInstr] callSites;

    // Until we have exhausted the inlining budget or
    // there are no suitable inlining candidates
    for (;;)
    {
        // If the caller is now too big to inline into, stop
        if (fun.numBlocks > preNumBlocks * GROWTH_FACTOR)
            break;

        // Attempt to find an inlining candidate
        auto inlSite = findInlSite(fun);

        // If no suitable candidate was found, stop
        if (inlSite is inlSite.init)
            break;

        auto callSite = inlSite.callSite;
        auto block = callSite.block;
        auto callee = inlSite.callee;

        if (opts.jit_dumpinfo)
        {
            writefln(
                "inlining %s into %s",
                callee.getName(),
                callSite.block.fun.getName()
            );

            writefln(
                "%s / %s (freq=%s, sz=%s)",
                callSite.block.execCount,
                fun.entryBlock.execCount,
                cast(double)block.execCount / fun.entryBlock.execCount,
                fun.numBlocks
            );
        }

        // Inline the callee
        auto retPhi = inlineCall(callSite, callee);
        callSites[callSite] = retPhi;

        numInlinings++;
    }

    // If no inlining was done, stop
    if (numInlinings is 0)
        return;

    // If the function was not mid-execution when compilation was triggered
    if (preWS.length is 0)
    {
        //writefln("rearranging stack frame");

        // Reoptimize the fused IRs
        optIR(fun);

        // Reallocate stack slots for the IR instructions
        allocSlots(fun);

        // Adjust the size of the stack frame
        if (fun.numLocals > preNumLocals)
            interp.push(fun.numLocals - preNumLocals);
        else
            interp.pop(preNumLocals - fun.numLocals);
    }
    else
    {
        /*
        writeln("***** rewriting frame for ", fun.getName, " at ", interp.target.getName, " *****");
        writeln(interp.target.execCount);
        writeln(interp.target.fun.entryBlock.execCount);
        */

        /*
        writeln();
        writeln(fun);

        writeln();
        writeln(interp.target);
        writeln();
        */

        // Compute liveness information for the function
        auto liveInfo = new LiveInfo(fun);

        // Reoptimize the fused IRs, taking the current IP
        // and liveness information into account
        optIR(fun, interp.target, liveInfo);

        // Reallocate stack slots for the IR instructions
        allocSlots(fun);

        // Adjust the size of the stack frame
        if (fun.numLocals > preNumLocals)
            interp.push(fun.numLocals - preNumLocals);
        else
            interp.pop(preNumLocals - fun.numLocals);

        // For each phi node and instruction in the function
        foreach (val, oldIdx; preIdxs)
        {
            if (oldIdx is NULL_LOCAL)
                continue;

            //writeln("value: ", val);
            //writeln("value: ", val.idString, ", hash: ", val.toHash, ", ptr: ", cast(void*)val);

            // If the value is not currently live, skip it
            if (liveInfo.liveAfterPhi(val, interp.target) is false)
                continue;

            auto newIdx = val.outSlot;
            assert (val.block !is null);
            assert (newIdx !is NULL_LOCAL);

            /*
            writeln("rewriting: ", val);
            writeln("  word: ", preWS[oldIdx].int64Val);
            writeln("  type: ", preTS[oldIdx]);
            */

            // Copy the value to the new stack frame
            interp.wsp[newIdx] = preWS[oldIdx];
            interp.tsp[newIdx] = preTS[oldIdx];
        }

        // For each return phi node created
        foreach (callSite, phi; callSites)
        {
            if (phi is null)
                continue;

            //writeln("return phi: ", phi);
            //writeln(" call site block: ", callSite.block.getName);

            if (liveInfo.liveAfterPhi(phi, interp.target) is false)
                continue;

            auto oldIdx = preIdxs[callSite];
            auto newIdx = phi.outSlot;
            assert (newIdx !is NULL_LOCAL);

            /*
            writeln("writing phi: ", phi);
            writeln("  word: ", preWS[oldIdx].int64Val);
            writeln("  type: ", preTS[oldIdx]);
            */

            // Copy the value to the new stack frame
            interp.wsp[newIdx] = preWS[oldIdx];
            interp.tsp[newIdx] = preTS[oldIdx];
        }

        //writeln();
    }

    //writeln(fun);
    //writefln("inlinePass done");
}

