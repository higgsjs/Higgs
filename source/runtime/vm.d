/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2015, Maxime Chevalier-Boisvert. All rights reserved.
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

module runtime.vm;

import core.memory;
import std.c.string;
import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.stdint;
import std.typecons;
import std.path;
import std.file;
import std.algorithm;
import options;
import stats;
import util.misc;
import parser.parser;
import parser.ast;
import ir.ir;
import ir.ast;
import runtime.layout;
import runtime.string;
import runtime.object;
import runtime.gc;
import jit.codeblock;
import jit.jit;

/**
Run-time error
*/
class RunError : Error
{
    /// Associated virtual machine
    VM vm;

    /// Exception value
    ValuePair excVal;

    /// Error constructor name
    string name;

    /// Error message
    string message;

    /// Stack trace
    IRInstr[] trace;

    this(VM vm, ValuePair excVal, IRInstr[] trace)
    {
        this.vm = vm;
        this.excVal = excVal;
        this.trace = trace;

        this.name = "run-time error";

        if (excVal.tag is Tag.OBJECT)
        {
            auto errName = getProp(excVal, "name"w);

            this.name = errName.toString;

            auto msgStr = getProp(excVal, "message"w);

            this.message = msgStr.toString;
        }
        else
        {
            this.message = excVal.toString;
        }

        super(toString());
    }

    override string toString()
    {
        string str = name ~ ": " ~ message;

        foreach (instr; trace)
        {
            auto fun = instr.block.fun;
            auto pos = instr.srcPos? instr.srcPos:fun.ast.pos;
            str ~= "\n" ~ fun.getName ~ " (" ~ to!string(pos) ~ ")";
        }

        return str;
    }
}

/**
Memory word union
*/
union Word
{
    static Word int32v(int32 i) { Word w; w.int64Val = 0; w.int32Val = i; return w; }
    static Word int64v(int64 i) { Word w; w.int64Val = i; return w; }
    static Word uint32v(uint32 i) { Word w; w.int64Val = 0; w.uint32Val = i; return w; }
    static Word uint64v(uint64 i) { Word w; w.uint64Val = i; return w; }
    static Word float64v(float64 f) { Word w; w.floatVal = f; return w; }
    static Word refv(refptr p) { Word w; w.ptrVal = p; return w; }
    static Word ptrv(rawptr p) { Word w; w.ptrVal = p; return w; }
    static Word funv(IRFunction f) { Word w; w.funVal = f; return w; }

    int8    int8Val;
    int16   int16Val;
    int32   int32Val;
    int64   int64Val;
    uint8   uint8Val;
    uint16  uint16Val;
    uint32  uint32Val;
    uint64  uint64Val;
    float64 floatVal;
    refptr  refVal;
    rawptr  ptrVal;

    IRFunction  funVal;
    IRInstr     insVal;
    ObjShape    shapeVal;
}

unittest
{
    assert (
        Word.sizeof == rawptr.sizeof,
        "word size does not match pointer size"
    );
}

/// Type tag values
enum Tag : ubyte
{
    CONST = 0,
    INT32,
    INT64,
    FLOAT64,
    RAWPTR,
    RETADDR,
    FUNPTR,
    SHAPEPTR,

    // GC heap pointer tags
    REFPTR,
    OBJECT,
    ARRAY,
    CLOSURE,
    STRING,
    ROPE
}

/**
Test if a given tag is a heap pointer
*/
bool isHeapPtr(Tag tag)
{
    switch (tag)
    {
        case Tag.REFPTR:
        case Tag.OBJECT:
        case Tag.ARRAY:
        case Tag.CLOSURE:
        case Tag.STRING:
        case Tag.ROPE:
        return true;

        case Tag.CONST:
        case Tag.INT32:
        case Tag.INT64:
        case Tag.FLOAT64:
        case Tag.RAWPTR:
        case Tag.RETADDR:
        case Tag.FUNPTR:
        case Tag.SHAPEPTR:
        return false;

        default:
        assert (false);
    }
}

/**
Test if a tag is an object of some kind
*/
bool isObject(Tag tag)
{
    switch (tag)
    {
        case Tag.OBJECT:
        case Tag.ARRAY:
        case Tag.CLOSURE:
        return true;

        default:
        return false;
    }
}

