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
import ir.ops;
import interp.object;
import util.bitset;

/// Maximum number of blocks a caller may have before inlining
const size_t MAX_CALLER_BLOCKS = 100;

/// Maximum number of blocks a callee may have before inlining
const size_t MAX_CALLEE_BLOCKS = 35;

/**
Test if a function is inlinable at a call site
*/
bool inlinable(IRInstr callSite, IRFunction callee)
{
    auto caller = callSite.block.fun;

    // Not support for new for now, avoids complicated return logic
    if (callSite.opcode !is &CALL)
        return false;

    // No support for inlinin within try blocks for now
    if (callSite.getTarget(1) !is null)
        return false;

    // No support for functions using the "arguments" object
    if (callee.ast.usesArguments == true)
        return false;

    // No support for argument count mismatch
    auto numArgs = callSite.numArgs - 2;
    if (numArgs != callee.numParams)
        return false;

    // If the caller is too big to inline into
    size_t callerBlocks = 0;
    for (auto block = caller.firstBlock; block !is null; block = block.next)
        callerBlocks++;
    if (callerBlocks > MAX_CALLER_BLOCKS)
        return false;

    // If the callee is too big to be inlined
    size_t calleeBlocks = 0;
    for (auto block = callee.firstBlock; block !is null; block = block.next)
        calleeBlocks++;
    if (calleeBlocks > MAX_CALLEE_BLOCKS)
        return false;

    // Inlining is possible
    return true;
}

