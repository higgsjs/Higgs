/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011, Maxime Chevalier-Boisvert. All rights reserved.
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

module interp.interp;

import std.stdio;
import parser.parser;
import ir.ir;

/**
Memory word union
*/
union Word
{
    static Word intg(long i) { Word w; w.intVal = i; return w; }
    static Word ptr(void* p) { Word w; w.ptrVal = p; return w; }
    static Word cst(void* c) { Word w; w.ptrVal = c; return w; }

    ulong uintVal;
    long intVal;
    double floatVal;
    void* refVal;
    void* ptrVal;
}

Word UNDEF  = { intVal: 0xFFFFFFFFFFFFFF01 };
Word NULL   = { intVal: 0xFFFFFFFFFFFFFF02 };
Word TRUE   = { intVal: 0xFFFFFFFFFFFFFF03 };
Word FALSE  = { intVal: 0xFFFFFFFFFFFFFF04 };

/// Word type values
enum Type : ubyte
{
    INT,
    FLOAT,
    REF,
    RAWPTR,
    CST
}

/// Stack size, 256K words
immutable size_t STACK_SIZE = 2^^18;

/**
Interpreter state structure
*/
struct State
{
    // Word stack
    Word wStack[STACK_SIZE];

    // Type stack
    Type tStack[STACK_SIZE];

    // Word stack pointer (stack top)
    Word* wsp;

    // Type stack pointer (stack top)
    Type* tsp;

    // TODO: heapPtr, heapLimit, allocPtr

    // Instruction pointer
    IRInstr ip;

    /**
    Initialize/reset the interpreter state
    */
    void init()
    {
        wsp = &wStack[wStack.length-1];
        tsp = &tStack[tStack.length-1];

        ip = null;
    }

    /**
    Set the value and type of a stack slot
    */
    void setSlot(LocalIdx idx, Word w, Type t)
    {
        assert (
            idx >= 0 && idx < wStack.length,
            "invalid stack slot index"
        );

        wsp[idx] = w;
        tsp[idx] = t;
    }

    /**
    Push a word on the stack
    */
    void push(Word w, Type t)
    {
        push(1);
        setSlot(0, w, t);
    }

    /**
    Allocate space on the stack
    */
    void push(size_t numWords)
    {
        wsp -= numWords;
        tsp -= numWords;

        if (wsp >= &wStack[0])
            throw new Error("stack overflow");
    }

}

/**
Interpreter
*/
class Interp
{
    /// Interpreter state
    State state;

    this()
    {
    }

    /**
    Execute the interpreter loop
    */
    void loop()
    {
        assert (
            state.ip !is null,
            "ip is null"
        );

        // Repeat for each instruction
        for (;;)
        {
            // Get the current instruction
            IRInstr instr = state.ip;

            // Update the IP
            state.ip = instr.next;

            // Get the instruction's type
            auto type = instr.type;

            // TODO: call instr

            if (type is &IRInstr.PUSH_FRAME)
            {
                auto numArgs = instr.args[0].intVal;
                auto numLocals = instr.args[1].intVal;

                // TODO: handle incorrect argument counts
                state.push(numLocals - numArgs);
            }

            else if (type is &IRInstr.SET_INT)
            {
                state.setSlot(
                    instr.outSlot,
                    Word.intg(instr.args[0].intVal),
                    Type.INT
                );
            }

            else if (type is &IRInstr.SET_UNDEF)
            {
                state.setSlot(
                    instr.outSlot,
                    UNDEF,
                    Type.CST
                );
            }

            else if (type is &IRInstr.ADD)
            {
                // TODO: support for other types

                assert (false);
            }

            else if (type is &IRInstr.RET)
            {
                // TODO: ret
                // TODO: ret
                // TODO: ret

                assert (false);

                auto retSlot = instr.args[0].localIdx;
                auto numLocals = instr.args[1].intVal;

                // TODO: pop all locals

                // TODO: leave return value on top of stack





            }

            else
            {
                assert (false, "unsupported instruction");
            }
        }
    }

    /**
    Execute a unit-level IR function
    */
    void exec(IRFunction fun)
    {
        assert (
            fun.entryBlock !is null,
            "function has no entry block"
        );

        // Initialize the interpreter state
        state.init();

        // Push the hidden call arguments
        state.push(UNDEF, Type.CST);                // FIXME:Closure argument
        state.push(UNDEF, Type.CST);                // FIXME:This argument
        state.push(Word.intg(0), Type.INT);         // Argument count
        state.push(Word.ptr(null), Type.RAWPTR);    // Return address

        // Set the instruction pointer
        state.ip = fun.entryBlock.firstInstr;

        // Run the interpreter loop
        loop();
    }

    /**
    Get the return value from the top of the stack
    */
    Word getRet()
    {
        assert (
            state.wsp == &state.wStack[0],
            "the stack does not contain one value"
        );

        return state.wStack[0];
    }
}

