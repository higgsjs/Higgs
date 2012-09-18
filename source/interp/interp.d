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

import core.sys.posix.unistd;
import core.sys.posix.sys.mman;
import core.memory;
import std.stdio;
import std.string;
import std.conv;
import std.typecons;
import util.misc;
import parser.parser;
import ir.ir;
import ir.ast;

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

// TODO: set high bit instead for 8 bit immediate comparison?
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

/**
Produce a string representation of a value pair
*/
string ValueToString(ValuePair value)
{
    auto w = value.word;

    // Switch on the type tag
    switch (value.type)
    {
        case Type.INT:
        return to!string(w.intVal);

        case Type.FLOAT:
        return to!string(w.floatVal);

        case Type.RAWPTR:
        return to!string(w.ptrVal);

        case Type.REF:
        return "ref";

        case Type.CST:
        if (w == TRUE)
            return "true";
        else if (w == FALSE)
            return "false";
        else if (w == NULL)
            return "null";
        else if (w == UNDEF)
            return "undefined";
        else
            assert (false, "unsupported constant");

        default:
        assert (false, "unsupported value type");
    }
}

/// Stack size, 256K words
immutable size_t STACK_SIZE = 2^^18;

/// Initial heap size, 16M bytes
immutable size_t HEAP_INIT_SIZE = 2^^24;

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

    /// Heap start pointer
    ubyte* heapPtr;

    /// Heap size
    size_t heapSize;

    /// Heap upper limit
    ubyte* heapLimit;

    /// Allocation pointer
    ubyte* allocPtr;

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

        // Allocate a block of immovable memory for the heap
        heapSize = HEAP_INIT_SIZE;
        heapPtr = cast(ubyte*)GC.malloc(heapSize);
        heapLimit = heapPtr + heapSize;

        // Check that the allocation was successful
        if (heapPtr is null)
            throw new Error("heap allocation failed");

        // Map the memory as executable
        auto pa = mmap(
            cast(void*)heapPtr,
            heapSize,
            PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_PRIVATE | MAP_ANON,
            -1,
            0
        );

        // Check that the memory mapping was successful
        if (pa == MAP_FAILED)
            throw new Error("mmap call failed");

        // Initialize the allocation pointer
        allocPtr = alignPtr(heapPtr);

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
    Copy a value from one stack slot to another
    */
    void move(LocalIdx src, LocalIdx dst)
    {
        assert (
            &wsp[src] >= wLowerLimit && &wsp[src] < wUpperLimit,
            "invalid src index"
        );

        assert (
            &wsp[dst] >= wLowerLimit && &wsp[dst] < wUpperLimit,
            "invalid dst index"
        );

        wsp[dst] = wsp[src];
        tsp[dst] = tsp[src];
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

    /// Constructor
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
                auto fun = instr.args[0].fun;

                // TODO: create a proper closure
                state.setSlot(
                    instr.outSlot,
                    Word.ptr(cast(void*)&fun),
                    Type.RAWPTR
                );
            }

            // Set argument value
            else if (type is &IRInstr.SET_ARG)
            {
                auto srcIdx = instr.args[0].localIdx;
                auto dstIdx = -(instr.args[1].intVal + 1);

                auto wArg = state.getWord(srcIdx);
                auto tArg = state.getType(srcIdx);

                state.wsp[dstIdx] = wArg;
                state.tsp[dstIdx] = tArg;
            }

            // Function call
            else if (type is &IRInstr.CALL)
            {
                auto closIdx = instr.args[0].localIdx;
                auto thisIdx = instr.args[1].localIdx;
                auto numArgs = instr.args[2].intVal;

                // TODO: proper closure object
                // Get the function object
                auto fun = *cast(IRFunction*)state.getWord(closIdx).ptrVal;

                // If the function is not yet compiled, compile it now
                if (fun.entryBlock is null)
                {
                    astToIR(fun.ast, fun);
                    //writeln(fun.toString);
                }

                // Get the return address
                auto retAddr = cast(void*)&instr.next;

                assert (
                    retAddr !is null, 
                    "next instruction is null"
                );

                // Push stack space for the arguments
                state.push(numArgs);

                // Push the hidden call arguments
                state.push(UNDEF, Type.CST);                    // FIXME:Closure argument
                state.push(UNDEF, Type.CST);                    // FIXME:This argument
                state.push(Word.intg(numArgs), Type.INT);       // Argument count
                state.push(Word.ptr(retAddr), Type.RAWPTR);     // Return address

                // Set the instruction pointer
                state.ip = fun.entryBlock.firstInstr;
            }

            // Allocate/adjust the stack frame on function entry
            else if (type is &IRInstr.PUSH_FRAME)
            {
                auto numParams = instr.args[0].intVal;
                auto numLocals = instr.args[1].intVal;

                // Get the number of arguments passed
                auto numArgs = state.getWord(1).intVal;

                // If there are not enough arguments
                if (numArgs < numParams)
                {
                    auto deltaArgs = numParams - numArgs;

                    // Allocate new stack slots for the missing arguments
                    state.push(deltaArgs);

                    // Move the hidden arguments to the top of the stack
                    for (size_t i = 0; i < NUM_HIDDEN_ARGS; ++i)
                        state.move(deltaArgs + i, i);

                    // Initialize the missing arguments to undefined
                    for (size_t i = 0; i < deltaArgs; ++i)
                        state.setSlot(NUM_HIDDEN_ARGS + i, UNDEF, Type.CST);
                }

                // If there are too many arguments
                else if (numArgs > numParams)
                {
                    auto deltaArgs = numArgs - numParams;

                    // Move the hidden arguments down
                    for (size_t i = 0; i < NUM_HIDDEN_ARGS; ++i)
                        state.move(i, deltaArgs + i);

                    // Remove superfluous argument slots
                    state.pop(deltaArgs);
                }

                // Allocate slots for the local variables
                auto delta = numLocals - (numParams + NUM_HIDDEN_ARGS);
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

            else if (type is &IRInstr.SET_TRUE)
            {
                state.setSlot(
                    instr.outSlot,
                    TRUE,
                    Type.CST
                );
            }

            else if (type is &IRInstr.SET_FALSE)
            {
                state.setSlot(
                    instr.outSlot,
                    FALSE,
                    Type.CST
                );
            }

            else if (type is &IRInstr.SET_NULL)
            {
                state.setSlot(
                    instr.outSlot,
                    NULL,
                    Type.CST
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

            else if (type is &IRInstr.MOVE)
            {
                state.move(
                    instr.args[0].localIdx,
                    instr.outSlot
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

            else if (type is &IRInstr.DIV)
            {
                // TODO: support for other types
                auto idx0 = instr.args[0].localIdx;
                auto idx1 = instr.args[1].localIdx;

                auto w0 = state.getWord(idx0);
                auto w1 = state.getWord(idx1);

                // TODO: produce NaN or Inf on 0
                if (w1.intVal == 0)
                    throw new Error("division by 0");

                state.setSlot(
                    instr.outSlot, 
                    Word.intg(w0.intVal / w1.intVal),
                    Type.INT
                );
            }

            else if (type is &IRInstr.MOD)
            {
                // TODO: support for other types
                auto idx0 = instr.args[0].localIdx;
                auto idx1 = instr.args[1].localIdx;

                auto w0 = state.getWord(idx0);
                auto w1 = state.getWord(idx1);

                // TODO: produce NaN or Inf on 0
                if (w1.intVal == 0)
                    throw new Error("modulo with 0 divisor");

                state.setSlot(
                    instr.outSlot, 
                    Word.intg(w0.intVal % w1.intVal),
                    Type.INT
                );
            }

            else if (type is &IRInstr.BOOL_VAL)
            {
                auto idx = instr.args[0].localIdx;

                auto w = state.getWord(idx);
                auto t = state.getType(idx);

                bool output;
                switch (t)
                {
                    case Type.CST:
                    output = (w == TRUE);
                    break;

                    case Type.INT:
                    output = (w.intVal != 0);
                    break;

                    default:
                    assert (false, "unsupported type in comparison");
                }

                state.setSlot(
                    instr.outSlot, 
                    output? TRUE:FALSE,
                    Type.CST
                );
            }

            else if (type is &IRInstr.CMP_SE)
            {
                // TODO: support for other types
                auto idx0 = instr.args[0].localIdx;
                auto idx1 = instr.args[1].localIdx;

                auto w0 = state.getWord(idx0);
                auto w1 = state.getWord(idx1);

                bool output = (w0.intVal == w1.intVal);

                state.setSlot(
                    instr.outSlot, 
                    output? TRUE:FALSE,
                    Type.CST
                );
            }

            else if (type is &IRInstr.CMP_LT)
            {
                // TODO: support for other types
                auto idx0 = instr.args[0].localIdx;
                auto idx1 = instr.args[1].localIdx;

                auto w0 = state.getWord(idx0);
                auto w1 = state.getWord(idx1);

                bool output = (w0.intVal < w1.intVal);

                state.setSlot(
                    instr.outSlot, 
                    output? TRUE:FALSE,
                    Type.CST
                );
            }

            else if (type is &IRInstr.JUMP)
            {
                auto block = instr.args[0].block;
                state.ip = block.firstInstr;
            }

            else if (type is &IRInstr.JUMP_TRUE)
            {
                auto valIdx = instr.args[0].localIdx;
                auto block = instr.args[1].block;

                auto wVal = state.getWord(valIdx);

                if (wVal == TRUE)
                    state.ip = block.firstInstr;
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

            // Get the callee's return value after a call
            else if (type is &IRInstr.GET_RET)
            {
                // Read and pop the value
                auto wRet = state.getWord(0);
                auto tRet = state.getType(0);
                state.pop(1);

                state.setSlot(
                    instr.outSlot, 
                    wRet,
                    tRet
                );
            }

            else
            {
                throw new Error(
                    format(
                        "unsupported instruction: %s",
                        type.mnem
                    )
                );
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

        //writeln(fun.toString);

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

