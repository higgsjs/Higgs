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
import std.string;
import std.typecons;
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

/// Word and type pair
alias Tuple!(Word, "word", Type, "type") ValuePair;

/// Stack size, 256K words
immutable size_t STACK_SIZE = 2^^18;

/**
Interpreter state structure
*/
struct State
{
    /// Word stack
    Word wStack[STACK_SIZE];

    /// Type stack
    Type tStack[STACK_SIZE];

    /// Word and type stack pointers (stack top)
    Word* wsp;

    /// Type stack pointer (stack top)
    Type* tsp;

    /// Word stack lower limit
    Word* wLowerLimit;

    /// Word stack upper limit
    Word* wUpperLimit;

    /// Type stack lower limit
    Type* tLowerLimit;

    /// Type stack upper limit
    Type* tUpperLimit;

    // TODO: heapPtr, heapLimit, allocPtr

    /// Instruction pointer
    IRInstr ip;

    /**
    Initialize/reset the interpreter state
    */
    void init()
    {
        assert (
            wStack.length == tStack.length,
            "stack lengths do not match"
        );

        // Initialize the stack limit pointers
        wLowerLimit = &wStack[0];
        wUpperLimit = &wStack[0] + wStack.length;
        tLowerLimit = &tStack[0];
        tUpperLimit = &tStack[0] + tStack.length;

        // Initialize the stack pointers just past the end of the stack
        wsp = wUpperLimit;
        tsp = tUpperLimit;

        // Initialize the IP to null
        ip = null;
    }

    /**
    Set the value and type of a stack slot
    */
    void setSlot(LocalIdx idx, Word w, Type t)
    {
        assert (
            &wsp[idx] >= wLowerLimit && &wsp[idx] < wUpperLimit,
            "invalid stack slot index"
        );

        wsp[idx] = w;
        tsp[idx] = t;
    }

    /**
    Get a word from the word stack
    */
    Word getWord(LocalIdx idx)
    {
        assert (
            &wsp[idx] >= wLowerLimit && &wsp[idx] < wUpperLimit,
            "invalid stack slot index"
        );

        return wsp[idx];
    }

    /**
    Get a type from the type stack
    */
    Type getType(LocalIdx idx)
    {
        assert (
            &tsp[idx] >= tLowerLimit && &tsp[idx] < tUpperLimit,
            "invalid stack slot index"
        );

        return tsp[idx];
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

        if (wsp < wLowerLimit)
            throw new Error("stack overflow");
    }

    /**
    Free space on the stack
    */
    void pop(size_t numWords)
    {
        wsp += numWords;
        tsp += numWords;

        if (wsp > wUpperLimit)
            throw new Error("stack underflow");
    }

    /**
    Get the number of stack slots
    */
    size_t stackSize()
    {
        return wUpperLimit - wsp;
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
            assert (
                state.ip !is null,
                "ip is null"
            );

            // Get the current instruction
            IRInstr instr = state.ip;

            // Update the IP
            state.ip = instr.next;

            // Get the instruction's type
            auto type = instr.type;

            //writefln("mnem: %s", type.mnem);

            // Closure creation
            if (type is &IRInstr.NEW_CLOS)
            {
                // TODO
                assert (false);







            }

            else if (type is &IRInstr.CALL)
            {
                // TODO
                assert (false);
            }

            else if (type is &IRInstr.PUSH_FRAME)
            {
                auto numArgs = instr.args[0].intVal;
                auto numLocals = instr.args[1].intVal;

                // TODO: handle incorrect argument counts
                auto delta = numLocals - (numArgs + NUM_HIDDEN_ARGS);
                //writefln("push_frame adding %s slot", delta);
                state.push(delta);
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
                auto idx0 = instr.args[0].localIdx;
                auto idx1 = instr.args[1].localIdx;

                auto w0 = state.getWord(idx0);
                auto w1 = state.getWord(idx1);

                state.setSlot(
                    instr.outSlot, 
                    Word.intg(w0.intVal + w1.intVal),
                    Type.INT
                );
            }

            else if (type is &IRInstr.SUB)
            {
                // TODO: support for other types
                auto idx0 = instr.args[0].localIdx;
                auto idx1 = instr.args[1].localIdx;

                auto w0 = state.getWord(idx0);
                auto w1 = state.getWord(idx1);

                state.setSlot(
                    instr.outSlot, 
                    Word.intg(w0.intVal - w1.intVal),
                    Type.INT
                );
            }

            else if (type is &IRInstr.MUL)
            {
                // TODO: support for other types
                auto idx0 = instr.args[0].localIdx;
                auto idx1 = instr.args[1].localIdx;

                auto w0 = state.getWord(idx0);
                auto w1 = state.getWord(idx1);

                state.setSlot(
                    instr.outSlot, 
                    Word.intg(w0.intVal * w1.intVal),
                    Type.INT
                );
            }

            else if (type is &IRInstr.RET)
            {
                auto retSlot   = instr.args[0].localIdx;
                auto raSlot    = instr.args[1].localIdx;
                auto numLocals = instr.args[2].intVal;

                // Get the return value
                auto retW = state.wsp[retSlot];
                auto retT = state.tsp[retSlot];

                // Get the return address
                auto retAddr = state.getWord(raSlot).ptrVal;

                //writefln("popping num locals: %s", numLocals);

                // Pop all local stack slots
                state.pop(numLocals);

                // Leave the return value on top of the stack
                state.push(retW, retT);

                // If the return address is null, stop the execution
                if (retAddr is null)
                    break;

                // Set the instruction pointer
                state.ip = *cast(IRInstr*)retAddr;
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

        //writefln("stack size before entry: %s", state.stackSize());

        // Set the instruction pointer
        state.ip = fun.entryBlock.firstInstr;

        // Run the interpreter loop
        loop();
    }

    /**
    Get the return value from the top of the stack
    */
    ValuePair getRet()
    {
        assert (
            state.stackSize() == 1,
            format("the stack contains %s values", (state.wUpperLimit - state.wsp))
        );

        return ValuePair(*state.wsp, *state.tsp);
    }
}