/**
Produce a string representation of a type tag
*/
string tagToString(Tag tag)
{
    // Switch on the type tag
    switch (tag)
    {
        case Tag.INT32:    return "int32";
        case Tag.INT64:    return "int64";
        case Tag.FLOAT64:  return "float64";
        case Tag.RAWPTR:   return "rawptr";
        case Tag.RETADDR:  return "retaddr";
        case Tag.CONST:    return "const";
        case Tag.FUNPTR:   return "funptr";
        case Tag.SHAPEPTR: return "shapeptr";

        case Tag.REFPTR:   return "refptr";
        case Tag.OBJECT:   return "object";
        case Tag.ARRAY:    return "array";
        case Tag.CLOSURE:  return "closure";
        case Tag.STRING:   return "string";
        case Tag.ROPE:     return "rope";

        default:
        assert (false, "unsupported type tag");
    }
}

/**
Test if a reference points to an object of a given layout
*/
bool refIsLayout(refptr ptr, uint32 layoutId)
{
    return (ptr !is null && obj_get_header(ptr) == layoutId);
}

/// Word and tag pair
struct ValuePair
{
    Word word;

    Tag tag;

    this(Word word, Tag tag)
    {
        this.word = word;
        this.tag = tag;
    }

    this(refptr ptr, Tag tag)
    {
        this.word.ptrVal = ptr;
        this.tag = tag;
    }

    this(int32 int32Val)
    {
        this.word = Word.int32v(int32Val);
        this.tag = Tag.INT32;
    }

    this(IRFunction fun)
    {
        this.word.funVal = fun;
        this.tag = Tag.FUNPTR;
    }

    /**
    Test if a value is an object of a given layout
    */
    bool isLayout(uint32 layoutId)
    {
        return (
            tag is Tag.REFPTR && 
            refIsLayout(word.ptrVal, layoutId)
        );
    }

    /**
    Produce a string representation of a value pair
    */
    string toString()
    {
        // Switch on the type tag
        switch (tag)
        {
            case Tag.INT32:
            return to!string(word.int32Val);

            case Tag.FLOAT64:
            if (word.floatVal != word.floatVal)
                return "NaN";
            if (word.floatVal == 1.0/0)
                return "Infinity";
            if (word.floatVal == -1.0/0)
                return "-Infinity";
            return format("%f", word.floatVal);

            case Tag.RAWPTR:
            if (word.ptrVal is null)
                return "nullptr";
            return to!string(word.ptrVal);

            case Tag.RETADDR:
            return to!string(word.ptrVal);

            case Tag.CONST:
            if (this == TRUE)
                return "true";
            if (this == FALSE)
                return "false";
            if (this == UNDEF)
                return "undefined";
            assert (
                false,
                "unsupported constant " ~ to!string(word.uint64Val)
            );

            case Tag.FUNPTR:
            return "funptr";

            case Tag.REFPTR:
            if (this == NULL)
                return "null";
            if (ptrValid(word.ptrVal) is false)
                return "invalid refptr";
            if (isLayout(LAYOUT_OBJ))
                return "object";
            if (isLayout(LAYOUT_CLOS))
                return "function";
            if (isLayout(LAYOUT_ARR))
                return "array";
            return "refptr";

            case Tag.OBJECT:
            return "object";

            case Tag.ARRAY:
            if (ptrValid(word.ptrVal) is false)
                return "invalid array ptr";
            auto len = getArrLen(word.ptrVal);
            auto tbl = getArrTbl(word.ptrVal);
            auto output = "[";
            for (uint32_t i = 0; i < len; ++i)
            {
                auto elWord = Word.uint64v(arrtbl_get_word(tbl, i));
                auto elTag = cast(Tag)arrtbl_get_tag(tbl, i);
                output ~= ValuePair(elWord, elTag).toString;
                if (i < len - 1)
                    output ~= ",";
            }
            return output ~ "]";

            case Tag.CLOSURE:
            return "closure";

            case Tag.STRING:
            return extractStr(word.ptrVal);

            case Tag.ROPE:
            return ropeToStr(word.ptrVal);

            default:
            assert (false, "unsupported value type");
        }
    }

