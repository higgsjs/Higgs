/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

import core.memory;
import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.typecons;
import std.path;
import std.file;
import options;
import util.misc;
import analysis.typeset;
import parser.parser;
import parser.ast;
import ir.ir;
import ir.ast;
import interp.layout;
import interp.string;
import interp.object;
import interp.gc;
// FIXME: temporary for SSA refactoring
//import jit.jit;

/**
Run-time error
*/
class RunError : Error
{
    /// Associated interpreter
    Interp interp;

    /// Exception value
    ValuePair excVal;

    /// Error message
    string message;

    /// Stack trace
    IRInstr[] trace;

    this(Interp interp, ValuePair excVal, IRInstr[] trace)
    {
        this.interp = interp;
        this.excVal = excVal;
        this.trace = trace;

        if (excVal.type == Type.REFPTR && 
            valIsLayout(excVal.word, LAYOUT_OBJ))
        {
            auto msgStr = getProp(
                interp, 
                excVal.word.ptrVal,
                getString(interp, "message")
            );

            this.message = valToString(msgStr);
        }
        else
        {
            this.message = valToString(excVal);
        }

        super(toString());
    }

    override string toString()
    {
        string str = message;

        foreach (instr; trace)
        {
            auto fun = instr.block.fun;
            str ~= "\n" ~ fun.name ~ " (" ~ to!string(fun.ast.pos) ~ ")";
        }

        return str;
    }
}

/**
Memory word union
*/
union Word
{
    static Word int32v(int32 i) { Word w; w.int32Val = i; return w; }
    static Word int64v(int64 i) { Word w; w.int64Val = i; return w; }
    static Word uint32v(uint32 i) { Word w; w.uint32Val = i; return w; }
    static Word uint64v(uint64 i) { Word w; w.uint64Val = i; return w; }
    static Word float64v(float64 f) { Word w; w.floatVal = f; return w; }
    static Word refv(refptr p) { Word w; w.ptrVal = p; return w; }
    static Word ptrv(rawptr p) { Word w; w.ptrVal = p; return w; }

    int8    int8Val;
    int32   int32Val;
    int64   int64Val;
    uint8   uint8Val;
    uint32  uint32Val;
    uint64  uint64Val;
    float64 floatVal;
    refptr  refVal;
    rawptr  ptrVal;
}

unittest
{
    assert (
        Word.sizeof == rawptr.sizeof,
        "word size does not match pointer size"
    );
}

// Note: low byte is set to allow for one byte immediate comparison
Word NULL    = { uint64Val: 0x0000000000000000 };
Word TRUE    = { uint64Val: 0x0000000000000001 };
Word FALSE   = { uint64Val: 0x0000000000000002 };
Word UNDEF   = { uint64Val: 0x0000000000000003 };
Word MISSING = { uint64Val: 0x0000000000000004 };

/// Word type values
enum Type : ubyte
{
    INT32 = 0,
    INT64,
    FLOAT64,
    REFPTR,
    RAWPTR,
    CONST,
    FUNPTR,
    INSPTR
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
        case Type.INT32:    return "int32";
        case Type.INT64:    return "int64";
        case Type.FLOAT64:  return "float64";
        case Type.RAWPTR:   return "raw pointer";
        case Type.REFPTR:   return "ref pointer";
        case Type.CONST:    return "const";
        case Type.FUNPTR:   return "funptr";
        case Type.INSPTR:   return "insptr";

        default:
        assert (false, "unsupported type");
    }
}

/**
Test if a heap object has a given layout
*/
bool valIsLayout(Word w, uint32 layoutId)
{
    return (w != NULL && obj_get_header(w.ptrVal) == layoutId);
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
        case Type.INT32:
        return to!string(w.int32Val);

        case Type.FLOAT64:
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
            return extractStr(w.ptrVal);
        return "refptr";

        case Type.CONST:
        if (w == TRUE)
            return "true";
        if (w == FALSE)
            return "false";
        if (w == UNDEF)
            return "undefined";
        if (w == UNDEF)
            return "missing";
        assert (false, "unsupported constant");

        case Type.FUNPTR:
        return "funptr";
        break;

        case Type.INSPTR:
        return "insptr";
        break;

        default:
        assert (false, "unsupported value type");
    }
}

/// Stack size, 256K words
immutable size_t STACK_SIZE = 2^^18;

/// Initial heap size, 16M bytes
immutable size_t HEAP_INIT_SIZE = 2^^24;

