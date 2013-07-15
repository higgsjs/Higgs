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

module ir.slotalloc;

import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.conv;
import ir.ir;

/**
Allocate stack slots for a function's IR
*/
void allocSlots(IRFunction fun)
{
    // TODO: tmp slot improvement: don't increase tmp index if we don't
    // interfere with previous tmp?
    // keep track of lastTmp?

    //writefln("allocSlots");

    // Number of assigned variable slots
    auto numVarSlots = 0;

    // Number of assigned temp slots
    auto numTmpSlots = 0;

    // For each block of the function
    for (auto block = fun.entryBlock; block !is null; block = block.next)
    {
        //writefln("block:\n%s", block.toString());

        // Reset the temp slot index
        auto tmpSlotIdx = 0;

        // For each phi node
        for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
        {
            //writefln("phi: %s", phi.toString());

            // If this is not a function parameter
            if (cast(FunParam)phi is null)
            {
                // Assign the phi node to a variable slot
                phi.outSlot = numVarSlots++;
            }
        }

        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            //writefln("instr: %s", instr.toString());

            // If this instruction produces no output, skip it
            if (!instr.opcode.output)
                continue;

            // If this instruction has one use
            if (instr.hasOneUse)
            {
                //writeln("instr has one use");

                // Get the owner of this use
                auto owner = instr.getFirstUse.owner;

                assert (
                    owner !is null,
                    "use owner is null for use of instr: " ~
                    instr.toString()
                );

                assert (
                    owner.block !is null, 
                    "owner instr block is null for: " ~
                    owner.getName()
                );

                if (owner.block is instr.block)
                {
                    // Assign the instruction a temp slot
                    if (tmpSlotIdx >= numTmpSlots)
                        numTmpSlots++;
                    instr.outSlot = tmpSlotIdx++;
                    continue;
                }
            }

            // Assign the instruction a variable slot
            instr.outSlot = numVarSlots++;
        }
    }

    // Compute the total number of local variables
    // Note: function parameters are included in the variable slots
    fun.numLocals = NUM_HIDDEN_ARGS + fun.numParams + numVarSlots + numTmpSlots;

    // Total number of arguments, including hidden arguments
    auto numTotalArgs = NUM_HIDDEN_ARGS + fun.numParams;

    // Assign slots for the hidden arguments
    fun.raVal.outSlot   = fun.numLocals - numTotalArgs + 0;
    fun.closVal.outSlot = fun.numLocals - numTotalArgs + 1;
    fun.thisVal.outSlot = fun.numLocals - numTotalArgs + 2;
    fun.argcVal.outSlot = fun.numLocals - numTotalArgs + 3;

    // For each block of the function
    for (auto block = fun.entryBlock; block !is null; block = block.next)
    {
        // For each phi node
        for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
        {
            // If this is a function parameter
            if (auto param = cast(FunParam)phi)
            {
                // Assign the corresponding parameter slot index
                param.outSlot = fun.numLocals - numTotalArgs + param.idx;
            }
            else
            {
                // Remap the phi node's variable slot
                phi.outSlot += numTmpSlots;
            }
        }

        // For each instruction
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // If this instruction produces no output, skip it
            if (!instr.opcode.output)
                continue;

            // If this instruction has one use
            if (instr.hasOneUse)
            {
                // Get the owner of this use
                auto owner = instr.getFirstUse.owner;
                if (owner.block is instr.block)                    
                {
                    // Leave the tmp slot index unchanged and
                    // Move to the next instruction
                    continue;
                }
            }

            // Remap the instruction's variable slot
            instr.outSlot += numTmpSlots;
        }
    }

    /*
    writeln(fun.getName());
    writefln("numLocals  : %s", fun.numLocals);    
    writefln("numVarSlots: %s", numVarSlots);    
    writefln("numTmpSlots: %s", numTmpSlots);
    */
}