    refptr ptr()
    {
        return word.ptrVal;
    }
}

// Note: low byte is set to allow for one byte immediate comparison
immutable NULL    = ValuePair(Word(0x00), Tag.REFPTR);
immutable TRUE    = ValuePair(Word(0x01), Tag.CONST);
immutable FALSE   = ValuePair(Word(0x02), Tag.CONST);
immutable UNDEF   = ValuePair(Word(0x03), Tag.CONST);

/// Stack size, 256K words (2MB)
immutable size_t STACK_SIZE = 2^^18;

/// Initial object heap size, release 128M, debug 16M bytes
version (release)
    immutable size_t HEAP_INIT_SIZE = 2 ^^ 27;
else
    immutable size_t HEAP_INIT_SIZE = 2 ^^ 24;

/// Initial link table size
immutable size_t LINK_TBL_INIT_SIZE = 16384;

/// Initial global object size
immutable size_t GLOBAL_OBJ_INIT_SIZE = 1024;

/// Initial executable heap size 16M bytes
immutable size_t EXEC_HEAP_INIT_SIZE = 2 ^^ 24;

/// Fraction of the executable heap reserved for stubs
immutable size_t EXEC_HEAP_STUB_FRAC = 8;

/// Initial subroutine heap size, 64K bytes
immutable size_t SUBS_HEAP_INIT_SIZE = 2 ^^ 16;

/// Global VM instance
VM vm = null;

/**
Virtual Machine (VM) instance
*/
class VM
{
    /// Word stack
    Word* wStack;

    /// Type stack
    Tag* tStack;

    /// Word stack upper limit
    Word* wUpperLimit;

    /// Type stack upper limit
    Tag* tUpperLimit;

    /// Word stack pointer (stack top)
    Word* wsp;

    /// Tag stack pointer (stack top)
    Tag* tsp;

    /// Heap start pointer
    ubyte* heapStart;

    /// Heap size
    size_t heapSize = HEAP_INIT_SIZE;

    /// Heap upper limit
    ubyte* heapLimit;

    /// Allocation pointer
    ubyte* allocPtr;

    /// To-space heap pointers, for garbage collection
    ubyte* toStart;
    ubyte* toLimit;
    ubyte* toAlloc;

    /// Linked list of GC roots
    GCRoot* firstRoot;

    /// Set of weak references to functions referenced in the heap
    /// To be cleaned up by the GC
    IRFunction[void*] funRefs;

    /// Set of functions found live by the GC during collection
    IRFunction[void*] liveFuns;

    /// Garbage collection count
    size_t gcCount = 0;

    /// String table reference
    refptr strTbl;

    /// Empty object shape
    ObjShape emptyShape;

    /// Initial array shape
    ObjShape arrayShape;

    /// Object prototype object
    ValuePair objProto;

    /// Array prototype object
    ValuePair arrProto;

    /// Function prototype object
    ValuePair funProto;

    /// String prototype object
    ValuePair strProto;

    /// Global object reference
    ValuePair globalObj;

    /// Runtime error value (uncaught exceptions)
    RunError runError;

    /// Current instruction (set when calling into host code)
    IRInstr curInstr;

    /// Executable heap
    CodeBlock execHeap;

    /// Stub space start position
    size_t stubStartPos;

    /// Current stub space write position
    size_t stubWritePos;

    /// Subroutine heap
    CodeBlock subsHeap;

    /// Map of return addresses to return entries
    RetEntry[CodePtr] retAddrMap;

    /// List of code fragments, in memory order
    CodeFragment[] fragList;

    /// Queue of block versions to be compiled
    CodeFragment[] compQueue;

    /// List of references to code fragments to be linked
    FragmentRef[] refList;

    /// Generic function entry stub
    EntryStub entryStub;

    /// Generic branch target stubs
    BranchStub[] branchStubs;

    /// Generic call continuation stub
    ContStub contStub;

    /// Space to save registers when calling into hosted code
    Word* regSave;

