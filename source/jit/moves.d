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

module jit.moves;

import std.stdio;
import std.array;
import std.stdint;
import std.typecons;
import ir.ir;
import jit.codeblock;
import jit.x86;
import jit.util;
import options;

alias Tuple!(X86Opnd, "dst", X86Opnd, "src") Move;

/**
Execute a list of moves as if occurring simultaneously,
preventing memory locations from being overwritten
*/
void execMoves(CodeBlock as, Move[] moveList, X86Reg tmp0, X86Reg tmp1)
{
    void execMove(Move move)
    {
        assert (
            !move.dst.isImm,
            "move dst is an immediate"
        );

        auto src = move.src;
        auto dst = move.dst;

        //if (opts.jit_trace_instrs)
        //    as.printStr(dst.toString ~ " = " ~ src.toString);

        if (src.isMem && dst.isMem)
        {
            assert (src.mem.size == dst.mem.size);
            auto tmpReg = tmp1.opnd(src.mem.size);
            as.mov(tmpReg, src);
            as.mov(dst, tmpReg);
            return;
        }

        if (src.isImm && src.imm.immSize > 32 && dst.isMem)
        {
            assert (dst.mem.size == 64);
            as.mov(tmp1.opnd(64), src);
            as.mov(dst, tmp1.opnd(64));
            return;
        }

        if (dst.isReg && src.isImm)
        {
            auto regDst32 = dst.reg.opnd(32);

            // xor rXX, rXX is the shortest way to zero-out a register
            if (src.imm.imm is 0)
            {
                as.xor(regDst32, regDst32);
                return;
            }

            // Take advantage of zero-extension to save REX bytes
            if (dst.reg.size is 64 && src.imm.imm > 0 && src.imm.unsgSize <= 32)
            {
                as.mov(regDst32, src);
                return;
            }
        }

        as.mov(move.dst, move.src);
    }

    // Remove identity moves from the list
    foreach (idx, move; moveList)
    {
        if (move.src == move.dst)
        {
            moveList[idx] = moveList[$-1];
            moveList.length -= 1;
            continue;
        }
    }

    // Until all moves are executed
    EXEC_LOOP:
    while (moveList.length > 0)
    {
        // Find a move that doesn't overwrite an src and execute it
        //
        // if no move doesn't overwrite an src,
        //      take pair (B<-A) and remove from list
        //      execute the move (tmp<-A)
        //      add (B<-tmp) to list
        //
        // We've removed A from the src list, breaking the cycle
        // move that goes into A can now get executed

        MOVE_LOOP:
        foreach (idx0, move0; moveList)
        {
            // If move0 overwrites any src value, skip it
            foreach (idx1, move1; moveList)
                if (move0.dst == move1.src && idx1 != idx0)
                    continue MOVE_LOOP;

            // This move is safe and doesn't overwrite anything
            // Execute this move and remove it from the list,
            // then try finding another safe move
            execMove(move0);
            moveList[idx0] = moveList[$-1];
            moveList.length -= 1;
            continue EXEC_LOOP;
        }

        /*
        writefln("cycle occurs, list length=%s ***", moveList.length);
        foreach (move; moveList)
            writeln(move.dst, " <= ", move.src);
        */

        // No safe move was found
        // take a pair (dst<-src) and remove it from list
        Move move = moveList[$-1];
        moveList.length -= 1;

        auto src = move.src;
        auto dst = move.dst;

        X86Opnd tmpReg;
        if (src.isReg)
            tmpReg = tmp0.opnd(src.reg.size);
        else if (src.isMem)
            tmpReg = tmp0.opnd(src.mem.size);
        else
            tmpReg = X86Opnd(tmp0);

        // Ensure that the tmp reg is not already used in the move list
        debug
        {
            foreach (m; moveList)
                assert (!(m.src.isGPR && m.src.reg.regNo is tmpReg.reg.regNo));
        }

        // Execute (tmp<-src)
        execMove(Move(tmpReg, src));

        // Add (dst<-tmp) to the list
        moveList ~= Move(dst, tmpReg);
    }
}

