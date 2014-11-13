/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013-2014, Maxime Chevalier-Boisvert. All rights reserved.
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
import std.algorithm;
import ir.ir;
import ir.ops;
import ir.ast;
import runtime.vm;
import runtime.layout;
import runtime.object;
import util.bitset;
import options;

/**
Selectively inline callees into a function
*/
void inlinePass(VM vm, IRFunction caller)
{
    static bool funHasLoop(IRFunction fun)
    {
        for (auto block = fun.firstBlock; block !is null; block = block.next)
            if (block.name.startsWith("for") ||
                block.name.startsWith("while") ||
                block.name.startsWith("do"))
                return true;

        return false;
    }

    // If inlining is disabled, do nothing
    if (opts.noinline)
        return;

    //bool isUnit = caller.isUnit;
    //bool hasLoop = funHasLoop(caller);

    //writeln("inlinePass for ", caller.getName);

    // For each block of the caller function
    for (auto block = caller.firstBlock; block !is null; block = block.next)
    {
        if (block.lastInstr is null)
            continue;

        // If this is not a primitive call, skip it
        if (block.lastInstr.opcode !is &CALL_PRIM)
            continue;

        auto callSite = block.lastInstr;

        // Get the function name string (D string)
        auto strArg = cast(IRString)callSite.getArg(0);
        assert (strArg !is null);
        auto nameStr = strArg.str;

        // Get the primitve function from the global object
        auto closVal = getProp(vm, vm.globalObj, nameStr);
        assert (
            closVal.tag is Tag.CLOSURE ||
            (caller.isUnit() && caller.getName.canFind("runtime")),
            format(
                "cannot inline non-closure \"%s\" in \"%s\"", 
                nameStr, 
                caller.getName
            )
        );

        // If the closure is not available, skip it
        if (closVal.tag !is Tag.CLOSURE)
            continue;

        assert (closVal.word.ptrVal !is null);
        auto callee = getFunPtr(closVal.word.ptrVal);

        // If this combination is not inlinable, skip it
        if (inlinable(callSite, callee) is false)
            continue;

        if (caller is callee)
            continue;

        if (callee.entryBlock is null)
        {
            astToIR(vm, callee.ast, callee);
        }

        auto name = callee.getName();

        if (callee.numBlocks > 4
            && !name.startsWith("$rt_valIsObj")
            && !name.startsWith("$rt_minus")
            && !name.startsWith("$rt_addInt")
            && !name.startsWith("$rt_addIntFloat")
            && !name.startsWith("$rt_subInt")
            && !name.startsWith("$rt_subIntFloat")
            && !name.startsWith("$rt_mulIntFloat")
            && !name.startsWith("$rt_divIntFloat")
            && !name.startsWith("$rt_modInt")
            && !name.startsWith("$rt_and")
            && !name.startsWith("$rt_or")
            && !name.startsWith("$rt_xor")
            && !name.startsWith("$rt_lsft")
            && !name.startsWith("$rt_rsft")
            && !name.startsWith("$rt_ursft")
            && !name.startsWith("$rt_ltIntFloat")
            && !name.startsWith("$rt_leIntFloat")
            && !name.startsWith("$rt_gtIntFloat")
            && !name.startsWith("$rt_geIntFloat")
            && !name.startsWith("$rt_eqInt")
            && !name.startsWith("$rt_eqNull")
            && !name.startsWith("$rt_neNull")
            && !name.startsWith("$rt_getPropField")
            && !name.startsWith("$rt_getStrMethod")
            && !name.startsWith("$rt_getPropElem")
            && !name.startsWith("$rt_getPropLength")
            && !name.startsWith("$rt_setPropField")
            && !name.startsWith("$rt_setPropElem")
            && !name.startsWith("$rt_setArrElemNoCheck")
            && !name.startsWith("$rt_setProto")
            && !name.startsWith("$rt_newObj")
            && !name.startsWith("$rt_newArr")
            && !name.startsWith("$rt_ctorNewThis")
            && !name.startsWith("$rt_getGlobalInl")
            && !name.startsWith("$rt_setGlobalInl")
            && !name.startsWith("$rt_ropeToStr")
            && !name.startsWith("$rt_isShadowed")
        )
            continue;

        if (name.startsWith("$rt_throw"))
            continue;

        // If this is a global property read
        if (name.startsWith("$rt_getGlobalInl"))
        {
            auto propName = callSite.getArgStrCst(1);
            assert (propName !is null);

            auto globalObj = vm.globalObj.word.ptrVal;
            auto objShape = cast(ObjShape)obj_get_shape(globalObj);
            auto defShape = objShape.getDefShape(propName);

            // If the property is defined and is a constant
            if (defShape && !defShape.writable && !defShape.configurable)
            {
                auto val = getProp(vm, vm.globalObj, propName);

                IRConst newVal;
                if (val.tag is Tag.INT32)
                    newVal = IRConst.int32Cst(val.word.int32Val);
                else if (val.tag is Tag.FLOAT64)
                    newVal = IRConst.float64Cst(val.word.floatVal);
                else if (val is UNDEF)
                    newVal = IRConst.undefCst;

                if (newVal)
                {
                    // Replace uses of the call by the constant
                    callSite.replUses(newVal);

                    // Replace the getGlobal call by a direct jump
                    auto desc = callSite.getTarget(0);
                    auto jump = block.addInstr(new IRInstr(&JUMP));
                    auto newDesc = jump.setTarget(0, desc.target);
                    foreach (arg; desc.args)
                        newDesc.setPhiArg(cast(PhiNode)arg.owner, arg.value);
                    block.delInstr(callSite);

                    continue;
                }
            }
        }

        //writefln("inlining %s in %s (%s blocks)", name, caller.getName, callee.numBlocks);

        // Inline the callee
        inlineCall(callSite, callee);

        //writefln("  inlined");
    }

    //writeln("inlinePass done");
}