    /**
    Initialize or reinitialize the global VM object
    */
    static void init(bool loadRuntime = true, bool loadStdLib = true)
    {
        assert (
            !(loadStdLib && !loadRuntime),
            "cannot load stdlib without loading runtime"
        );

        // If a VM object was already created
        if (vm !is null)
        {
            // Explicitly free the VM object and its resources
            VM.free();
        }

        // Allocate the global VM object
        vm = new VM();

        with (vm)
        {
            // Allocate the word stack
            wStack = cast(Word*)GC.malloc(
                Word.sizeof * STACK_SIZE,
                GC.BlkAttr.NO_SCAN |
                GC.BlkAttr.NO_INTERIOR |
                GC.BlkAttr.NO_MOVE
            );

            // Allocate the tag stack
            tStack = cast(Tag*)GC.malloc(
                Tag.sizeof * STACK_SIZE,
                GC.BlkAttr.NO_SCAN |
                GC.BlkAttr.NO_INTERIOR |
                GC.BlkAttr.NO_MOVE
            );

            // Initialize the stack limit pointers
            wUpperLimit = wStack + STACK_SIZE;
            tUpperLimit = tStack + STACK_SIZE;

            // Initialize the stack pointers just past the end of the stack
            wsp = wUpperLimit;
            tsp = tUpperLimit;

            // Allocate two blocks of immovable memory
            // for the from-space and to-space heaps
            heapStart = allocHeapBlock(vm, heapSize);
            toStart = allocHeapBlock(vm, heapSize);

            // Initialize the from-space heap to zero
            memset(heapStart, 0, heapSize);

            // Initialize the allocation and limit pointers
            allocPtr = heapStart;
            heapLimit = heapStart + heapSize;
            toAlloc = toStart;
            toLimit = toStart + heapSize;

            // Allocate and initialize the string table
            strTbl = strtbl_alloc(vm, STR_TBL_INIT_SIZE);

            // Allocate the empty object shape
            emptyShape = new ObjShape();

            // Initialize the initial array shape
            arrayShape = emptyShape.defProp(
                "__proto__",
                ValType(Tag.OBJECT),
                ATTR_CONST_NOT_ENUM,
                null
            ).defProp(
                "__arrTbl__",
                ValType(Tag.REFPTR),
                ATTR_CONST_NOT_ENUM,
                null
            ).defProp(
                "__arrLen__",
                ValType(Tag.INT32),
                ATTR_CONST_NOT_ENUM,
                null
            );

            // Allocate the object prototype object
            objProto = newObj(NULL);

            // Allocate the array prototype object
            arrProto = newObj(objProto);

            // Allocate the string prototype object
            strProto = newObj(objProto);

            // Allocate the function prototype object
            funProto = newObj(objProto);

            // Allocate the global object
            globalObj = newObj(objProto, GLOBAL_OBJ_INIT_SIZE);

            // Allocate the executable heap
            execHeap = new CodeBlock(EXEC_HEAP_INIT_SIZE, opts.genasm);

            // Compute the stub space start position
            stubStartPos = execHeap.getSize - (execHeap.getSize / EXEC_HEAP_STUB_FRAC);
            stubWritePos = stubStartPos;

            // Allocate the subroutine heap
            subsHeap = new CodeBlock(SUBS_HEAP_INIT_SIZE, opts.genasm);

            // Allocate the register save space
            regSave = cast(Word*)GC.malloc(
                Word.sizeof * allocRegs.length,
                GC.BlkAttr.NO_SCAN |
                GC.BlkAttr.NO_INTERIOR
            );

            // Define the object-related constants
            defObjConsts(vm);

            // Generate the generic JIT stubs
            genStubs(vm);

            // If the runtime library should be loaded
            if (loadRuntime)
            {
                // Load the layout code
                load("runtime/layout.js", true);

                // Load the runtime library
                load("runtime/runtime.js", true);
            }

            // If the standard library should be loaded
            if (loadStdLib)
            {
                load("stdlib/object.js");
                load("stdlib/error.js");
                load("stdlib/function.js");
                load("stdlib/math.js");
                load("stdlib/string.js");
                load("stdlib/array.js");
                load("stdlib/number.js");
                load("stdlib/boolean.js");
                load("stdlib/date.js");
                load("stdlib/map.js");
                load("stdlib/set.js");
                load("stdlib/json.js");
                load("stdlib/regexp.js");
                load("stdlib/global.js");
                load("stdlib/typedarrays.js");
                load("stdlib/commonjs.js");
            }
        }
    }

