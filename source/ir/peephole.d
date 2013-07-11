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

module ir.peephole;

import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.conv;
import ir.ir;
import ir.ops;

void optIR(IRFunction fun)
{
    //writeln("peephole pass");

    // Work list for blocks
    IRBlock[] blockWL = [];

    // Populate the work lists
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        blockWL ~= block;
    }

    /// Remove and destroy a block
    void delBlock(IRBlock block)
    {
        // TODO: delBlock removal function
        // TODO: queue up successors for re-examination before doing delBlock
        // ISSUE: if we delete a block, we shouldn't be holding a reference to it...
        // Need to scan the work list and remove references




    }








    // Until all work lists are empty
    while (blockWL.length > 0)
    {
        // If there are blocks on the block work list
        if (blockWL.length > 0)
        {
            // Remove a block from the work list
            auto block = blockWL[$-1];
            blockWL.length = blockWL.length - 1;

            // If this block is dead, remove it
            if (block.numIncoming is 0)
            {



                // FIXME
                /*
                writeln("deleting block");
                fun.delBlock(block);
                writeln("block deleted");
                */


                // TODO: traverse fn and look for incoming branches?


            }
        }


        // TODO: If an instruction's block is removed...








    }

    //writeln("peephole pass complete");
}

