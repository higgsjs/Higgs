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
import interp.layout;

/**
Memory word union
*/
union Word
{
    static Word intv(long i) { Word w; w.intVal = i; return w; }
    static Word ptrv(rawptr p) { Word w; w.ptrVal = p; return w; }
    static Word refv(refptr p) { Word w; w.ptrVal = p; return w; }
    static Word cstv(rawptr c) { Word w; w.ptrVal = c; return w; }

    uint64  uintVal;
    int64   intVal;
    float64 floatVal;
    refptr  refVal;
    rawptr  ptrVal;
}

// Note: high byte is set to allow for one byte immediate comparison
Word UNDEF  = { intVal: 0xF1FFFFFFFFFFFFFF };
Word NULL   = { intVal: 0xF2FFFFFFFFFFFFFF };
Word TRUE   = { intVal: 0xF3FFFFFFFFFFFFFF };
Word FALSE  = { intVal: 0xF4FFFFFFFFFFFFFF };

/// Word type values
enum Type : ubyte
{
    INT,
    FLOAT,
    STRING,
    REFPTR,
    RAWPTR,
    CONST
}

/// Word and type pair
alias Tuple!(Word, "word", Type, "type") ValuePair;

/**
Produce a string representation of a type tag
*/
string TypeToString(Type type)
{
    // Switch on the type tag
    switch (type)
    {
        case Type.INT:      return "int";
        case Type.FLOAT:    return "float";
        case Type.STRING:   return "string";
        case Type.RAWPTR:   return "raw pointer";
        case Type.REFPTR:   return "ref pointer";
        case Type.CONST:    return "const";
        default:
        assert (false, "unsupported type");
    }
}

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

        case Type.STRING:
        auto len = str_get_len(w.ptrVal);
        wchar[] str = new wchar[len];
        for (size_t i = 0; i < len; ++i)
            str[i] = str_get_data(w.ptrVal, i);
        return to!string(str);

        case Type.RAWPTR:
        return to!string(w.ptrVal);

        case Type.REFPTR:
        return "refptr";

        case Type.CONST:
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
Interpreter
*/
class Interp
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

    /**
    Allocate an object on the stack
    */
    rawptr alloc(size_t size)
    {
        ubyte* ptr = allocPtr;

        allocPtr += size;

        if (allocPtr > heapLimit)
            throw new Error("heap space exhausted");

        // Align the allocation pointer
        allocPtr = alignPtr(allocPtr);

        return ptr;
    }

    /**
    Execute the interpreter loop
    */
    void loop()
    {
        assert (
            ip !is null,
            "ip is null"
        );

        // Repeat for each instruction
        while (ip !is null)
        {
            // Get the current instruction
            IRInstr instr = ip;

            // Update the IP
            ip = instr.next;

            //writefln("mnem: %s", instr.opcode.mnem);

            // Get the opcode's implementation function
            auto opFun = instr.opcode.opFun;

            assert (
                opFun !is null,
                format(
                    "unsupported opcode: %s",
                    instr.opcode.mnem
                )
            );

            // Call the opcode's function
            opFun(this, instr);
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
        init();

        // Push the hidden call arguments
        push(UNDEF, Type.CONST);                // FIXME:Closure argument
        push(UNDEF, Type.CONST);                // FIXME:This argument
        push(Word.intv(0), Type.INT);         // Argument count
        push(Word.ptrv(null), Type.RAWPTR);    // Return address

        //writefln("stack size before entry: %s", stackSize());

        // Set the instruction pointer
        ip = fun.entryBlock.firstInstr;

        // Run the interpreter loop
        loop();
    }

    /**
    Get the return value from the top of the stack
    */
    ValuePair getRet()
    {
        assert (
            stackSize() == 1,
            format("the stack contains %s values", (wUpperLimit - wsp))
        );

        return ValuePair(*wsp, *tsp);
    }

    /**
    Allocate and initialize a string with a given value
    */
    ValuePair makeString(wstring str)
    {
        auto objPtr = this.alloc(str_comp_size(str.length));

        str_set_len(objPtr, cast(uint32)str.length);

        // TODO: hash code

        for (size_t i = 0; i < str.length; ++i)
            str_set_data(objPtr, i, str[i]);

        return ValuePair(Word.refv(objPtr), Type.STRING);
    }

    //
    // TODO: boolVal
    //

    /**
    Produce the string representation of a value
    */
    ValuePair stringVal(Word w, Type t)
    {
        switch (t)
        {
            case Type.STRING:
            return ValuePair(w, t);

            case Type.INT:
            return makeString(to!wstring(w.intVal));

            case Type.CONST:
            if (w == TRUE)
                return makeString("true");
            else if (w == FALSE)
                return makeString("false");
            else if (w == NULL)
                return makeString("null");
            else if (w == UNDEF)
                return makeString("undefined");
            else
                assert (false, "unsupported constant");

            default:
            assert (false, "unsupported type in stringVal");
        }
    }

    static void opSetInt(Interp interp, IRInstr instr)
    {
        interp.setSlot(
            instr.outSlot,
            Word.intv(instr.args[0].intVal),
            Type.INT
        );
    }

    static void opSetStr(Interp interp, IRInstr instr)
    {
        auto objPtr = instr.args[1].ptrVal;

        // If the string is null, allocate it
        if (objPtr is null)
        {
            auto strVal = interp.makeString(instr.args[0].stringVal);
            objPtr = strVal.word.ptrVal;
        }

        interp.setSlot(
            instr.outSlot,
            Word.ptrv(objPtr),
            Type.STRING
        );
    }

    static void opSetTrue(Interp interp, IRInstr instr)
    {
        interp.setSlot(
            instr.outSlot,
            TRUE,
            Type.CONST
        );
    }

    static void opSetFalse(Interp interp, IRInstr instr)
    {
        interp.setSlot(
            instr.outSlot,
            FALSE,
            Type.CONST
        );
    }

    static void opSetNull(Interp interp, IRInstr instr)
    {
        interp.setSlot(
            instr.outSlot,
            NULL,
            Type.CONST
        );
    }

    static void opSetUndef(Interp interp, IRInstr instr)
    {
        interp.setSlot(
            instr.outSlot,
            UNDEF,
            Type.CONST
        );
    }

    static void opMove(Interp interp, IRInstr instr)
    {
        interp.move(
            instr.args[0].localIdx,
            instr.outSlot
        );
    }

    static void opAdd(Interp interp, IRInstr instr)
    {
        auto idx0 = instr.args[0].localIdx;
        auto idx1 = instr.args[1].localIdx;
        auto w0 = interp.getWord(idx0);
        auto w1 = interp.getWord(idx1);
        auto t0 = interp.getType(idx0);
        auto t1 = interp.getType(idx1);

        // If both values are integer
        if (t0 == Type.INT && t1 == Type.INT)
        {
            interp.setSlot(
                instr.outSlot, 
                Word.intv(w0.intVal + w1.intVal),
                Type.INT
            );
        }

        // If either value is a string
        else if (t0 == Type.STRING || t1 == Type.STRING)
        {
            // Evaluate the string value of both arguments
            auto s0 = interp.stringVal(w0, t0);
            auto s1 = interp.stringVal(w1, t1);

            auto l0 = str_get_len(s0.word.ptrVal);
            auto l1 = str_get_len(s1.word.ptrVal);

            auto sO = interp.alloc(str_comp_size(l0+l1));
            str_set_len(sO, l0+l1);

            for (size_t i = 0; i < l0; ++i)
                str_set_data(sO, i, str_get_data(s0.word.ptrVal, i));
            for (size_t i = 0; i < l1; ++i)
                str_set_data(sO, l0+i, str_get_data(s1.word.ptrVal, i));

            interp.setSlot(
                instr.outSlot, 
                Word.ptrv(sO),
                Type.STRING
            );
        }

        else
        {
            assert (false, "unsupported types in add");
        }
    }

    static void opSub(Interp interp, IRInstr instr)
    {
        // TODO: support for other types
        auto idx0 = instr.args[0].localIdx;
        auto idx1 = instr.args[1].localIdx;

        auto w0 = interp.getWord(idx0);
        auto w1 = interp.getWord(idx1);

        interp.setSlot(
            instr.outSlot, 
            Word.intv(w0.intVal - w1.intVal),
            Type.INT
        );
    }

    static void opMul(Interp interp, IRInstr instr)
    {
        // TODO: support for other types
        auto idx0 = instr.args[0].localIdx;
        auto idx1 = instr.args[1].localIdx;

        auto w0 = interp.getWord(idx0);
        auto w1 = interp.getWord(idx1);

        interp.setSlot(
            instr.outSlot, 
            Word.intv(w0.intVal * w1.intVal),
            Type.INT
        );
    }

    static void opDiv(Interp interp, IRInstr instr)
    {
        // TODO: support for other types
        auto idx0 = instr.args[0].localIdx;
        auto idx1 = instr.args[1].localIdx;

        auto w0 = interp.getWord(idx0);
        auto w1 = interp.getWord(idx1);

        // TODO: produce NaN or Inf on 0
        if (w1.intVal == 0)
            throw new Error("division by 0");

        interp.setSlot(
            instr.outSlot, 
            Word.intv(w0.intVal / w1.intVal),
            Type.INT
        );
    }

    static void opMod(Interp interp, IRInstr instr)
    {
        // TODO: support for other types
        auto idx0 = instr.args[0].localIdx;
        auto idx1 = instr.args[1].localIdx;

        auto w0 = interp.getWord(idx0);
        auto w1 = interp.getWord(idx1);

        // TODO: produce NaN or Inf on 0
        if (w1.intVal == 0)
            throw new Error("modulo with 0 divisor");

        interp.setSlot(
            instr.outSlot, 
            Word.intv(w0.intVal % w1.intVal),
            Type.INT
        );
    }

    static void opBoolVal(Interp interp, IRInstr instr)
    {
        auto idx = instr.args[0].localIdx;

        auto w = interp.getWord(idx);
        auto t = interp.getType(idx);

        bool output;
        switch (t)
        {
            case Type.CONST:
            output = (w == TRUE);
            break;

            case Type.INT:
            output = (w.intVal != 0);
            break;

            case Type.STRING:
            output = (str_get_len(w.ptrVal) != 0);
            break;

            default:
            assert (false, "unsupported type in comparison");
        }

        interp.setSlot(
            instr.outSlot, 
            output? TRUE:FALSE,
            Type.CONST
        );
    }

    static void opCmpSe(Interp interp, IRInstr instr)
    {
        // TODO: support for other types
        auto idx0 = instr.args[0].localIdx;
        auto idx1 = instr.args[1].localIdx;

        auto w0 = interp.getWord(idx0);
        auto w1 = interp.getWord(idx1);

        bool output = (w0.intVal == w1.intVal);

        interp.setSlot(
            instr.outSlot, 
            output? TRUE:FALSE,
            Type.CONST
        );
    }

    static void opCmpLt(Interp interp, IRInstr instr)
    {
        // TODO: support for other types
        auto idx0 = instr.args[0].localIdx;
        auto idx1 = instr.args[1].localIdx;

        auto w0 = interp.getWord(idx0);
        auto w1 = interp.getWord(idx1);

        bool output = (w0.intVal < w1.intVal);

        interp.setSlot(
            instr.outSlot, 
            output? TRUE:FALSE,
            Type.CONST
        );
    }

    static void opJump(Interp interp, IRInstr instr)
    {
        auto block = instr.args[0].block;
        interp.ip = block.firstInstr;
    }

    static void opJumpTrue(Interp interp, IRInstr instr)
    {
        auto valIdx = instr.args[0].localIdx;
        auto block = instr.args[1].block;
        auto wVal = interp.getWord(valIdx);

        if (wVal == TRUE)
            interp.ip = block.firstInstr;
    }

    static void opJumpFalse(Interp interp, IRInstr instr)
    {
        auto valIdx = instr.args[0].localIdx;
        auto block = instr.args[1].block;
        auto wVal = interp.getWord(valIdx);

        if (wVal == FALSE)
            interp.ip = block.firstInstr;
    }

    static void opSetArg(Interp interp, IRInstr instr)
    {
        auto srcIdx = instr.args[0].localIdx;
        auto dstIdx = -(instr.args[1].intVal + 1);

        auto wArg = interp.getWord(srcIdx);
        auto tArg = interp.getType(srcIdx);

        interp.wsp[dstIdx] = wArg;
        interp.tsp[dstIdx] = tArg;
    }

    static void opCall(Interp interp, IRInstr instr)
    {
        auto closIdx = instr.args[0].localIdx;
        auto thisIdx = instr.args[1].localIdx;
        auto numArgs = instr.args[2].intVal;

        // TODO: proper closure object
        // Get the function object
        auto ptr = interp.getWord(closIdx).ptrVal;
        auto fun = cast(IRFunction)ptr;

        assert (
            fun !is null, 
            "null IRFunction pointer"
        );

        // If the function is not yet compiled, compile it now
        if (fun.entryBlock is null)
        {
            //writeln("compiling");
            astToIR(fun.ast, fun);
            //writeln(fun.toString);
        }

        // Get the return address
        auto retAddr = cast(rawptr)instr.next;

        assert (
            retAddr !is null, 
            "next instruction is null"
        );

        // Push stack space for the arguments
        interp.push(numArgs);

        // Push the hidden call arguments
        interp.push(UNDEF, Type.CONST);                     // FIXME:Closure argument
        interp.push(UNDEF, Type.CONST);                     // FIXME:This argument
        interp.push(Word.intv(numArgs), Type.INT);          // Argument count
        interp.push(Word.ptrv(retAddr), Type.RAWPTR);       // Return address

        // Set the instruction pointer
        interp.ip = fun.entryBlock.firstInstr;
    }

    // Allocate/adjust the stack frame on function entry
    static void opPushFrame(Interp interp, IRInstr instr)
    {
        auto numParams = instr.args[0].intVal;
        auto numLocals = instr.args[1].intVal;

        // Get the number of arguments passed
        auto numArgs = interp.getWord(1).intVal;

        // If there are not enough arguments
        if (numArgs < numParams)
        {
            auto deltaArgs = numParams - numArgs;

            // Allocate new stack slots for the missing arguments
            interp.push(deltaArgs);

            // Move the hidden arguments to the top of the stack
            for (size_t i = 0; i < NUM_HIDDEN_ARGS; ++i)
                interp.move(deltaArgs + i, i);

            // Initialize the missing arguments to undefined
            for (size_t i = 0; i < deltaArgs; ++i)
                interp.setSlot(NUM_HIDDEN_ARGS + i, UNDEF, Type.CONST);
        }

        // If there are too many arguments
        else if (numArgs > numParams)
        {
            auto deltaArgs = numArgs - numParams;

            // Move the hidden arguments down
            for (size_t i = 0; i < NUM_HIDDEN_ARGS; ++i)
                interp.move(i, deltaArgs + i);

            // Remove superfluous argument slots
            interp.pop(deltaArgs);
        }

        // Allocate slots for the local variables
        auto delta = numLocals - (numParams + NUM_HIDDEN_ARGS);
        //writefln("push_frame adding %s slot", delta);
        interp.push(delta);
    }

    static void opRet(Interp interp, IRInstr instr)
    {
        auto retSlot   = instr.args[0].localIdx;
        auto raSlot    = instr.args[1].localIdx;
        auto numLocals = instr.args[2].intVal;

        // Get the return value
        auto retW = interp.wsp[retSlot];
        auto retT = interp.tsp[retSlot];

        // Get the return address
        auto retAddr = interp.getWord(raSlot).ptrVal;

        //writefln("popping num locals: %s", numLocals);

        // Pop all local stack slots
        interp.pop(numLocals);

        // Leave the return value on top of the stack
        interp.push(retW, retT);

        // Set the instruction pointer
        interp.ip = retAddr? (cast(IRInstr)retAddr):null;
    }

    // Get the callee's return value after a call
    static void opGetRet(Interp interp, IRInstr instr)
    {
        // Read and pop the value
        auto wRet = interp.getWord(0);
        auto tRet = interp.getType(0);
        interp.pop(1);

        interp.setSlot(
            instr.outSlot, 
            wRet,
            tRet
        );
    }

    static void opNewClos(Interp interp, IRInstr instr)
    {
        auto fun = instr.args[0].fun;

        // TODO: create a proper closure
        interp.setSlot(
            instr.outSlot,
            Word.ptrv(cast(rawptr)fun),
            Type.RAWPTR
        );
    }
}