    /**
    Free the global VM object and its allocated resources
    Note: we intentionally do not rely on the VM destructor
    because D does not guarantee destructor call order
    */
    static void free()
    {
        with (vm)
        {
            // Free the stacks
            GC.free(wStack);
            GC.free(tStack);

            // Free the heap blocks
            GC.free(heapStart);
            GC.free(toStart);

            // Destroy the root shapes
            destroy(arrayShape);
            destroy(emptyShape);

            // Destroy the executable heaps
            destroy(execHeap);
            destroy(subsHeap);

            // Free the IRFunction references
            foreach (ptr, fun; funRefs)
                destroy(fun);

            // Unregister all the GC roots to prevent them from
            // touching the VM object after the it is destroyed
            for (auto root = firstRoot; root !is null;)
            {
                auto next = root.nextRoot;
                destroy(root);
                root = next;
            }
        }

        // Destroy the VM object itself
        destroy(vm);

        // Nullify the global VM object pointer
        vm = null;
    }

    /**
    Do not call the VM constructor directly
    */
    private this()
    {
    }

    /**
    Do not call the VM destructor directly
    */
    private ~this()
    {
    }

    /**
    Set the value and type of a stack slot
    */
    void setSlot(StackIdx idx, Word w, Tag t)
    {
        assert (
            &wsp[idx] >= wStack && &wsp[idx] < wUpperLimit,
            format("invalid stack slot index (%s/%s)", idx, stackSize)
        );

        assert (
            !isHeapPtr(t) ||
            w.ptrVal == null ||
            (w.ptrVal >= heapStart && w.ptrVal < heapLimit),
            "ref ptr out of heap in setSlot: " ~
            to!string(w.ptrVal)
        );

        wsp[idx] = w;
        tsp[idx] = t;
    }

    /**
    Set the value and type of a stack slot from a value/type pair
    */
    void setSlot(StackIdx idx, ValuePair val)
    {
        setSlot(idx, val.word, val.tag);
    }

    /**
    Set a stack slot to an integer value
    */
    void setSlot(StackIdx idx, uint32 val)
    {
        setSlot(idx, Word.int32v(val), Tag.INT32);
    }

    /**
    Set a stack slot to a float value
    */
    void setSlot(StackIdx idx, float64 val)
    {
        setSlot(idx, Word.float64v(val), Tag.FLOAT64);
    }

    /**
    Get a word from the word stack
    */
    Word getWord(StackIdx idx)
    {
        assert (
            &wsp[idx] >= wStack && &wsp[idx] < wUpperLimit,
            format("invalid stack slot index (%s/%s)", idx, stackSize)
        );

        return wsp[idx];
    }

    /**
    Get a type tag from the tag stack
    */
    Tag getTag(StackIdx idx)
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
    ValuePair getSlot(StackIdx idx)
    {
        return ValuePair(getWord(idx), getTag(idx));
    }

    /**
    Copy a value from one stack slot to another
    */
    void move(StackIdx src, StackIdx dst)
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
    Push a word and tag on the stack
    */
    void push(Word w, Tag t)
    {
        push(1);
        setSlot(0, w, t);
    }

    /**
    Push a value pair on the stack
    */
    void push(ValuePair val)
    {
        push(1);
        setSlot(0, val.word, val.tag);
    }

