/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012, Maxime Chevalier-Boisvert. All rights reserved.
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
import parser.ast;
import ir.ir;
import ir.ast;
import interp.layout;
import interp.string;
import interp.object;

/**
Memory word union
*/
union Word
{
    static Word intv(uint64 i) { Word w; w.intVal = i; return w; }
    static Word floatv(float64 f) { Word w; w.floatVal = f; return w; }
    static Word ptrv(rawptr p) { Word w; w.ptrVal = p; return w; }
    static Word refv(refptr p) { Word w; w.ptrVal = p; return w; }
    static Word cstv(rawptr c) { Word w; w.ptrVal = c; return w; }

    uint64  uintVal;
    int64   intVal;
    float64 floatVal;
    refptr  refVal;
    rawptr  ptrVal;
}

// Note: low byte is set to allow for one byte immediate comparison
Word NULL   = { intVal: 0x0000000000000000 };
Word UNDEF  = { intVal: 0xFFFFFFFFFFFFFFF1 };
Word TRUE   = { intVal: 0xFFFFFFFFFFFFFFF3 };
Word FALSE  = { intVal: 0xFFFFFFFFFFFFFFF4 };

/// Word type values
enum Type : ubyte
{
    INT,
    FLOAT,
    REFPTR,
    RAWPTR,
    CONST
}

/// Word and type pair
alias Tuple!(Word, "word", Type, "type") ValuePair;

/**
Produce a string representation of a type tag
*/
string typeToString(Type type)
{
    // Switch on the type tag
    switch (type)
    {
        case Type.INT:      return "int";
        case Type.FLOAT:    return "float";
        case Type.RAWPTR:   return "raw pointer";
        case Type.REFPTR:   return "ref pointer";
        case Type.CONST:    return "const";
        default:
        assert (false, "unsupported type");
    }
}

/**
Test if a heap object has a given layout
*/
bool valIsLayout(Word w, uint32 layoutId)
{
    return (obj_get_header(w.ptrVal) == layoutId);
}

/**
Test if a value is a string
*/
bool valIsString(Word w, Type t)
{
    return (t == Type.REFPTR && valIsLayout(w, LAYOUT_STR));
}

/**
Produce a string representation of a value pair
*/
string valToString(ValuePair value)
{
    auto w = value.word;

    // Switch on the type tag
    switch (value.type)
    {
        case Type.INT:
        return to!string(w.intVal);

        case Type.FLOAT:
        if (w.floatVal != w.floatVal)
            return "NaN";
        if (w.floatVal == 1.0/0)
            return "Infinity";
        if (w.floatVal == -1.0/0)
            return "-Infinity";
        return to!string(w.floatVal);

        case Type.RAWPTR:
        return to!string(w.ptrVal);

        case Type.REFPTR:
        if (w == NULL)
            return "null";
        if (valIsLayout(w, LAYOUT_OBJ))
            return "object";
        if (valIsLayout(w, LAYOUT_CLOS))
            return "function";
        if (valIsLayout(w, LAYOUT_ARR))
            return "array";
        if (valIsString(w, value.type))
        {
            auto len = str_get_len(w.ptrVal);
            wchar[] str = new wchar[len];
            for (uint32 i = 0; i < len; ++i)
                str[i] = str_get_data(w.ptrVal, i);
            return to!string(str);
        }
        return "refptr";

        case Type.CONST:
        if (w == TRUE)
            return "true";
        if (w == FALSE)
            return "false";
        if (w == UNDEF)
            return "undefined";
        assert (false, "unsupported constant");

        default:
        assert (false, "unsupported value type");
    }
}

/// Stack size, 256K words
immutable size_t STACK_SIZE = 2^^18;

/// Initial heap size, 16M bytes
immutable size_t HEAP_INIT_SIZE = 2^^24;

/// Initial global object size
immutable size_t GLOBAL_OBJ_INIT_SIZE = 512;