/// Initial link table size
immutable size_t LINK_TBL_INIT_SIZE = 8192;

/// Initial global class size
immutable size_t GLOBAL_CLASS_INIT_SIZE = 1024;

/// Initial global object size
immutable size_t GLOBAL_OBJ_INIT_SIZE = 512;

/**
Interpreter
*/
class Interp
{
    /// Word stack
    Word* wStack;

    /// Type stack
    Type* tStack;

    /// Word stack upper limit
    Word* wUpperLimit;

    /// Type stack upper limit
    Type* tUpperLimit;

    /// Word and type stack pointers (stack top)
    Word* wsp;

    /// Type stack pointer (stack top)
    Type* tsp;

    /// Heap start pointer
    ubyte* heapStart;

    /// Heap size
    size_t heapSize;

    /// Heap upper limit
    ubyte* heapLimit;

    /// Allocation pointer
    ubyte* allocPtr;

    /// To-space heap pointers, for garbage collection
    ubyte* toStart = null;
    ubyte* toLimit = null;
    ubyte* toAlloc = null;

    /// Linked list of GC roots
    GCRoot* firstRoot = null;

    /// Linked list of type sets
    TypeSet* firstSet = null;

    /// Set of weak references to functions referenced in the heap
    /// To be cleaned up by the GC
    IRFunction[void*] funRefs;

    /// Set of functions found live by the GC during collection
    IRFunction[void*] liveFuns;

    /// Garbage collection count
    size_t gcCount = 0;

    /// Link table words
    Word* wLinkTable;

    /// Link table types
    Type* tLinkTable;

    /// Link table size
    uint32 linkTblSize;

    /// Free link table entries
    uint32[] linkTblFree;

    /// Branch target block
    IRBlock target = null;

    /// Instruction pointer
    IRInstr ip = null;

    /// String table reference
    refptr strTbl;

    /// Object prototype object
    refptr objProto;

    /// Array prototype object
    refptr arrProto;

    /// Function prototype object
    refptr funProto;

    /// Global object reference
    refptr globalObj;

    /**
    Constructor, initializes/resets the interpreter state
    */
    this(bool loadStdLib = true)
    {
        // Allocate the word stack
        wStack = cast(Word*)GC.malloc(
            Word.sizeof * STACK_SIZE,
            GC.BlkAttr.NO_SCAN |
            GC.BlkAttr.NO_INTERIOR
        );

        // Allocate the type stack
        tStack = cast(Type*)GC.malloc(
            Type.sizeof * STACK_SIZE,
            GC.BlkAttr.NO_SCAN |
            GC.BlkAttr.NO_INTERIOR
        );

        // Initialize the stack limit pointers
        wUpperLimit = wStack + STACK_SIZE;
        tUpperLimit = tStack + STACK_SIZE;

        // Initialize the stack pointers just past the end of the stack
        wsp = wUpperLimit;
        tsp = tUpperLimit;

        // Allocate a block of immovable memory for the heap
        heapSize = HEAP_INIT_SIZE;
        heapStart = cast(ubyte*)GC.malloc(
            heapSize, 
            GC.BlkAttr.NO_SCAN |
            GC.BlkAttr.NO_INTERIOR
        );

        // Check that the allocation was successful
        if (heapStart is null)
            throw new Error("heap allocation failed");

        // Initialize the allocation and limit pointers
        allocPtr = heapStart;
        heapLimit = heapStart + heapSize;

        /// Link table size
        linkTblSize = LINK_TBL_INIT_SIZE;

        /// Free link table entries
        linkTblFree = new LinkIdx[linkTblSize];
        for (uint32 i = 0; i < linkTblSize; ++i)
            linkTblFree[i] = i;

        /// Link table words
        wLinkTable = cast(Word*)GC.malloc(
            Word.sizeof * linkTblSize,
            GC.BlkAttr.NO_SCAN |
            GC.BlkAttr.NO_INTERIOR
        );

        /// Link table types
        tLinkTable = cast(Type*)GC.malloc(
            Type.sizeof * linkTblSize,
            GC.BlkAttr.NO_SCAN |
            GC.BlkAttr.NO_INTERIOR
        );

        // Initialize the link table
        for (size_t i = 0; i < linkTblSize; ++i)
        {
            wLinkTable[i].int32Val = 0;
            tLinkTable[i] = Type.INT32;
        }

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
            null, 
            objProto,
            GLOBAL_CLASS_INIT_SIZE,
            GLOBAL_OBJ_INIT_SIZE
        );