    /**
    Allocate space on the stack
    */
    void push(size_t numWords)
    {
        wsp -= numWords;
        tsp -= numWords;

        if (wsp < wStack)
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
    Get the value pair for an IR value
    */
    ValuePair getValue(IRValue val)
    {
        // If the value has an associated output slot
        if (auto dstVal = cast(IRDstValue)val)
        {
            assert (
                dstVal.outSlot != NULL_STACK,
                "out slot unassigned for:\n" ~
                dstVal.toString()
            );

            // Get the value at the output slot
            return getSlot(dstVal.outSlot);
        }

        // If the value is a string
        if (auto strVal = cast(IRString)val)
        {
            return ValuePair(strVal.getPtr(this), Tag.STRING);
        }

        // Get the constant value pair for this IR value
        return val.cstValue();
    }

    /**
    Get the value of an instruction's argument
    */
    ValuePair getArgVal(IRInstr instr, size_t argIdx)
    {
        // Get the argument IRValue
        auto val = instr.getArg(argIdx);

        return getValue(val);
    }

    /**
    Get a boolean argument value
    */
    bool getArgBool(IRInstr instr, size_t argIdx)
    {
        auto argVal = getArgVal(instr, argIdx);

        assert (
            argVal.tag == Tag.CONST,
            "expected constant value for arg " ~ to!string(argIdx)
        );

        return (argVal.word.int8Val == TRUE.word.int8Val);
    }

    /**
    Get an argument value and ensure it is an uint32
    */
    uint32_t getArgUint32(IRInstr instr, size_t argIdx)
    {
        auto argVal = getArgVal(instr, argIdx);

        assert (
            argVal.tag == Tag.INT32,
            "expected uint32 value for arg " ~ to!string(argIdx)
        );

        assert (
            argVal.word.int32Val >= 0,
            "expected positive value"
        );

        return argVal.word.uint32Val;
    }

    /**
    Get an argument value and ensure it is a string object pointer
    */
    refptr getArgStr(IRInstr instr, size_t argIdx)
    {
        auto strVal = getArgVal(instr, argIdx);

        assert (
            strVal.tag is Tag.STRING,
            format("expected string value for arg %s of:\n%s", argIdx, instr)
        );

        return strVal.word.ptrVal;
    }

    /**
    Prepares the callee stack-frame for a call
    */
    void callFun(
        IRFunction fun,         // Function to call
        CodePtr retAddr,        // Return address
        refptr closPtr,         // Closure pointer
        ValuePair thisVal,      // This value
        uint32_t argCount,
        ValuePair* argVals
    )
    {
        //writefln("call to %s (%s)", fun.name, cast(void*)fun);
        //writefln("num args: %s", argCount);
        //writeln("clos ptr: ", closPtr);

        assert (
            fun !is null,
            "null IRFunction pointer"
        );

        // Compute the number of missing arguments
        size_t argDiff = (fun.numParams > argCount)? (fun.numParams - argCount):0;

        // Push undefined values for the missing last arguments
        for (size_t i = 0; i < argDiff; ++i)
            push(UNDEF);

        // Push the visible function arguments in reverse order
        for (size_t i = 0; i < argCount; ++i)
        {
            auto argVal = argVals[argCount-(1+i)];
            push(argVal);
        }

        // Push the argument count
        push(Word.int32v(argCount), Tag.INT32);

        // Push the "this" argument
        push(thisVal);

        // Push the closure argument
        push(Word.ptrv(closPtr), Tag.CLOSURE);

        // Push the return address
        push(Word.ptrv(cast(rawptr)retAddr), Tag.RETADDR);

        // Push space for the callee locals
        auto numLocals = fun.numLocals - NUM_HIDDEN_ARGS - fun.numParams;
        push(numLocals);
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

        // Compile the entry block of the unit function
        auto entryFn = compileUnit(this, fun);

        // Start recording execution time
        stats.execTimeStart();

        // Call into the compiled code
        entryFn();

        // Stop recording execution time
        stats.execTimeStop();

        // If a runtime error occurred, throw the exception object
        if (runError)
        {
            auto error = runError;
            runError = null;
            throw error;
        }

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
    Get the path for a load command based on a (potentially relative) path
    */
    string getLoadPath(string fileName)
    {
        // If the path is relative, first check the Higgs lib dir
        if (!isAbsolute(fileName))
        {
            auto libFile = buildPath(import("libdir.txt"), fileName);
            if (!exists(fileName) && exists(libFile))
                fileName = to!string(libFile);
        }

        return fileName;
    }

    /**
    Parse and execute a source file
    */
    ValuePair load(string fileName, bool isRuntime = false)
    {
        //writeln("load(", fileName, ")");
        auto file = getLoadPath(fileName);

        // Start recording compilation time
        stats.compTimeStart();

        auto ast = parseFile(file, isRuntime);
        auto ir = astToIR(ast, null);

        // Stop recording compilation time
        stats.compTimeStop();

        return exec(ir);
    }

    /**
    Parse and execute a source string
    */
    ValuePair evalString(string input, string fileName = "string")
    {
        //writefln("input: %s", input);

        auto ast = parseString(input, fileName);
        auto ir = astToIR(ast, null);

        return exec(ir);
    }

    /// Stack frame visit function
    alias VisitFrameFn = void delegate(
        IRFunction fun,
        Word* wsp,
        Tag* tsp,
        size_t depth,
        size_t frameSize,
        IRInstr curInstr
    );

    /**
    Visit each stack frame currently on the stack
    */
    void visitStack(VisitFrameFn visitFrame)
    {
        // If the stack is empty, stop
        if (this.stackSize() is 0)
            return;

        // Get the current stack pointers
        auto wsp = this.wsp;
        auto tsp = this.tsp;

        // Current instruction
        assert (
            curInstr !is null,
            "VM.curInstr is null"
        );
        auto curInstr = this.curInstr;

        // For each stack frame, starting from the topmost
        for (size_t depth = 0;; depth++)
        {
            assert (curInstr !is null);
            auto curFun = curInstr.block.fun;
            assert (curFun !is null);

            auto numLocals = curFun.numLocals;
            auto numParams = curFun.numParams;
            auto argcSlot  = curFun.argcVal.outSlot;
            auto raSlot    = curFun.raVal.outSlot;

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

            //writeln("curFun: ", curFun.getName);
            //writeln("numLocals=", numLocals);
            //writeln("argcSlot=", argcSlot);
            //writeln("raSlot=", raSlot);
            //writeln("argCount=", argCount);
            //writeln("frameSize=", frameSize);

            // Get the return address
            auto retAddr = cast(CodePtr)wsp[raSlot].ptrVal;

            // Find the return address entry
            assert (
                retAddr in retAddrMap,
                "no return entry for return address: " ~ to!string(retAddr)
            );
            auto retEntry = retAddrMap[retAddr];

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
            if (retEntry.callInstr is null)
                break;

            // Pop the stack frame
            wsp += frameSize;
            tsp += frameSize;

            // Move to the caller frame's context
            curInstr = retEntry.callInstr;
        }
    }

    /**
    Define a constant on the global object
    */
    void defConst(wstring name, ValuePair val, bool enumerable = false)
    {
        runtime.object.defConst(globalObj, name, val, enumerable);
    }

    /**
    Define a run-time constant on the global object
    */
    void defRTConst(alias cstIdent)(wstring name = "")
    {
        if (name == "")
            name = to!wstring(__traits(identifier, cstIdent));

        ValuePair valPair;
        static if (__traits(isIntegral, cstIdent))
            valPair = ValuePair(cstIdent);
        else
            valPair = cstIdent;

        assert (name.toUpper == name);
        return defConst(RT_PREFIX ~ name, valPair, false);
    }
}

/**
Throw an exception, unwinding the stack until an exception handler
is found. Returns a pointer to the exception handler code.
*/
extern (C) CodePtr throwExc(
    VM vm,
    IRInstr throwInstr,
    CodeFragment throwHandler,
    Word excWord,
    Tag excTag
)
{
    //writefln("entering throwExc");

    // Stack trace (throwing instruction and call instructions)
    IRInstr[] trace;

    // Get the exception handler code, if supplied
    auto curHandler = throwHandler;

    // Get a GC root for the exception object
    auto exc = GCRoot(excWord, excTag);

    // If the exception value is an object,
    // add trace information to the object
    if (exc.tag is Tag.OBJECT)
    {
        assert (vm.curInstr is null);
        vm.curInstr = throwInstr;

        auto visitFrame = delegate void(
            IRFunction fun,
            Word* wsp,
            Tag* tsp,
            size_t depth,
            size_t frameSize,
            IRInstr curInstr
        )
        {
            auto propName = to!wstring(depth);

            auto pos = curInstr.srcPos? curInstr.srcPos:fun.ast.pos;
            auto str = GCRoot(
                getString(
                    vm,
                    to!wstring(
                        curInstr.block.fun.getName ~
                        " (" ~ pos.toString ~ ")"
                    )
                ),
                Tag.STRING
            );

            setProp(
                exc.pair,
                propName,
                str.pair
            );

            setProp(
                exc.pair,
                "length"w,
                ValuePair(Word.int64v(depth), Tag.INT32)
            );
        };

        vm.visitStack(visitFrame);

        vm.curInstr = null;
    }

    // Until we're done unwinding the stack
    for (IRInstr curInstr = throwInstr;;)
    {
        assert (curInstr !is null);

        //writeln("unwinding: ", curInstr.toString, " in ", curInstr.block.fun.getName);
        //writeln("stack size: ", vm.stackSize);

        // Add the current instruction to the stack trace
        trace ~= curInstr;

        // If the current instruction has an exception handler
        if (curHandler !is null)
        {
            //writefln("found exception handler");

            // If the exception handler is not yet compiled, compile it
            if (curHandler.ended is false)
            {
                auto excTarget = curInstr.getTarget(1);

                vm.queue(curHandler);
                vm.compile(excTarget.target.firstInstr);
            }

            auto excCodeAddr = curHandler.getCodePtr(vm.execHeap);

            // Push the exception value on the stack
            vm.push(exc.word, exc.tag);

            // Return the exception handler address
            return excCodeAddr;
        }

        auto curFun = curInstr.block.fun;
        assert (curFun !is null);

        auto numLocals = curFun.numLocals;
        auto numParams = curFun.numParams;
        auto argcSlot  = curFun.argcVal.outSlot;
        auto raSlot    = curFun.raVal.outSlot;

        // Get the return address
        auto retAddr = cast(CodePtr)vm.wsp[raSlot].ptrVal;

        // Find the return address entry
        assert (
            retAddr in vm.retAddrMap,
            "no return entry for return address: " ~ to!string(retAddr)
        );
        auto retEntry = vm.retAddrMap[retAddr];

        // Get the calling instruction and context for this stack frame
        curInstr = retEntry.callInstr;

        // If we have reached the bottom of the stack
        if (curInstr is null)
        {
            //writeln("reached stack bottom");

            assert (retEntry.retCode !is null);

            // Set the runtime error value
            vm.runError = new RunError(vm, exc.pair, trace);

            // Return the return code branch
            return retEntry.retCode.getCodePtr(vm.execHeap);
        }

        // Get the exception handler code for the calling instruction
        if (retEntry.excCode)
        {
            curHandler = retEntry.excCode;
        }

        // Get the argument count
        auto argCount = vm.wsp[argcSlot].int32Val;

        // Compute the actual number of extra arguments to pop
        size_t extraArgs = (argCount > numParams)? (argCount - numParams):0;

        // Pop all local stack slots and arguments
        vm.pop(numLocals + extraArgs);
    }

    assert (false);
}

/**
Throw a JavaScript error object as an exception
*/
extern (C) CodePtr throwError(
    VM vm,
    IRInstr throwInstr,
    CodeFragment throwHandler,
    string ctorName,
    string errMsg
)
{
    vm.setCurInstr(throwInstr);

    auto errStr = GCRoot(
        getString(vm, to!wstring(errMsg)),
        Tag.STRING
    );

    auto errCtor = GCRoot(
        getProp(
            vm.globalObj,
            to!wstring(ctorName)
        )
    );

    // If the error constructor is a function
    if (errCtor.tag is Tag.CLOSURE)
    {
        auto errProto = GCRoot(
            getProp(
                errCtor.pair,
                "prototype"w
            )
        );

        // If the error prototype is an object
        if (errProto.tag is Tag.OBJECT)
        {
            // Create the error object
            auto excObj = GCRoot(newObj(errProto.pair));

            // Set the error "message" property
            setProp(
                excObj.pair,
                "message"w,
                errStr.pair
            );

            vm.setCurInstr(null);

            return throwExc(
                vm,
                throwInstr,
                throwHandler,
                excObj.word,
                excObj.tag
            );
        }
    }

    vm.setCurInstr(null);

    // Throw the error string directly
    return throwExc(
        vm,
        throwInstr,
        throwHandler,
        errStr.word,
        errStr.tag,
    );
}