/// Initial object class size
immutable size_t CLASS_INIT_SIZE = 64;

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

    /// String table reference
    refptr strTbl;

    /// Object prototype object
    refptr objProto;

    /// Array prototype object
    refptr arrProto;

    /// Function prototype object
    refptr funProto;

    /// Global object class descriptor
    refptr globalClass;

    /// Global object reference
    refptr globalObj;

    /// Set of weak references to functions referenced in the heap
    /// To be cleaned up by the GC
    IRFunction[void*] funRefs;

    // Total cycle count
    uint64 cycleCount = 0;

    /**
    Constructor, initializes/resets the interpreter state
    */
    this(bool loadStdLib = true)
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

        // Allocate and initialize the string table
        strTbl = strtbl_alloc(this, STR_TBL_INIT_SIZE);

        // Allocate the object prototype object
        objProto = newObj(
            this, 
            null, 
            NULL.ptrVal,
            CLASS_INIT_SIZE,
            CLASS_INIT_SIZE
        );

        // Allocate the array prototype object
        arrProto = newObj(
            this, 
            null, 
            objProto,
            CLASS_INIT_SIZE,
            CLASS_INIT_SIZE
        );

        // Allocate the function prototype object
        funProto = newObj(
            this, 
            null, 
            objProto,
            CLASS_INIT_SIZE,
            CLASS_INIT_SIZE
        );

        // Allocate the global object
        globalObj = newObj(
            this, 
            &globalClass, 
            objProto,
            GLOBAL_OBJ_INIT_SIZE,
            GLOBAL_OBJ_INIT_SIZE
        );

        // Load the layout code
        load("interp/layout.js");

        // Load the runtime library
        load("interp/runtime.js");

        // If the standard library should be loaded
        if (loadStdLib)
        {
            load("stdlib/object.js");
            load("stdlib/function.js");
            load("stdlib/math.js");
            load("stdlib/string.js");
            //load("stdlib/array.js");
            load("stdlib/number.js");
            load("stdlib/boolean.js");
        }
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
    Set the value and type of a stack slot from a value/type pair
    */
    void setSlot(LocalIdx idx, ValuePair val)
    {
        setSlot(idx, val.word, val.type);
    }

    /**
    Set a stack slot to a boolean value
    */
    void setSlot(LocalIdx idx, bool val)
    {
        setSlot(idx, val? TRUE:FALSE, Type.CONST);
    }

    /**
    Set a stack slot to an integer value
    */
    void setSlot(LocalIdx idx, uint64 val)
    {
        setSlot(idx, Word.intv(val), Type.INT);
    }

    /**
    Set a stack slot to a float value
    */
    void setSlot(LocalIdx idx, float64 val)
    {
        setSlot(idx, Word.floatv(val), Type.FLOAT);
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
    Get a value/type pair from the stack
    */
    ValuePair getSlot(LocalIdx idx)
    {
        return ValuePair(getWord(idx), getType(idx));
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

            // Increment the cycle count
            cycleCount++;
        }
    }

    /**
    Execute a unit-level IR function
    */
    ValuePair exec(IRFunction fun)
    {
        assert (
            fun.entryBlock !is null,
            "function has no entry block"
        );

        //writeln(fun.toString());

        // Register this function in the function reference set
        funRefs[cast(void*)fun] = fun;

        // Push the hidden call arguments
        push(Word.ptrv(null), Type.RAWPTR);    // Return address
        push(UNDEF, Type.CONST);               // Closure argument
        push(UNDEF, Type.CONST);               // This argument
        push(Word.intv(0), Type.INT);          // Argument count

        //writefln("stack size before entry: %s", stackSize());

        // Set the instruction pointer
        ip = fun.entryBlock.firstInstr;

        // Run the interpreter loop
        loop();

        // Ensure the stack contains one return value
        assert (
            stackSize() == 1,
            format("the stack contains %s values", (wUpperLimit - wsp))
        );

        // Get the return value
        auto retVal = ValuePair(*wsp, *tsp); 

        // Pop the return value off the stack
        pop(1);

        return retVal;
    }

    /**
    Execute a unit-level function
    */
    ValuePair exec(FunExpr fun)
    {
        auto ir = astToIR(fun);
        return exec(ir);
    }

    /**
    Parse and execute a source file
    */
    ValuePair load(string fileName)
    {
        auto ast = parseFile(fileName);
        return exec(ast);
    }

    /**
    Parse and execute a source string
    */
    ValuePair evalString(string input, string fileName = "string")
    {
        auto ast = parseString(input, fileName);

        // If the AST contains only an expression statement,
        // turn it into a return statement
        if (auto blockStmt = cast(BlockStmt)ast.bodyStmt)
        {
            if (blockStmt.stmts.length == 1)
            {
                if (auto exprStmt = cast(ExprStmt)blockStmt.stmts[$-1])
                {
                    blockStmt.stmts[$-1] = new ReturnStmt(
                        exprStmt.expr,
                        exprStmt.pos
                    );
                }
            }
        }

        auto result = exec(ast);

        return result;
    }

    // TODO: replace by runtime function $rt_toString
    // TODO: way to call $rt_toString with a specific value?
    // - Probably want to call through exec?
    // - callGlobal?
    /**
    Produce the string representation of a value
    */
    refptr stringVal(Word w, Type t)
    {
        switch (t)
        {
            case Type.REFPTR:
            if (valIsString(w, t))
                return w.ptrVal;
            assert(false, "unsupported ref ptr type in stringVal");

            case Type.INT:
            return getString(this, to!wstring(w.intVal));

            case Type.FLOAT:
            return getString(this, to!wstring(w.floatVal));

            case Type.CONST:
            if (w == TRUE)
                return getString(this, "true");
            else if (w == FALSE)
                return getString(this, "false");
            else if (w == NULL)
                return getString(this, "null");
            else if (w == UNDEF)
                return getString(this, "undefined");
            else
                assert (false, "unsupported constant");

            default:
            assert (false, "unsupported type in stringVal");
        }
    }
}

