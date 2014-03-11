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

module ir.peephole;

import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.conv;
import ir.ir;
import ir.livevars;
import ir.ops;
import runtime.vm;

void optIR(IRFunction fun, IRBlock target = null, LiveInfo liveInfo = null)
{
    //writeln("peephole pass for ", fun.getName);

    /// Test if a value is available at the target block
    bool isAvail(IRValue value)
    {
        auto dstValue = cast(IRDstValue)value;

        if (dstValue is null || liveInfo is null)
            return true;

        return liveInfo.liveAfterPhi(dstValue, target);
    }

    // CFG changed flag
    bool changed = true;

    /// Remove and destroy a block
    void delBlock(ref IRBlock block)
    {
        //writeln("*** deleting block ", block.getName());

        assert (
            block !is target,
            "deleting target block"
        );

        // Check that the block has no incoming branches
        debug
        {
            for (auto zblock = fun.firstBlock; zblock !is null; zblock = zblock.next)
            {
                auto branch = zblock.lastInstr;
                if (branch is null)
                    continue;

                for (size_t tIdx = 0; tIdx < IRInstr.MAX_TARGETS; ++tIdx)
                {
                    auto target = branch.getTarget(tIdx);
                    if (target !is null && target.target is block)
                        assert (false, "block is still target!");
                }
            }
        }

        // Set the changed flag
        changed = true;

        // Remove and delete the block
        fun.delBlock(block);

        // Check that the block was properly destroyed
        debug
        {
            assert (block.firstPhi is null);
            assert (block.firstInstr is null);
        }

        //writeln("block deleted");
    }

    // Remove and destroy a phi node
    void delPhi(PhiNode phi)
    {
        //writeln("*** deleting phi node ", phi.getName());

        assert (
            phi.hasNoUses || (phi.hasOneUse && phi.getFirstUse.owner is phi),
            "cannot remove phi node which still has uses:\n" ~
            phi.toString()
        );

        // Set the changed flag
        changed = true;

        // Remove and delete the phi node
        phi.block.delPhi(phi);

        debug
        {
            for (auto block = fun.firstBlock; block !is null; block = block.next)
            {
                // Check that there are no arguments to the deleted phi node
                auto branch = block.lastInstr;
                if (branch)
                {
                    for (size_t tIdx = 0; tIdx < IRInstr.MAX_TARGETS; ++tIdx)
                    {
                        auto target = branch.getTarget(tIdx);
                        if (target !is null)
                        {
                            assert (
                                target.getPhiArg(phi) is null,
                                "target has arg to deleted phi"
                            );
                        }
                    }
                }

                // Check that no phi uses the deleted phi node
                for (auto zphi = block.firstPhi; zphi !is null; zphi = zphi.next)
                {
                    for (size_t iIdx = 0; iIdx < zphi.block.numIncoming; ++iIdx)
                    {
                        auto ibranch = zphi.block.getIncoming(iIdx);
                        assert (ibranch !is null);
                        auto arg = ibranch.getPhiArg(zphi);
                        assert (
                            arg !is phi, 
                            "phi uses deleted phi in block:\n" ~
                            zphi.block.getName()
                        );
                    }
                }

                // Check that no instruction uses the deleted phi node
                for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
                {
                    for (size_t i = 0; i < instr.numArgs; ++i)
                    {
                        auto arg = instr.getArg(i);
                        assert (arg !is phi, "instr uses deleted phi");
                    }
                }
            }
        }

        //writeln("phi deleted");
    }

    // Remove and destroy an instruction
    void delInstr(IRInstr instr)
    {
        //writeln("*** deleting instr ", instr);

        assert (
            instr.hasNoUses
        );

        // Set the changed flag
        changed = true;

        instr.block.delInstr(instr);
    }

    // Until there are no more changes;
    size_t passNo;
    for (passNo = 1; changed is true; passNo++)
    {
        //writeln("passNo=", passNo);

        // Reset the changed flag
        changed = false;

        // For each block of the function
        BLOCK_LOOP:
        for (auto block = fun.firstBlock; block !is null; block = block.next)
        {
            // If this block has no incoming branches, remove it
            if (block !is fun.entryBlock && block.numIncoming is 0 && block !is target)
            {
                delBlock(block);
                continue BLOCK_LOOP;
            }

            // For each phi node of the block
            PHI_LOOP:
            for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
            {
                // Delete all phi assignments of the form:
                // Vi <- phi(...Vi...Vi...)
                // with 0+ Vi
                //
                // If a phi assignment has the form:
                // Vi <- phi(...Vi...Vj...Vi...Vj...)
                // with 0+ Vi and 1+ Vj (where Vi != Vj)
                //
                // Then delete the assignment and rename
                // all occurences of Vi to Vj

                //writeln("phi: ", phi.getName());

                // If this phi node is a function parameter, skip it
                if (cast(FunParam)phi)
                    continue;

                // If this phi node has no uses, remove it
                if (phi.hasNoUses)
                {
                    delPhi(phi);
                    continue;
                }

                size_t numVi = 0;
                size_t numVj = 0;
                IRValue Vj = null;

                // Count the kinds of arguments to the phi node
                for (size_t iIdx = 0; iIdx < phi.block.numIncoming; ++iIdx)
                {
                    auto branch = phi.block.getIncoming(iIdx);
                    assert (branch !is null);
                    auto arg = branch.getPhiArg(phi);

                    if (arg is phi)
                    {
                        numVi++;
                    }
                    else if (arg is Vj || Vj is null)
                    {
                        numVj++;
                        Vj = arg;
                    }
                }

                // If this phi node has the form:
                // Vi <- phi(...Vi...Vi...)
                // it is a tautological phi node
                if (numVi == phi.block.numIncoming && phi.hasOneUse)
                {
                    // Remove the phi node
                    delPhi(phi);
                    continue;
                }

                // If this phi assignment has the form:
                // Vi <- phi(...Vi...Vj...Vi...Vj...)
                // 0 or more Vi and 1 or more Vj
                if (numVi + numVj == phi.block.numIncoming && numVj > 0 && isAvail(Vj))
                {
                    //print('Renaming phi: ' + instr);

                    // Rename all occurences of Vi to Vj
                    assert (!Vj.hasNoUses);
                    phi.replUses(Vj);

                    // Remove the phi node
                    delPhi(phi);
                    continue;
                }

            } // foreach phi

            // For each instruction of the block
            INSTR_LOOP:
            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
            {
                auto op = instr.opcode;

                //writeln("instr: ", instr);

                // If this instruction has no uses and is pure, remove it
                if (instr.hasNoUses && !op.isImpure && !op.isBranch)
                {
                    //writeln("removing dead: ", instr);
                    delInstr(instr);
                    continue INSTR_LOOP;
                }

                // Constant folding on is_i32
                if (op == &IS_I32)
                {
                    auto arg0 = instr.getArg(0);
                    auto cst0 = cast(IRConst)arg0;

                    if (cst0)
                    {
                        instr.replUses(
                            (cst0.type is Type.INT32)? 
                            IRConst.trueCst:IRConst.falseCst
                        );

                        delInstr(instr);
                        continue INSTR_LOOP;
                    }
                }

                // Constant folding on int32 add instructions
                if (op == &ADD_I32)
                {
                    auto arg0 = instr.getArg(0);
                    auto arg1 = instr.getArg(1);
                    auto cst0 = cast(IRConst)arg0;
                    auto cst1 = cast(IRConst)arg1;

                    if (cst0 && cst1 && cst0.isInt32 && cst1.isInt32)
                    {
                        auto v0 = cast(int64_t)cst0.int32Val; 
                        auto v1 = cast(int64_t)cst1.int32Val;
                        auto r = v0 + v1;

                        if (r >= int32_t.min && r <= int32_t.max)
                        {
                            instr.replUses(IRConst.int32Cst(cast(int32_t)r));
                            delInstr(instr);
                            continue INSTR_LOOP;
                        }
                    }

                    if (cst0 && cst0.isInt32 && cst0.int32Val is 0 && isAvail(arg1))
                    {
                        instr.replUses(arg1);
                        delInstr(instr);
                        continue INSTR_LOOP;
                    }

                    if (cst1 && cst1.isInt32 && cst1.int32Val is 0 && isAvail(arg0))
                    {
                        instr.replUses(arg0);
                        delInstr(instr);
                        continue INSTR_LOOP;
                    }
                }

                // Constant folding on int32 mul instructions
                if (op == &MUL_I32)
                {
                    auto arg0 = instr.getArg(0);
                    auto arg1 = instr.getArg(1);
                    auto cst0 = cast(IRConst)arg0;
                    auto cst1 = cast(IRConst)arg1;

                    if (cst0 && cst1 && cst0.isInt32 && cst1.isInt32)
                    {
                        auto v0 = cast(int64_t)cst0.int32Val; 
                        auto v1 = cast(int64_t)cst1.int32Val;
                        auto r = v0 * v1;

                        if (r >= int32_t.min && r <= int32_t.max)
                        {
                            instr.replUses(IRConst.int32Cst(cast(int32_t)r));
                            delInstr(instr);
                            continue INSTR_LOOP;
                        }
                    }

                    if (cst0 && cst0.isInt32 && cst0.int32Val is 1 && isAvail(arg1))
                    {
                        instr.replUses(arg1);
                        delInstr(instr);
                        continue INSTR_LOOP;
                    }

                    if (cst1 && cst1.isInt32 && cst1.int32Val is 1 && isAvail(arg0))
                    {
                        instr.replUses(arg0);
                        delInstr(instr);
                        continue INSTR_LOOP;
                    }
                }

                // If this is a branch instruction
                if (op.isBranch)
                {
                    // If this is an unconditional jump
                    if (op is &JUMP)
                    {
                        auto branch = instr.getTarget(0);
                        auto succ = branch.target;

                        // If the successor has no phi nodes and only one predecessor
                        if (branch.args.length is 0 &&
                            succ.numIncoming is 1 &&
                            succ !is target &&
                            succ !is block)
                        {
                            // Move instructions from the successor into the predecessor
                            while (succ.firstInstr !is null)
                                succ.moveInstr(succ.firstInstr, block);

                            // Remove the jump instruction
                            delInstr(instr);

                            continue INSTR_LOOP;
                        }

                        // If the successor contains an if_true of a single phi node
                        if (branch.args.length is 1 &&
                            succ.firstInstr.opcode is &IF_TRUE &&
                            succ.firstInstr.getArg(0) is succ.firstPhi &&
                            succ.firstInstr.getArg(0).hasOneUse &&
                            branch.getPhiArg(succ.firstPhi).hasOneUse)
                        {
                            // Create an if_true instruction to replace the jump
                            auto predIf = block.addInstr(new IRInstr(
                                &IF_TRUE,
                                branch.getPhiArg(succ.firstPhi)
                            ));

                            // Copy the successor if branches to the new if branch
                            auto succIf = succ.firstInstr;
                            for (size_t tIdx = 0; tIdx < 2; ++tIdx)
                            {
                                auto succTarget = succIf.getTarget(tIdx);
                                auto predTarget = predIf.setTarget(tIdx, succTarget.target);
                                foreach (arg; succTarget.args)
                                    predTarget.setPhiArg(cast(PhiNode)arg.owner, arg.value);
                            }

                            // Remove the jump instruction
                            delInstr(instr);

                            continue INSTR_LOOP;
                        }

                        // Phi of phi optimization:
                        // If the predecessor has a phi and a jump, and the 
                        // successor has one phi which uses the predecessor phi
                        if (block.firstInstr is instr && 
                            block.firstPhi !is null && block.firstPhi.next is null &&
                            succ.firstPhi !is null && succ.firstPhi.next is null &&
                            branch.getPhiArg(succ.firstPhi) is block.firstPhi)
                        {
                            // For each predecessor
                            for (size_t pIdx = 0; pIdx < block.numIncoming; ++pIdx)
                            {
                                auto desc = block.getIncoming(pIdx);
                                auto pBranch = desc.branch;

                                // Find the target index
                                size_t tIdx;
                                for (tIdx = 0; tIdx < pBranch.MAX_TARGETS; ++tIdx)
                                    if (pBranch.getTarget(tIdx) is desc)
                                        break;
                                assert (tIdx < pBranch.MAX_TARGETS);

                                // Make the predecessor pass the phi argument
                                // to the successor directly
                                auto phiArg = desc.getPhiArg(block.firstPhi);
                                auto newDesc = pBranch.setTarget(tIdx, succ);
                                newDesc.setPhiArg(succ.firstPhi, phiArg);
                            }

                            changed = true;
                            continue INSTR_LOOP;
                        }
                    }

                    // If this is an if_true conditional branch
                    if (op is &IF_TRUE)
                    {
                        auto ifArg = instr.getArg(0);
                        auto ifDstArg = cast(IRDstValue)ifArg;

                        // If the argument is a constant
                        if (auto cstArg = cast(IRConst)ifArg)
                        {
                            // Select the target to branch to
                            auto desc = instr.getTarget((cstArg is IRConst.trueCst)? 0:1);

                            // Replace the if branch by a direct jump
                            auto jumpInstr = block.addInstr(new IRInstr(&JUMP));
                            auto newDesc = jumpInstr.setTarget(0, desc.target);
                            foreach (arg; desc.args)
                                newDesc.setPhiArg(cast(PhiNode)arg.owner, arg.value);
                            delInstr(instr);

                            continue INSTR_LOOP;
                        }

                        // If there is a single predecessor which is an if
                        // branch on the same argument, and the argument is
                        // not from this block
                        if (
                            block.numIncoming is 1 &&
                            block.getIncoming(0).branch.opcode is &IF_TRUE &&
                            block.getIncoming(0).branch.getArg(0) is ifArg &&
                            ifDstArg && ifDstArg.block !is block
                        )
                        {
                            // Determine which branch was taken to get here
                            auto predEdge = block.getIncoming(0);
                            auto predIf = predEdge.branch;
                            auto branchIdx = (predEdge is predIf.getTarget(0))? 0:1;

                            // This if will branch the same way as the predecessor
                            auto desc = instr.getTarget(branchIdx);

                            // Replace the if branch by a direct jump
                            auto jumpInstr = block.addInstr(new IRInstr(&JUMP));
                            auto newDesc = jumpInstr.setTarget(0, desc.target);
                            foreach (arg; desc.args)
                                newDesc.setPhiArg(cast(PhiNode)arg.owner, arg.value);
                            delInstr(instr);

                            continue INSTR_LOOP;
                        }
                    }

                    // For each branch edge from this instruction
                    for (size_t tIdx = 0; tIdx < IRInstr.MAX_TARGETS; ++tIdx)
                    {
                        auto branch = instr.getTarget(tIdx);
                        if (branch is null)
                            continue;

                        // Get the first instruction of the successor
                        auto firstInstr = branch.target.firstInstr;

                        // If the branch has no phi args and the target is a jump
                        if (branch.args.length is 0 && 
                            firstInstr.opcode is &JUMP &&
                            branch.target !is block)
                        {
                            assert (branch.target.firstPhi is null);
                            auto jmpBranch = firstInstr.getTarget(0);

                            //writeln("instr block:\n", instr.block.toString);
                            //writeln("jump block:\n", branch.succ.toString);
                            //writeln("num phis: ", jmpBranch.args.length);

                            // Branch directly to the target of the jump
                            auto newBranch = instr.setTarget(tIdx, jmpBranch.target);
                            foreach (arg; jmpBranch.args)
                                newBranch.setPhiArg(cast(PhiNode)arg.owner, arg.value);

                            changed = true;
                            continue INSTR_LOOP;
                        }
                    }
                }

            } // foreach instr

        } // foreach block

    } // while changed

    //writeln("peephole opts completed (", passNo, " passes)");
    //writeln(fun);
}

