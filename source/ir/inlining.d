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

    // Map of pre-inlining local indices to post-inlining indices 
    // Only for locals of the caller function, used for on-stack replacement
    LocalIdx[LocalIdx] localMap;

    // Remap the caller locals to add callee locals
    for (LocalIdx i = 0; i < caller.numLocals; ++i)
        localMap[i] = i + callee.numLocals;

    // Remap the caller identifier
    foreach (id, localIdx; caller.cellMap)
        caller.cellMap[id] = localIdx + callee.numLocals;
    foreach (id, localIdx; caller.localMap)
        caller.localMap[id] = localIdx + callee.numLocals;

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
            // Translate local indices
            foreach (argIdx, arg; instr.args)
                if (instr.opcode.getArgType(argIdx) == OpArg.LOCAL)
                    instr.args[argIdx].localIdx = localMap[instr.args[argIdx].localIdx];

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
            }

            // If this is a return instruction
            if (instr.opcode == &RET)
            {
                // Remove the return instruction
                block.remInstr(instr);

                // Move the return value to the return value slot
                block.addInstr(new IRInstr(
                    &MOVE,
                    localMap[callSite.outSlot],
                    instr.args[0].localIdx
                ));

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
            localMap[callSite.args[0].localIdx], 
            ofsInstr.outSlot
        )
    );

    // Set a constant for the function pointer
    auto ptrInstr = callBlock.addInstr(new IRInstr(&SET_RAWPTR));
    ptrInstr.outSlot = callee.thisSlot;
    ptrInstr.args.length = 1;
    ptrInstr.args[0].ptrVal = cast(ubyte*)callee;

    // Get the entry block for the callee function
    auto entryBlock = blockMap[callee.entryBlock];

    // If the function pointer matches, jump to the callee's entry
    auto testInstr = callBlock.addInstr(
        new IRInstr(
            &EQ_RAWPTR,
            loadInstr.outSlot,
            ptrInstr.outSlot
        )
    );
    callBlock.addInstr(IRInstr.ifTrue(testInstr.outSlot, entryBlock, regCall));






    // Copy the visible arguments
    foreach (argIdx, arg; callSite.args[2..$])
    {
        auto dstIdx = cast(LocalIdx)(callee.numLocals - NUM_HIDDEN_ARGS + argIdx - 2);
        entryBlock.addInstrBefore(
            new IRInstr(&MOVE, localMap[arg.localIdx], dstIdx),
            entryBlock.firstInstr
        );
    }

    // Copy the closure and this arguments
    entryBlock.addInstrBefore(
        new IRInstr(&MOVE, localMap[callSite.args[0].localIdx], callee.closSlot),
        entryBlock.firstInstr
    );
    entryBlock.addInstrBefore(
        new IRInstr(&MOVE, localMap[callSite.args[1].localIdx], callee.thisSlot),
        entryBlock.firstInstr
    );

    // Set the argument count
    entryBlock.addInstrBefore(
        IRInstr.intCst(cast(uint)numArgs, callee.argcSlot),
        entryBlock.firstInstr
    );

    // Return the mapping of pre-inlining local indices to post-inlining indices 
    return localMap;
}

