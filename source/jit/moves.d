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
import jit.assembler;
import jit.x86;
import jit.encodings;

alias Tuple!(X86Opnd, "dst", X86Opnd, "src") Move;

/**
Execute a list of moves as if occurring simultaneously,
preventing memory locations from being overwritten
*/
void execMoves(Assembler as, Move[] moveList, X86Reg tmp0, X86Reg tmp1)
{
    void execMove(Move move)
    {
        assert (cast(X86Imm)move.dst is null);

        auto immSrc = cast(X86Imm)move.src;
        auto memSrc = cast(X86Mem)move.src;
        auto regDst = cast(X86Reg)move.dst;
        auto memDst = cast(X86Mem)move.dst;

        if (memSrc && memDst)
        {
            assert (memSrc.memSize == memDst.memSize);
            auto tmpReg = tmp1.ofSize(memSrc.memSize);
            as.instr(MOV, tmpReg, memSrc);
            as.instr(MOV, memDst, tmpReg);
            return;
        }

        if (immSrc && immSrc.immSize > 32 && memDst)
        {
            assert (memDst.memSize == 64);
            as.instr(MOV, tmp1, immSrc);
            as.instr(MOV, memDst, tmp1);
            return;
        }

        if (regDst && immSrc)
        {
            auto regDst32 = regDst.ofSize(32);

            // xor rXX, rXX is the shortest way to zero-out a register
            if (immSrc.imm is 0)
            {
                as.instr(XOR, regDst32, regDst32);
                return;
            }

            // Take advantage of zero-extension to save REX bytes
            if (regDst.size is 64 && immSrc.imm > 0 && immSrc.unsgSize <= 32)
            {
                as.instr(MOV, regDst32, immSrc);
                return;
            }
        }

        as.instr(MOV, move.dst, move.src);  
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
        //      take pair (A->B) and remove from list
        //      add (A->tmp), (tmp->B) to list
        //
        // We've removed A from the src list
        // move that goes into A can get executed

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

        writeln("cycle occurs ***");

        // No safe move was found
        // take a pair (A->B) and remove it from list
        // add (A->tmp), (tmp->B) to list
        Move move = moveList[$-1];
        moveList.length -= 1;

        X86Reg tmpReg;
        if (auto regSrc = cast(X86Reg)move.src)
            tmpReg = tmp0.ofSize(regSrc.size);
        else if (auto memSrc = cast(X86Mem)move.src)
            tmpReg = tmp0.ofSize(memSrc.memSize);
        else
            tmpReg = tmp0;

        moveList ~= Move(tmpReg, move.src);
        moveList ~= Move(move.dst, tmpReg);
    }
}