/**
Test if a function is inlinable at a call site
*/
bool inlinable(IRInstr callSite, IRFunction callee)
{
    auto caller = callSite.block.fun;

    // Not support for new for now, avoids complicated return logic
    if (callSite.opcode !is &CALL &&
        callSite.opcode !is &CALL_PRIM)
        return false;

    // No support for inlining within try blocks for now
    if (callSite.getTarget(1) !is null)
        return false;

    // No support for functions using the "arguments" object
    if (callee.ast.usesArguments == true)
        return false;

    // No support for argument count mismatch
    auto numArgs = callSite.numArgs;
    if ((callSite.opcode is &CALL && numArgs - 2 != callee.numParams) ||
        (callSite.opcode is &CALL_PRIM && numArgs - 1 != callee.numParams))
        return false;

    // Inlining is possible
    return true;
}

/**
Inline a callee function at a call site
*/
PhiNode inlineCall(IRInstr callSite, IRFunction callee)
{
    // Ensure that this inlining is possible
    assert (inlinable(callSite, callee));

    // Get the caller function
    auto caller = callSite.block.fun;
    assert (caller !is null);

    // Get the number of visible arguments passed at the call site
    size_t numArgs;
    if (callSite.opcode is &CALL_PRIM)
        numArgs = callSite.numArgs - 1;
    else if (callSite.opcode is &CALL)
        numArgs = callSite.numArgs - 2;
    else
        assert (false);

    // Get the call continuation branch and successor block
    auto contBranch = callSite.getTarget(0);
    auto contBlock = contBranch.target;

    // Create a block for the return value merging
    auto mergeBlock = caller.newBlock("call_merge");

    // Create a phi node in the call continuation for the return value
    auto retPhi = mergeBlock.addPhi(new PhiNode());

    // Jump to the call continuation block
    auto jumpInstr = mergeBlock.addInstr(new IRInstr(&JUMP));
    auto jumpDesc = jumpInstr.setTarget(0, contBlock);

    // Copy arguments from the call continuation jump
    foreach (arg; contBranch.args)
        jumpDesc.setPhiArg(cast(PhiNode)arg.owner, arg.value);

    //
    // Callee basic block copying and translation
    //

    // Map of callee blocks to copies
    IRBlock[IRBlock] blockMap;

    // Map of callee instructions and phi nodes to copies
    IRValue[IRValue] valMap;

    // Map the hidden argument values to call site parameters
    valMap[callee.raVal] = IRConst.nullCst;
    valMap[callee.closVal] = callSite.getArg(0);
    valMap[callee.thisVal] = (callSite.opcode is &CALL)? callSite.getArg(1):IRConst.nullCst;
    valMap[callee.argcVal] = IRConst.int32Cst(cast(int32_t)numArgs);

    // Map the visible parameters to call site parameters
    foreach (param; callee.paramMap)
    {
        auto argIdx = param.idx - NUM_HIDDEN_ARGS;
        if (argIdx < numArgs)
            valMap[param] = callSite.getArg(callSite.numArgs - numArgs + argIdx);
        else
            valMap[param] = IRConst.undefCst;
    }

    // For each callee block
    auto lastBlock = callee.lastBlock;
    for (auto block = callee.firstBlock;; block = block.next)
    {
        assert (
            block !is null,
            "null block"
        );

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
            // If this is the global value
            if (instr is callee.globalVal)
            {
                // Map it to the caller global value
                valMap[callee.globalVal] = caller.globalVal;
            }
            else
            {
                // Create a new instruction (copy)
                auto newInstr = newBlock.addInstr(
                    new IRInstr(instr.opcode, instr.numArgs)
                );
                valMap[instr] = newInstr;
            }
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
            assert (newInstr.block is newBlock || newInstr is caller.globalVal);

            if (oldInstr.srcPos)
                newInstr.srcPos = callSite.srcPos;

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

                auto newTarget = blockMap[desc.target];
                auto newBranch = newInstr.setTarget(tIdx, newTarget);

                foreach (arg; desc.args)
                {
                    auto newPhi = cast(PhiNode)valMap.get(arg.owner, null);
                    auto newArg = valMap.get(arg.value, arg.value);
                    newBranch.setPhiArg(newPhi, newArg);
                }
            }

            /*
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
            */

            // If this is a return instruction
            if (newInstr.opcode == &RET)
            {
                // Get the return value
                auto retVal = newInstr.getArg(0);

                // Remove the return instruction
                newBlock.delInstr(newInstr);

                // Jump to the merge block
                auto jump = newBlock.addInstr(new IRInstr(&JUMP));
                auto desc = jump.setTarget(0, mergeBlock);

                // Set the return phi argument
                desc.setPhiArg(retPhi, retVal);
            }
        }
    }
 
    //
    // Callee test and call patching
    //

    // Get the block the call site belongs to
    auto callBlock = callSite.block;

    // Get the inlined entry block for the callee function
    auto entryBlock = blockMap[callee.entryBlock];

    // Replace uses of the call instruction by uses of the return phi
    callSite.replUses(retPhi);

    // If this is a static primitive call
    if (callSite.opcode is &CALL_PRIM)
    {
        // Remove the original call instruction
        callBlock.delInstr(callSite);

        // Add a direct jump to the callee entry block
        auto jump = callBlock.addInstr(new IRInstr(&JUMP));
        jump.setTarget(0, entryBlock);
    }
    else
    {
        assert (false);

        /*
        // Move the call instruction to a new basic block,
        // This will be our fallback (uninlined call)
        auto regCallBlock = caller.newBlock("call_reg");
        callBlock.moveInstr(callSite, regCallBlock);

        // Make the regular call continue to the call merge block
        auto regCallDesc = callSite.setTarget(0, mergeBlock);
        regCallDesc.setPhiArg(retPhi, callSite);

        // Create a function pointer for the callee function
        auto ptrConst = new IRFunPtr(callee);

        // If the function pointer matches, jump to the callee's entry
        auto ifInstr = callBlock.addInstr(
            new IRInstr(
                &IF_EQ_FUN,
                callSite.getArg(0),
                ptrConst
            )
        );
        ifInstr.setTarget(0, blockMap[callee.entryBlock]);
        ifInstr.setTarget(1, regCallBlock);
        */
    }

    // Return the return merge phi node
    return retPhi;
}

