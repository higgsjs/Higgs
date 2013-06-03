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
import std.stdint;
import ir.ir;
import interp.object;
import util.bitset;

/// Maximum number of locals a caller may have before inlining
const size_t MAX_CALLER_LOCALS = 100;

/// Maximum number of locals a callee may have before inlining
const size_t MAX_CALLEE_LOCALS = 30;

/**
Test if a function is inlinable at a call site
*/
bool inlinable(IRInstr callSite, IRFunction callee)
{
    // Not support for new for now, avoids complicated return logic
    if (callSite.opcode !is &CALL)
        return false;

    // No support for inlinin within try blocks for now
    if (callSite.excTarget !is null)
        return false;

    // No support fo rfunctions with arguments
    if (callee.ast.usesArguments == true)
        return false;

    // No support for argument count mismatch
    auto numArgs = callSite.args.length - 2;
    if (numArgs != callee.numParams)
        return false;

    // If the caller is too big to inline into
    auto caller = callSite.block.fun;
    if (caller.numLocals > MAX_CALLER_LOCALS)
        return false;

    // If the callee is too big to be inlined
    if (callee.numLocals > MAX_CALLEE_LOCALS)
        return false;

    // Inlining is possible
    return true;
}

/**
Inline a callee function at a call site
*/
LocalIdx[LocalIdx] inlineCall(IRInstr callSite, IRFunction callee)
{
    // Ensure that this inlining is possible
    assert (inlinable(callSite, callee));

    // Get the caller function
    auto caller = callSite.block.fun;
    assert (caller !is null);

    // Get the number of arguments passed
    auto numArgs = callSite.args.length - 2;

    //
    // Stack-frame remapping
    //

    // Remap the hidden arguments
    caller.raSlot += callee.numLocals;
    caller.closSlot += callee.numLocals;
    caller.thisSlot += callee.numLocals;
    caller.argcSlot += callee.numLocals;

    // Map of pre-inlining local indices to post-inlining indices 
    // Only for locals of the caller function, used for on-stack replacement
    LocalIdx[LocalIdx] localMap;

    // Remap the caller locals to add callee locals
    for (LocalIdx i = 0; i < caller.numLocals; ++i)
        localMap[i] = i + callee.numLocals;

    // Remap the caller identifiers
    foreach (id, localIdx; caller.cellMap)
        caller.cellMap[id] = localIdx + callee.numLocals;
    foreach (id, localIdx; caller.localMap)
        caller.localMap[id] = localIdx + callee.numLocals;

    // For each caller block
    for (auto block = caller.firstBlock; block !is null; block = block.next)
    {
        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // Translate local indices
            foreach (argIdx, arg; instr.args)
                if (instr.opcode.getArgType(argIdx) == OpArg.LOCAL)
                    instr.args[argIdx].localIdx = localMap[instr.args[argIdx].localIdx];

            // Translate the output slot
            if (instr.outSlot !is NULL_LOCAL)
                instr.outSlot = localMap[instr.outSlot];
        }
    }

    // Extend the caller stack frame for the callee
    caller.numLocals += callee.numLocals;

    //
    // Callee basic block copying
    //

    // Get the execution count of the call site
    auto callCount = cast(uint64_t)callSite.block.execCount;

    // Get the execution count of the callee's entry block
    auto entryCount = cast(uint64_t)callee.entryBlock.execCount;

    // Map of callee blocks to copied blocks
    IRBlock[IRBlock] blockMap;

    // Flags indicating if the callee uses the hidden arguments
    bool usesArgc = false;
    bool usesClos = false;
    bool usesThis = false;

    // Slot index for the first callee argument
    auto arg0Slot = callee.numLocals - callee.numParams;

    // Bit set to keep track of arguments slots written to
    auto writtenArgs = new BitSet(numArgs);

    // For each callee block
    for (auto block = callee.firstBlock; block !is null; block = block.next)
    {
        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // Check if the hidden arguments are used
            foreach (argIdx, arg; instr.args)
            {
                if (instr.opcode.getArgType(argIdx) == OpArg.LOCAL)
                {
                    auto argSlot = instr.args[argIdx].localIdx;
                    usesArgc = usesArgc || (argSlot == callee.argcSlot);
                    usesClos = usesClos || (argSlot == callee.closSlot);
                    usesThis = usesThis || (argSlot == callee.thisSlot);
                }
            }

            // Keep track of arguments written to
            if (instr.outSlot - arg0Slot < writtenArgs.length)
                writtenArgs.add(instr.outSlot - arg0Slot);
        }

        // Copy the block and add it to the caller
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
            // Remap uses of argument slots that were never written to
            foreach (argIdx, arg; instr.args)
            {
                if (instr.opcode.getArgType(argIdx) == OpArg.LOCAL)
                {
                    auto argNo = instr.args[argIdx].localIdx - arg0Slot;
                    if (argNo < numArgs && !writtenArgs.has(argNo))
                        instr.args[argIdx].localIdx = callSite.args[2 + argNo].localIdx;
                }
            }

            // Tanslate targets
            if (instr.target)
                instr.target = blockMap[instr.target];
            if (instr.excTarget)
                instr.excTarget = blockMap[instr.excTarget];

            // If this is a call instruction
            if (instr.opcode.isCall)
            {
                // Add the callee function to the list of
                // inlined functions at this call site
                caller.inlineMap[instr] ~= callee;

                // Copy the call profiles from the callee
                auto origCall = orig.lastInstr;
                assert (origCall.opcode.isCall);
                caller.callCounts[instr] = callee.callCounts.get(origCall, uint64_t[IRFunction].init);
            }

            // If this is a return instruction
            if (instr.opcode == &RET)
            {
                // Remove the return instruction
                block.remInstr(instr);

                // Move the return value to the return value slot
                if (callSite.outSlot !is NULL_LOCAL)
                {
                    block.addInstr(new IRInstr(
                        &MOVE,
                        callSite.outSlot,
                        instr.args[0].localIdx
                    ));
                }

                // Jump to the call continuation block
                block.addInstr(IRInstr.jump(callSite.target));
            }
        }

        // Adjust the block execution count
        block.execCount = (block.execCount * callCount) / entryCount;
    }

    //
    // Callee test and call patching
    //

    // Move the call instruction to a new basic block,
    // This will be our fallback (uninlined call)
    auto callBlock = callSite.block;
    auto regCall = caller.newBlock("call_reg");
    callBlock.remInstr(callSite);
    regCall.addInstr(callSite);

    // Load the function pointer from the closure object
    auto ofsInstr = callBlock.addInstr(IRInstr.intCst(callee.closSlot, CLOS_OFS_FPTR));
    auto loadInstr = callBlock.addInstr(
        new IRInstr(
            &LOAD_RAWPTR, 
            callee.closSlot, 
            callSite.args[0].localIdx,
            ofsInstr.outSlot
        )
    );

    // Set a constant for the function pointer
    auto ptrInstr = callBlock.addInstr(new IRInstr(&SET_RAWPTR));
    ptrInstr.outSlot = callee.thisSlot;
    ptrInstr.args.length = 1;
    ptrInstr.args[0].ptrVal = cast(ubyte*)callee;

    // Get the inlined entry block for the callee function
    auto entryBlock = blockMap[callee.entryBlock];

    // If the function pointer matches, jump to the callee's entry
    auto testInstr = callBlock.addInstr(
        new IRInstr(
            &EQ_RAWPTR,
            callee.closSlot,
            loadInstr.outSlot,
            ptrInstr.outSlot
        )
    );
    callBlock.addInstr(IRInstr.ifTrue(testInstr.outSlot, entryBlock, regCall));

    // Copy the visible arguments that were written to, in reverse order
    foreach (argIdx, arg; callSite.args[2..$])
    {
        if (writtenArgs.has(argIdx))
        {
            auto dstIdx = cast(LocalIdx)(callee.numLocals - (numArgs - argIdx));
            entryBlock.addInstrBefore(
                new IRInstr(&MOVE, dstIdx, arg.localIdx),
                entryBlock.firstInstr
            );
        }
    }

    // Copy the closure argument
    if (usesClos)
    {
        entryBlock.addInstrBefore(
            new IRInstr(&MOVE, callee.closSlot, callSite.args[0].localIdx),
            entryBlock.firstInstr
        );
    }

    // Copy the "this" argument
    if (usesThis)
    {
        entryBlock.addInstrBefore(
            new IRInstr(&MOVE, callee.thisSlot, callSite.args[1].localIdx),
            entryBlock.firstInstr
        );
    }

    // Set the argument count
    if (usesArgc)
    {
        entryBlock.addInstrBefore(
            IRInstr.intCst(callee.argcSlot, cast(uint)numArgs),
            entryBlock.firstInstr
        );
    }

    // Return the mapping of pre-inlining local indices to post-inlining indices 
    return localMap;
}