        // Load the layout code
        load("interp/layout.js");

        // Load the runtime library
        load("interp/runtime.js");

        // If the standard library should be loaded
        if (loadStdLib)
        {
            load("stdlib/error.js");
            load("stdlib/object.js");
            load("stdlib/function.js");
            load("stdlib/math.js");
            load("stdlib/string.js");
            load("stdlib/array.js");
            load("stdlib/number.js");
            load("stdlib/boolean.js");
            load("stdlib/date.js");
            load("stdlib/json.js");
            load("stdlib/regexp.js");
            load("stdlib/global.js");
            load("stdlib/commonjs.js");
        }
    }

    /**
    Set the value and type of a stack slot
    */
    void setSlot(LocalIdx idx, Word w, Type t)
    {
        assert (
            &wsp[idx] >= wStack && &wsp[idx] < wUpperLimit,
            "invalid stack slot index"
        );

        assert (
            t != Type.REFPTR ||
            w.ptrVal == null ||
            (w.ptrVal >= heapStart && w.ptrVal < heapLimit),
            "ref ptr out of heap"
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
    void setSlot(LocalIdx idx, uint32 val)
    {
        setSlot(idx, Word.int32v(val), Type.INT32);
    }

    /**
    Set a stack slot to a float value
    */
    void setSlot(LocalIdx idx, float64 val)
    {
        setSlot(idx, Word.float64v(val), Type.FLOAT64);
    }

    /**
    Get a word from the word stack
    */
    Word getWord(LocalIdx idx)
    {
        assert (
            &wsp[idx] >= wStack && &wsp[idx] < wUpperLimit,
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
            &tsp[idx] >= tStack && &tsp[idx] < tUpperLimit,
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
            &wsp[src] >= wStack && &wsp[src] < wUpperLimit,
            "invalid move src index"
        );

        assert (
            &wsp[dst] >= wStack && &wsp[dst] < wUpperLimit,
            "invalid move dst index"
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

        if (wsp < wStack)
            throw new Error("interpreter stack overflow");
    }

    /**
    Free space on the stack
    */
    void pop(size_t numWords)
    {
        wsp += numWords;
        tsp += numWords;

        if (wsp > wUpperLimit)
            throw new Error("interpreter stack underflow");
    }

    /**
    Get the number of stack slots
    */
    size_t stackSize()
    {
        return wUpperLimit - wsp;
    }

    /**
    Allocate a link table entry
    */
    LinkIdx allocLink()
    {
        if (linkTblFree.length == 0)
        {
            assert (false, "no free link entries");
        }

        auto idx = linkTblFree.back;
        linkTblFree.popBack();

        return idx;
    }

    /**
    Free a link table entry
    */
    void freeLink(LinkIdx idx)
    {
        assert (
            idx <= linkTblSize,
            "invalid link index"
        );

        // Remove any heap reference
        wLinkTable[idx].uint32Val = 0;
        tLinkTable[idx] = Type.INT32;

        linkTblFree ~= idx;
    }

    /**
    Get the word associated with a link value
    */
    Word getLinkWord(LinkIdx idx)
    {
        assert (
            idx <= linkTblSize,
            "invalid link index"
        );

        return wLinkTable[idx];
    }

    /**
    Get the type associated with a link value
    */
    Type getLinkType(LinkIdx idx)
    {
        assert (
            idx <= linkTblSize,
            "invalid link index"
        );

        return tLinkTable[idx];
    }

    /**
    Set the word associated with a link value
    */
    void setLinkWord(LinkIdx idx, Word word)
    {
        assert (
            idx <= linkTblSize,
            "invalid link index"
        );

        wLinkTable[idx] = word;
    }

    /**
    Set the type associated with a link value
    */
    void setLinkType(LinkIdx idx, Type type)
    {
        assert (
            idx <= linkTblSize,
            "invalid link index"
        );

        tLinkTable[idx] = type;
    }

    /**
    Make the execution jump to a specific block
    */
    void jump(IRBlock block)
    {
        // Set the branch target block
        target = block;

        // Nullify the IP to stop the execution of the current block
        ip = null;
    }

    /**
    Execute the interpreter loop
    */
    void loop()
    {
        // While we have a target to branch to
        while (target !is null)
        {
            // FIXME: temporary for SSA refactoring
            /*
            // If this block was executed often enough and 
            // JIT compilation is enabled
            if (target.execCount > JIT_COMPILE_COUNT &&
                target.fun.codeBlock is null &&
                opts.jit_disable == false)
            {
                // Compile the function this block belongs to
                compFun(this, target.fun);
            }
            */

            // If this block has an associated entry point
            if (target.entryFn !is null)
            {
                auto entryFn = target.entryFn;
                target = null;

                //writefln("entering fn: %s (%s)", target.fun.getName(), target.getName());
                entryFn();
                //writefln("returned from fn");
                continue;
            }

            // Increment the execution count for the block
            target.execCount++;
            
            // Set the IP to the first instruction of the block
            ip = target.firstInstr;

            // Nullify the target pointer
            target = null;

            // Until the execution of the block is done
            while (ip !is null)
            {
                // Get the current instruction
                IRInstr instr = ip;

                //writefln("op: %s", instr.opcode.mnem);
     
                // Get the opcode's implementation function
                auto opFn = instr.opcode.opFn;

                assert (
                    opFn !is null,
                    format(
                        "unsupported opcode: %s",
                        instr.opcode.mnem
                    )
                );

                // Call the opcode's function
                opFn(this, instr);

                // Update the IP
                ip = instr.next;
            }

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

        // FIXME
        /*
        // Setup the callee stack frame
        interp.ops.callFun(
            this,
            fun,
            null,       // Null return address
            null,       // Null closure argument
            NULL,       // Null this argument
            Type.REFPTR,// This value is a reference
            []          // 0 arguments
        );
        */

        // Run the interpreter loop
        loop();

        // Ensure the stack contains at least one value
        assert (
            stackSize() >= 1,
            "stack is empty, no return value found"
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
    Get the path to load based on a (potentially relative) path
    */
    string getLoadPath(string fileName)
    {
        // If the path is relative, first check the Higgs lib dir
        if (!isAbsolute(fileName))
        {
            auto libFile = buildPath("/etc/higgs", fileName);
            if (!exists(fileName) && exists(libFile))
                fileName = to!string(libFile);
        }

        return fileName;
    }

    /**
    Parse and execute a source file
    */
    ValuePair load(string fileName)
    {
        auto file = getLoadPath(fileName);
        auto ast = parseFile(file);
        return exec(ast);
    }

    /**
    Parse and execute a source string
    */
    ValuePair evalString(string input, string fileName = "string")
    {
        //writefln("input: %s", input);

        auto ast = parseString(input, fileName);
        auto result = exec(ast);

        return result;
    }

    /// Stack frame visit function
    alias void delegate(
        IRFunction fun, 
        Word* wsp, 
        Type* tsp, 
        size_t depth,
        size_t frameSize,
        IRInstr callInstr
    ) VisitFrameFn;

    /**
    Visit each stack frame currently on the stack
    */
    void visitStack(VisitFrameFn visitFrame)
    {
        // If the stack is empty, stop
        if (this.stackSize() == 0)
            return;

        // Get the current stack pointers
        auto wsp = this.wsp;
        auto tsp = this.tsp;

        IRInstr curInstr = this.target? this.target.firstInstr:this.ip;
        assert (
            curInstr !is null, 
            "curInstr is null"
        );

        auto curFun = curInstr.block.fun;
        assert (
            curFun !is null, 
            "curFun is null"
        );

        // For each stack frame, starting from the topmost
        for (size_t depth = 0;; depth++)
        {
            auto numParams = curFun.numParams;
            auto numLocals = curFun.numLocals;
            auto raSlot = curFun.raVal.outSlot;
            auto argcSlot = curFun.argcVal.outSlot;

            assert (
                wsp + numLocals <= this.wUpperLimit, 
                "no room for numLocals in stack frame"
            );

            // Get the argument count
            auto argCount = wsp[argcSlot].int32Val;

            // Compute the actual number of extra arguments to pop
            size_t extraArgs = (argCount > numParams)? (argCount - numParams):0;

            // Compute the number of locals in this frame
            auto frameSize = numLocals + extraArgs;

            // Get the calling instruction for this frame
            curInstr = cast(IRInstr)wsp[raSlot].ptrVal;

            // Visit this stack frame
            visitFrame(
                curFun,
                wsp,
                tsp,
                depth,
                frameSize,
                curInstr
            );

            // If we reached the bottom of the stack, stop
            if (curInstr is null)
                break;

            // Move to the caller function
            curFun = curInstr.block.fun;
            assert (curFun !is null);

            // Move to the next stack frame
            wsp += frameSize;
            tsp += frameSize;
        }
    }
}