/**
Inline a callee function at a call site
*/
void inlineCall(IRInstr callSite, IRFunction callee)
{
    // Ensure that this inlining is possible
    assert (inlinable(callSite, callee));

    // Get the caller function
    auto caller = callSite.block.fun;
    assert (caller !is null);

    // Get the number of arguments passed at the call site
    auto numArgs = callSite.numArgs - 2;

    // Get the call continuation branch and successor block
    auto contDesc = callSite.getTarget(0);
    auto contBlock = contDesc.succ;

    // Create a new block to merge inlined returns
    auto retBlock = callSite.block.fun.newBlock("call_ret");

    // Create a phi node for the return value, add it to the call continuation
    auto retPhi = retBlock.addPhi(new PhiNode());

    // Create a jump to the call continuation block
    auto retJump = retBlock.addInstr(new IRInstr(&JUMP));
    auto retDesc = retJump.setTarget(0, contBlock);

    // Set phi arguments for the jump to the continuation block
    foreach (arg; contDesc.args)
    {
        retDesc.setPhiArg(
            cast(PhiNode)arg.owner,
            (arg.value is callSite)? retPhi:callSite
        );
    }

    //
    // Callee basic block copying and translation
    //

    // Get the execution count of the call site
    auto callCount = cast(uint64_t)callSite.block.execCount;

    // Get the execution count of the callee's entry block
    auto entryCount = cast(uint64_t)callee.entryBlock.execCount;

    // Map of callee blocks to copies
    IRBlock[IRBlock] blockMap;

    // Map of callee instructions and phi nodes to copies
    IRValue[IRValue] valMap;

    // Map the hidden argument values to call site parameters
    valMap[callee.raVal] = IRConst.nullCst;
    valMap[callee.closVal] = callSite.getArg(0);
    valMap[callee.thisVal] = callSite.getArg(1);
    valMap[callee.argcVal] = IRConst.int32Cst(cast(int32_t)(callSite.numArgs - 2));

    // Map the visible parameters to call site parameters
    foreach (param; callee.paramMap)
    {
        auto argIdx = param.idx - NUM_HIDDEN_ARGS;
        if (argIdx < numArgs)
            valMap[param] = callSite.getArg(2 + argIdx);
        else
            valMap[param] = IRConst.undefCst;
    }

    // For each callee block
    auto lastBlock = callee.lastBlock;
    for (auto block = callee.firstBlock;; block = block.next)
    {
        assert (block !is null);

        // Copy the block and add it to the caller
        auto newBlock = caller.newBlock(block.name);
        blockMap[block] = newBlock;

        // For each phi node
        for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
        {
            // If this not a function parameter
            if (cast(FunParam)phi is null)
            {
                // Create a new phi node (copy)
                valMap[phi] = newBlock.addPhi(new PhiNode());
            }
        }

        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // Create a new instruction (copy)
            valMap[instr] = newBlock.addInstr(
                new IRInstr(instr.opcode, instr.numArgs)
            );
        }

        // If this is the last block to inline, stop
        if (block is lastBlock)
            break;
    }

    // For each block
    foreach (oldBlock, newBlock; blockMap)
    {
        // For each instruction
        for (auto oldInstr = oldBlock.firstInstr; oldInstr !is null; oldInstr = oldInstr.next)
        {
            // Get the corresponding copied instruction
            auto newInstr = cast(IRInstr)valMap.get(oldInstr, null);
            assert (newInstr !is null);
            assert (newInstr.block is newBlock);

            // Translate the instruction arguments
            for (size_t aIdx = 0; aIdx < oldInstr.numArgs; ++aIdx)
            {
                auto arg = oldInstr.getArg(aIdx);
                assert (arg in valMap || cast(IRDstValue)arg is null);
                auto newArg = valMap.get(arg, arg);
                newInstr.setArg(aIdx, newArg);
            }

            // Translate the branch targets
            for (size_t tIdx = 0; tIdx < oldInstr.MAX_TARGETS; ++tIdx)
            {
                auto desc = oldInstr.getTarget(tIdx);
                if (desc is null)
                    continue;

                auto newDesc = new BranchDesc(newBlock, blockMap[desc.succ]);

                foreach (arg; desc.args)
                {
                    auto newPhi = cast(PhiNode)valMap.get(arg.owner, null);
                    auto newArg = valMap.get(arg.value, arg.value);
                    newDesc.setPhiArg(newPhi, newArg);
                }

                newInstr.setTarget(tIdx, newDesc);
            }

            // If this is a call instruction
            if (newInstr.opcode.isCall)
            {
                // Add the callee function to the list of
                // inlined functions at this call site
                caller.inlineMap[newInstr] ~= callee.inlineMap.get(oldInstr, []) ~ callee;

                // Copy the call profiles from the callee
                caller.callCounts[newInstr] = callee.callCounts.get(
                    oldInstr, 
                    uint64_t[IRFunction].init
                );
            }

            // If this is a return instruction
            if (newInstr.opcode == &RET)
            {
                // Get the return value
                auto retVal = oldInstr.getArg(0);

                // Remove the return instruction
                newBlock.delInstr(newInstr);

                // Jump to the return block
                auto jump = newBlock.addInstr(new IRInstr(&JUMP));
                auto desc = jump.setTarget(0, retBlock);

                // Add a phi argument for the return value
                desc.setPhiArg(retPhi, valMap.get(retVal, retVal));
            }
        }

        // Adjust the block execution count
        newBlock.execCount = (oldBlock.execCount * callCount) / entryCount;
    }
 
    //
    // Callee test and call patching
    //

    // Copy the call instruction to a new basic block,
    // This will be our fallback (uninlined call)
    auto callBlock = callSite.block;
    auto regCallBlock = caller.newBlock("call_reg");
    auto newCallInstr = new IRInstr(callSite.opcode, callSite.numArgs);
    regCallBlock.addInstr(newCallInstr);

    // Replace uses of the call instruction by uses of the return phi
    callSite.replUses(retPhi);


    // Copy the call arguments
    for (size_t aIdx = 0; aIdx < callSite.numArgs; ++aIdx)
        newCallInstr.setArg(aIdx, callSite.getArg(aIdx));

    // Copy the branch descriptors
    for (size_t tIdx = 0; tIdx < callSite.MAX_TARGETS; ++tIdx)
    {
        auto desc = callSite.getTarget(tIdx);
        if (desc is null)
            continue;

        auto newDesc = new BranchDesc(regCallBlock, desc.succ);
        foreach (arg; desc.args)
            newDesc.setPhiArg(cast(PhiNode)arg.owner, arg.value);
        newCallInstr.setTarget(tIdx, newDesc);
    }

    // Remove the old call instruction
    callBlock.delInstr(callSite);

    // Add the regular call as an argument for the return phi
    newCallInstr.getTarget(0).setPhiArg(retPhi, newCallInstr);

    // Load the function pointer from the closure object
    auto loadInstr = callBlock.addInstr(
        new IRInstr(
            &LOAD_RAWPTR, 
            newCallInstr.getArg(0),
            IRConst.int32Cst(CLOS_OFS_FPTR)
        )
    );

    // Create a pointer constant for the callee function
    auto ptrConst = new IRRawPtr(cast(ubyte*)callee);

    // Get the inlined entry block for the callee function
    auto entryBlock = blockMap[callee.entryBlock];

    // If the function pointer matches, jump to the callee's entry
    auto testInstr = callBlock.addInstr(
        new IRInstr(
            &EQ_RAWPTR,
            loadInstr,
            ptrConst
        )
    );
    auto ifInstr = callBlock.addInstr(new IRInstr(&IF_TRUE, testInstr));
    ifInstr.setTarget(0, blockMap[callee.entryBlock]);
    ifInstr.setTarget(1, regCallBlock);
}

