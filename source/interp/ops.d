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

module interp.ops;

import core.sys.posix.dlfcn;
import std.stdio;
import std.algorithm;
import std.string;
import std.conv;
import std.math;
import std.datetime;
import std.stdint;
import parser.parser;
import ir.ir;
import ir.ops;
import ir.ast;
import interp.interp;
import interp.layout;
import interp.string;
import interp.object;
import interp.gc;
import interp.ffi;

/**
Get the value of an instruction's argument
*/
private ValuePair getArgVal(Interp interp, IRInstr instr, size_t argIdx)
{
    // Get the argument IRValue
    auto val = instr.getArg(argIdx);

    return interp.getValue(val);
}

/**
Get a boolean argument value
*/
bool getArgBool(Interp interp, IRInstr instr, size_t argIdx)
{
    auto argVal = interp.getArgVal(instr, argIdx);

    assert (
        argVal.type == Type.CONST,
        "expected constant value for arg " ~ to!string(argIdx)
    );

    return (argVal.word.int8Val == TRUE.int8Val);
}

/**
Get an argument value and ensure it is an uint32
*/
uint32_t getArgUint32(Interp interp, IRInstr instr, size_t argIdx)
{
    auto argVal = interp.getArgVal(instr, argIdx);

    assert (
        argVal.type == Type.INT32,
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
refptr getArgStr(Interp interp, IRInstr instr, size_t argIdx)
{
    auto strVal = interp.getArgVal(instr, argIdx);

    assert (
        valIsString(strVal.word, strVal.type),
        "expected string value for arg " ~ to!string(argIdx)
    );

    return strVal.word.ptrVal;
}

// FIXME
/*
void throwExc(Interp interp, IRInstr instr, ValuePair excVal)
{
    //writefln("throw");

    // Stack trace (call instructions and throwing instruction)
    IRInstr[] trace;

    // Until we're done unwinding the stack
    for (IRInstr curInstr = instr;;)
    {
        // If we have reached the bottom of the stack
        if (curInstr is null)
        {
            //writefln("reached bottom of stack");

            // Throw run-time error exception
            throw new RunError(interp, excVal, trace);
        }

        // Add the current instruction to the stack trace
        trace ~= curInstr;

        // If this is a call instruction and it has an exception target
        if (curInstr.opcode is &CALL && curInstr.getTarget(1) !is null)
        {
            //writefln("found exception target");

            // Set the return value slot to the exception value
            interp.setSlot(
                curInstr.outSlot, 
                excVal
            );

            // Go to the exception target
            interp.branch(curInstr.getTarget(1));

            // Stop unwinding the stack
            return;
        }

        auto numLocals = curInstr.block.fun.numLocals;
        auto numParams = curInstr.block.fun.numParams;
        auto argcSlot = curInstr.block.fun.argcVal.outSlot;
        auto raSlot = curInstr.block.fun.raVal.outSlot;

        // Get the calling instruction for the current stack frame
        curInstr = cast(IRInstr)interp.wsp[raSlot].ptrVal;

        // Get the argument count
        auto argCount = interp.wsp[argcSlot].int32Val;

        // Compute the actual number of extra arguments to pop
        size_t extraArgs = (argCount > numParams)? (argCount - numParams):0;

        // Pop all local stack slots and arguments
        interp.pop(numLocals + extraArgs);
    }
}
*/

void throwError(
    Interp interp,
    IRInstr instr,
    string ctorName, 
    string errMsg
)
{
    assert (false);

    // FIXME
    /*
    auto errStr = GCRoot(interp, getString(interp, to!wstring(errMsg)));

    auto ctorStr = GCRoot(interp, getString(interp, to!wstring(ctorName)));
    auto errCtor = GCRoot(
        interp,
        getProp(
            interp,
            interp.globalObj,
            ctorStr.ptr
        )
    );

    if (errCtor.type == Type.REFPTR &&
        valIsLayout(errCtor.word, LAYOUT_OBJ))
    {
        auto protoStr = GCRoot(interp, getString(interp, "prototype"w));
        auto errProto = GCRoot(
            interp,
            getProp(
                interp,
                errCtor.ptr,
                protoStr.ptr
            )
        );

        if (errProto.type == Type.REFPTR &&
            valIsLayout(errCtor.word, LAYOUT_OBJ))
        {
            // Create the error object
            auto excObj = GCRoot(
                interp,
                    newObj(
                    interp, 
                    new ObjMap(interp, 1), 
                    errProto.ptr
                )
            );

            // Set the error "message" property
            auto msgStr = GCRoot(interp, getString(interp, "message"w));
            setProp(
                interp,
                excObj.ptr,
                msgStr.ptr,
                errStr.pair
            );

            throwExc(
                interp,
                instr,
                excObj.pair
            );

            return;
        }
    }

    // Throw the error string directly
    throwExc(
        interp,
        instr,
        errStr.pair
    );
    */
}

extern (C) void op_set_str(Interp interp, IRInstr instr)
{
    auto linkArg = cast(IRLinkIdx)instr.getArg(1);
    assert (linkArg !is null);
    auto linkIdx = &linkArg.linkIdx;

    if (*linkIdx is NULL_LINK)
    {
        // Find the string in the string table
        auto strArg = cast(IRString)instr.getArg(0);
        assert (strArg !is null);
        auto strPtr = getString(interp, strArg.str);

        // Allocate a link table entry
        *linkIdx = interp.allocLink();

        interp.setLinkWord(*linkIdx, Word.ptrv(strPtr));
        interp.setLinkType(*linkIdx, Type.REFPTR);
    }

    //writefln("setting str %s", (cast(IRString)instr.getArg(0)).str);

    interp.setSlot(
        instr.outSlot,
        interp.getLinkWord(*linkIdx),
        Type.REFPTR
    );
}

/*
extern (C) void op_floor_f64(Interp interp, IRInstr instr)
{
    auto v0 = interp.getArgVal(instr, 0);

    assert (v0.type == Type.FLOAT64, "invalid operand type in floor");

    auto r = floor(v0.word.floatVal);

    if (r >= int32.min && r <= int32.max)
    {
        interp.setSlot(
            instr.outSlot,
            Word.int32v(cast(int32)r),
            Type.INT32
        );
    }
    else
    {
        interp.setSlot(
            instr.outSlot,
            Word.float64v(r),
            Type.FLOAT64
        );
    }
}

extern (C) void op_ceil_f64(Interp interp, IRInstr instr)
{
    auto v0 = interp.getArgVal(instr, 0);

    assert (v0.type == Type.FLOAT64, "invalid operand type in ceil");

    auto r = ceil(v0.word.floatVal);

    if (r >= int32.min && r <= int32.max)
    {
        interp.setSlot(
            instr.outSlot,
            Word.int32v(cast(int32)r),
            Type.INT32
        );
    }
    else
    {
        interp.setSlot(
            instr.outSlot,
            Word.float64v(r),
            Type.FLOAT64
        );
    }
}
*/

/*
extern (C) void op_call(Interp interp, IRInstr instr)
{
    auto closVal = interp.getArgVal(instr, 0);
    auto thisVal = interp.getArgVal(instr, 1);

    if (closVal.type != Type.REFPTR || !valIsLayout(closVal.word, LAYOUT_CLOS))
        return throwError(interp, instr, "TypeError", "call to non-function");

    // Get the function object from the closure
    auto closPtr = closVal.word.ptrVal;
    auto fun = getClosFun(closPtr);

    //writeln(core.memory.GC.addrOf(cast(void*)fun));

    auto argCount = cast(uint32_t)instr.numArgs - 2;

    // Allocate temporary storage for the argument values
    if (argCount > interp.tempVals.length)
        interp.tempVals.length = argCount;
    auto argVals = interp.tempVals.ptr;

    // Fetch the argument values
    for (size_t i = 0; i < argCount; ++i)
        argVals[i] = interp.getArgVal(instr, 2 + i);

    interp.callFun(
        fun,
        instr,
        closPtr,
        thisVal.word,
        thisVal.type,
        argCount,
        argVals
    );
}
*/

/*
/// JavaScript new operator (constructor call)
extern (C) void op_call_new(Interp interp, IRInstr instr)
{
    auto closVal = interp.getArgVal(instr, 0);

    if (closVal.type != Type.REFPTR || !valIsLayout(closVal.word, LAYOUT_CLOS))
        return throwError(interp, instr, "TypeError", "call to non-function");

    // Get the function object from the closure
    auto clos = GCRoot(interp, closVal.word.ptrVal);
    auto fun = getClosFun(clos.ptr);

    assert (
        fun !is null,
        "null IRFunction pointer"
    );

    // Lookup the "prototype" property on the closure
    auto protoStr = GCRoot(interp, getString(interp, "prototype"));
    auto protoObj = GCRoot(
        interp,
        getProp(
            interp, 
            clos.ptr,
            protoStr.ptr
        )
    );

    // Get the "this" object map from the closure
    auto ctorMap = cast(ObjMap)clos_get_ctor_map(clos.ptr);

    // Lazily allocate the "this" object map if it doesn't already exist
    if (ctorMap is null)
    {
        ctorMap = new ObjMap(interp, 0);
        clos_set_ctor_map(clos.ptr, cast(rawptr)ctorMap);
    }

    // Allocate the "this" object
    auto thisObj = GCRoot(
        interp,
        newObj(
            interp, 
            ctorMap,
            protoObj.ptr
        )
    );

    // Stack-allocate an array for the argument values
    auto argCount = cast(uint32_t)instr.numArgs - 1;

    // Allocate temporary storage for the argument values
    if (argCount > interp.tempVals.length)
        interp.tempVals.length = argCount;
    auto argVals = interp.tempVals.ptr;

    // Fetch the argument values
    for (size_t i = 0; i < argCount; ++i)
        argVals[i] = interp.getArgVal(instr, 1 + i);

    interp.callFun(
        fun,
        instr,
        clos.ptr,
        thisObj.word,
        Type.REFPTR,
        argCount,
        argVals
    );
}
*/

/*
extern (C) void op_call_apply(Interp interp, IRInstr instr)
{
    auto closVal = interp.getArgVal(instr, 0);
    auto thisVal = interp.getArgVal(instr, 1);
    auto tblVal = interp.getArgVal(instr, 2);
    auto argCount = interp.getArgUint32(instr, 3);

    if (closVal.type != Type.REFPTR || !valIsLayout(closVal.word, LAYOUT_CLOS))
        return throwError(interp, instr, "TypeError", "call to non-function");

    if (tblVal.type != Type.REFPTR || !valIsLayout(tblVal.word, LAYOUT_ARRTBL))
        return throwError(interp, instr, "TypeError", "invalid argument table");

    // Get the function object from the closure
    auto closPtr = closVal.word.ptrVal;
    auto fun = getClosFun(closPtr);

    // Get the array table pointer
    auto tblPtr = tblVal.word.ptrVal;

    // Allocate temporary storage for the argument values
    if (argCount > interp.tempVals.length)
        interp.tempVals.length = argCount;
    auto argVals = interp.tempVals.ptr;

    // Fetch the argument values from the array table
    for (uint32_t i = 0; i < argCount; ++i)
    {
        argVals[i].word.uint64Val = arrtbl_get_word(tblPtr, i);
        argVals[i].type = cast(Type)arrtbl_get_type(tblPtr, i);
    }

    interp.callFun(
        fun,
        instr,
        closPtr,
        thisVal.word,
        thisVal.type,
        argCount,
        argVals
    );
}
*/

/*
extern (C) void op_call_prim(Interp interp, IRInstr instr)
{
    // Name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Cached function pointer
    auto funArg = cast(IRFunPtr)instr.getArg(1);
    assert (funArg !is null);

    // If the function pointer is not yet cached
    if (funArg.fun is null)
    {
        auto propStr = GCRoot(interp, getString(interp, nameStr));
        ValuePair val = getProp(
            interp,
            interp.globalObj,
            propStr.ptr
        );

        assert (
            val.type is Type.REFPTR &&
            valIsLayout(val.word, LAYOUT_CLOS)
        );

        funArg.fun = getClosFun(val.word.ptrVal);

        assert (
            funArg.fun.ast.usesClos == 0,
            "primitive function uses its closure argument: " ~
            to!string(strArg.str)
        );
    }

    auto argCount = cast(uint32_t)instr.numArgs - 2;

    // Allocate temporary storage for the argument values
    if (argCount > interp.tempVals.length)
        interp.tempVals.length = argCount;
    auto argVals = interp.tempVals.ptr;

    // Fetch the argument values
    for (size_t i = 0; i < argCount; ++i)
        argVals[i] = interp.getArgVal(instr, 2 + i);

    // Call the function with null closure and this values
    interp.callFun(
        funArg.fun,
        instr,
        NULL.ptrVal,
        NULL,
        Type.REFPTR,
        argCount,
        argVals
    );
}
*/

/*
extern (C) void op_ret(Interp interp, IRInstr instr)
{
    //writefln("ret from %s", instr.block.fun.getName);

    auto raSlot    = instr.block.fun.raVal.outSlot;
    auto argcSlot  = instr.block.fun.argcVal.outSlot;
    auto numParams = instr.block.fun.numParams;
    auto numLocals = instr.block.fun.numLocals;

    // Get the return value
    auto retVal = interp.getArgVal(instr, 0);

    // Get the calling instruction
    auto callInstr = cast(IRInstr)interp.wsp[raSlot].ptrVal;

    // Get the argument count
    auto argCount = interp.wsp[argcSlot].uint32Val;

    // If the call instruction is valid
    if (callInstr !is null)
    {
        //writeln("ret val: ");
        //writeln("  word: ", retVal.word.int64Val);
        //writeln("   i32: ", retVal.word.int32Val);
        //writeln("  type: ", retVal.type);

        // If this is a new call and the return value is undefined
        if (callInstr.opcode == &CALL_NEW && (retVal.type == Type.CONST && retVal.word == UNDEF))
        {
            // Use the this value as the return value
            retVal = interp.getSlot(instr.block.fun.thisVal.outSlot);
        }

        // Compute the actual number of extra arguments to pop
        size_t extraArgs = (argCount > numParams)? (argCount - numParams):0;

        //writefln("argCount: %s", argCount);
        //writefln("popping %s", numLocals + extraArgs);

        // Pop all local stack slots and arguments
        interp.pop(numLocals + extraArgs);

        // Leave the return value in the call instruction's output slot
        interp.setSlot(
            callInstr.outSlot,
            retVal
        );

        // Set the instruction pointer to the call continuation instruction
        interp.branch(callInstr.getTarget(0));
    }
    else
    {
        // Pop all local stack slots
        interp.pop(numLocals);

        // Terminate the execution
        interp.jump(null);

        // Leave the return value on top of the stack
        interp.push(retVal);
    }
}
*/

/*
extern (C) void op_throw(Interp interp, IRInstr instr)
{
    // Get the exception value
    auto excVal = interp.getArgVal(instr, 0);

    // Throw the exception
    throwExc(interp, instr, excVal);
}
*/

extern (C) void op_heap_alloc(Interp interp, IRInstr instr)
{
    auto allocSize = interp.getArgUint32(instr, 0);

    auto ptr = heapAlloc(interp, allocSize);

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(ptr),
        Type.REFPTR
    );
}

extern (C) void op_gc_collect(Interp interp, IRInstr instr)
{
    auto heapSize = interp.getArgUint32(instr, 0);

    writeln("triggering gc");

    gcCollect(interp, heapSize);
}

extern (C) void op_make_link(Interp interp, IRInstr instr)
{
    auto linkArg = cast(IRLinkIdx)instr.getArg(0);
    assert (linkArg !is null);
    auto linkIdx = &linkArg.linkIdx;

    if (*linkIdx is NULL_LINK)
    {
        *linkIdx = interp.allocLink();

        interp.setLinkWord(*linkIdx, NULL);
        interp.setLinkType(*linkIdx, Type.REFPTR);
    }

    interp.setSlot(
        instr.outSlot,
        Word.uint32v(*linkIdx),
        Type.INT32
    );
}

extern (C) void op_set_link(Interp interp, IRInstr instr)
{
    auto linkIdx = interp.getArgUint32(instr, 0);

    auto val = interp.getArgVal(instr, 1);

    interp.setLinkWord(linkIdx, val.word);
    interp.setLinkType(linkIdx, val.type);
}

extern (C) void op_get_link(Interp interp, IRInstr instr)
{
    auto linkIdx = interp.getArgUint32(instr, 0);

    auto wVal = interp.getLinkWord(linkIdx);
    auto tVal = interp.getLinkType(linkIdx);

    interp.setSlot(
        instr.outSlot,
        wVal,
        tVal
    );
}

extern (C) void op_make_map(Interp interp, IRInstr instr)
{
    auto mapArg = cast(IRMapPtr)instr.getArg(0);
    assert (mapArg !is null);

    if (mapArg.map is null)
    {
        // Minimum number of properties to allocate
        auto minNumProps = interp.getArgUint32(instr, 1);

        // Allocate the map
        mapArg.map = new ObjMap(interp, minNumProps);
    }

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(cast(rawptr)mapArg.map),
        Type.MAPPTR
    );
}

extern (C) void op_map_num_props(Interp interp, IRInstr instr)
{
    // Get the map value
    auto mapArg = interp.getArgVal(instr, 0);
    assert (mapArg.type is Type.MAPPTR);
    auto map = mapArg.word.mapVal;
    assert (map !is null);

    // Get the number of properties to allocate
    auto numProps = map.numProps;

    interp.setSlot(
        instr.outSlot,
        Word.uint32v(numProps),
        Type.INT32
    );
}

extern (C) void op_map_prop_idx(Interp interp, IRInstr instr)
{
    // Get the map value
    auto mapArg = interp.getArgVal(instr, 0);
    assert (mapArg.type is Type.MAPPTR);
    auto map = mapArg.word.mapVal;
    assert (map !is null, "map is null");

    // Get the string value
    auto strVal = interp.getArgStr(instr, 1);

    // Get the allocField flag
    auto allocField = interp.getArgBool(instr, 2);

    // Lookup the property index
    auto propIdx = map.getPropIdx(strVal, allocField);

    // If the property was not found
    if (propIdx is uint32.max)
    {
        // Output the boolean false
        interp.setSlot(
            instr.outSlot,
            FALSE,
            Type.CONST
        );
    }
    else
    {
        // Output the property index
        interp.setSlot(
            instr.outSlot,
            Word.uint32v(propIdx),
            Type.INT32
        );
    }
}

extern (C) void op_map_prop_name(Interp interp, IRInstr instr)
{
    // Get the map value
    auto mapArg = interp.getArgVal(instr, 0);
    auto map = mapArg.word.mapVal;

    // Get the index value
    auto idxArg = interp.getArgUint32(instr, 1);

    // Get the property name
    auto propName = map.getPropName(idxArg);

    if (propName is null)
    {
        interp.setSlot(
            instr.outSlot,
            NULL,
            Type.REFPTR
        );
    }
    else
    {
        auto propStr = getString(interp, propName);

        interp.setSlot(
            instr.outSlot,
            Word.ptrv(propStr),
            Type.REFPTR
        );
    }
}

extern (C) void op_get_str(Interp interp, IRInstr instr)
{
    auto strPtr = interp.getArgStr(instr, 0);

    // Compute and set the hash code for the string
    auto hashCode = compStrHash(strPtr);
    str_set_hash(strPtr, hashCode);

    // Find the corresponding string in the string table
    strPtr = getTableStr(interp, strPtr);

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(strPtr),
        Type.REFPTR
    );
}

/// Get the value of a global variable
extern (C) void op_get_global(Interp interp, IRInstr instr)
{
    // Name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Cached property index
    auto idxArg = cast(IRCachedIdx)instr.getArg(1);
    assert (idxArg !is null);
    auto propIdx = idxArg.idx;

    // If a property index was cached
    if (propIdx !is idxArg.idx.max)
    {
        auto wVal = obj_get_word(interp.globalObj, propIdx);
        auto tVal = obj_get_type(interp.globalObj, propIdx);

        interp.setSlot(
            instr.outSlot,
            Word.uint64v(wVal),
            cast(Type)tVal
        );

        return;
    }

    auto propStr = GCRoot(interp, getString(interp, nameStr));

    // Lookup the property index in the class
    auto globalMap = cast(ObjMap)obj_get_map(interp.globalObj);
    assert (globalMap !is null);
    propIdx = globalMap.getPropIdx(propStr.ptr);

    // If the property was found, cache it
    if (propIdx != uint32.max)
    {
        // Cache the property index
        idxArg.idx = propIdx;
    }

    // Lookup the property
    ValuePair val = getProp(
        interp,
        interp.globalObj,
        propStr.ptr
    );

    // If the property is not defined
    if (val.type == Type.CONST && val.word == MISSING)
    {
        return throwError(
            interp,
            instr, 
            "ReferenceError", "global property \"" ~ 
            to!string(nameStr) ~ "\" is not defined"
        );
    }

    interp.setSlot(
        instr.outSlot,
        val
    );
}

/// Set the value of a global variable
extern (C) void op_set_global(Interp interp, IRInstr instr)
{
    // Name string (D string)
    auto strArg = cast(IRString)instr.getArg(0);
    assert (strArg !is null);
    auto nameStr = strArg.str;

    // Get the property value argument
    auto propVal = interp.getArgVal(instr, 1);

    // Cached property index
    auto idxArg = cast(IRCachedIdx)instr.getArg(2);
    assert (idxArg !is null);
    auto propIdx = idxArg.idx;

    // If a property index was cached
    if (propIdx !is idxArg.idx.max)
    {
        obj_set_word(interp.globalObj, cast(uint32)propIdx, propVal.word.uint64Val);
        obj_set_type(interp.globalObj, cast(uint32)propIdx, propVal.type);

        return;
    }

    // Save the value in a GC root
    auto val = GCRoot(interp, propVal);

    // Get the property string
    auto propStr = GCRoot(interp, getString(interp, nameStr));

    // Set the property value
    setProp(
        interp,
        interp.globalObj,
        propStr.ptr,
        val.pair
    );

    // Lookup the property index in the class
    auto globalMap = cast(ObjMap)obj_get_map(interp.globalObj);
    assert (globalMap !is null);
    propIdx = globalMap.getPropIdx(propStr.ptr);

    // If the property was found, cache it
    if (propIdx != uint32.max)
    {
        // Cache the property index
        idxArg.idx = propIdx;
    }
}

extern (C) void op_new_clos(Interp interp, IRInstr instr)
{
    //writefln("entering newclos");

    auto funArg = cast(IRFunPtr)instr.getArg(0);
    assert (funArg !is null);
    auto fun = funArg.fun;

    // Closure map
    auto closMapArg = interp.getArgVal(instr, 1);

    // Prototype map
    auto protMapArg = interp.getArgVal(instr, 2);

    //writeln("clos map numProps: ", closMapArg.word.mapVal.numProps);

    // Allocate the closure object
    auto closPtr = GCRoot(
        interp,
        newClos(
            interp, 
            closMapArg.word.mapVal,
            interp.funProto,
            cast(uint32)fun.ast.captVars.length,
            fun
        )
    );

    // Allocate the prototype object
    auto objPtr = GCRoot(
        interp,
        newObj(
            interp, 
            protMapArg.word.mapVal, 
            interp.objProto
        )
    );

    // Set the "prototype" property on the closure object
    auto protoStr = GCRoot(interp, getString(interp, "prototype"));
    setProp(
        interp,
        closPtr.ptr,
        protoStr.ptr,
        objPtr.pair
    );

    assert (
        clos_get_next(closPtr.ptr) == null,
        "closure next pointer is not null"
    );

    //writeln("final clos ptr: ", closPtr.ptr);

    // Output a pointer to the closure
    interp.setSlot(
        instr.outSlot,
        closPtr.word,
        Type.REFPTR
    );

    //writefln("leaving newclos");
}

extern (C) void op_load_file(Interp interp, IRInstr instr)
{
    auto strPtr = interp.getArgStr(instr, 0);
    auto fileName = interp.getLoadPath(extractStr(strPtr));

    try
    {
        // Parse the source file and generate IR
        auto ast = parseFile(fileName);
        auto fun = astToIR(ast);

        // Register this function in the function reference set
        interp.funRefs[cast(void*)fun] = fun;

        // Setup the callee stack frame
        interp.callFun(
            fun,
            instr,      // Calling instruction
            null,       // Null closure argument
            NULL,       // Null this argument
            Type.REFPTR,// This value is a reference
            0,          // 0 arguments
            null        // 0 arguments
        );
    }

    catch (Exception err)
    {
        throwError(interp, instr, "RuntimeError", err.msg);
    }
}

extern (C) void op_eval_str(Interp interp, IRInstr instr)
{
    auto strPtr = interp.getArgStr(instr, 0);
    auto codeStr = extractStr(strPtr);

    // Parse the source file and generate IR
    auto ast = parseString(codeStr, "eval_str");
    auto fun = astToIR(ast);

    // Register this function in the function reference set
    interp.funRefs[cast(void*)fun] = fun;

    // Setup the callee stack frame
    interp.callFun(
        fun,
        instr,      // Calling instruction
        null,       // Null closure argument
        NULL,       // Null this argument
        Type.REFPTR,// This value is a reference
        0,          // 0 arguments
        null        // 0 arguments
    );
}

extern (C) void op_print_str(Interp interp, IRInstr instr)
{
    auto strPtr = interp.getArgStr(instr, 0);
    auto str = extractStr(strPtr);

    // Print the string to standard output
    write(str);
}

extern (C) void op_get_ast_str(Interp interp, IRInstr instr)
{
    auto funArg = interp.getArgVal(instr, 0);

    assert (
        funArg.type == Type.REFPTR && valIsLayout(funArg.word, LAYOUT_CLOS),
        "invalid closure object"
    );

    auto fun = getClosFun(funArg.word.ptrVal);

    auto str = fun.ast.toString();
    auto strObj = getString(interp, to!wstring(str));
   
    interp.setSlot(
        instr.outSlot,
        Word.ptrv(strObj),
        Type.REFPTR
    );
}

extern (C) void op_get_ir_str(Interp interp, IRInstr instr)
{
    auto funArg = interp.getArgVal(instr, 0);

    assert (
        funArg.type == Type.REFPTR && valIsLayout(funArg.word, LAYOUT_CLOS),
        "invalid closure object"
    );

    auto fun = getClosFun(funArg.word.ptrVal);

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
        astToIR(fun.ast, fun);

    auto str = fun.toString();
    auto strObj = getString(interp, to!wstring(str));

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(strObj),
        Type.REFPTR
    );
}

extern (C) void op_f64_to_str(Interp interp, IRInstr instr)
{
    auto argVal = interp.getArgVal(instr, 0);

    assert (
        argVal.type == Type.FLOAT64,
        "invalid float value"
    );

    auto str = format("%G", argVal.word.floatVal);
    auto strObj = getString(interp, to!wstring(str));

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(strObj),
        Type.REFPTR
    );
}

extern (C) void op_f64_to_str_lng(Interp interp, IRInstr instr)
{
    auto argVal = interp.getArgVal(instr, 0);

    assert (
        argVal.type == Type.FLOAT64,
        "invalid float value"
    );

    enum fmt = format("%%.%df", float64.dig);
    auto str = format(fmt, argVal.word.floatVal);
    auto strObj = getString(interp, to!wstring(str));

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(strObj),
        Type.REFPTR
    );
}

extern (C) void op_get_time_ms(Interp interp, IRInstr instr)
{
    auto msecs = Clock.currAppTick().msecs();

    interp.setSlot(
        instr.outSlot,
        Word.uint32v(cast(uint32)msecs),
        Type.INT32
    );
}

extern (C) void op_load_lib(Interp interp, IRInstr instr)
{
    // Library to load (JS string)
    auto strPtr = interp.getArgStr(instr, 0);

    // Library to load (D string)
    auto libname = extractStr(strPtr);

    // String must be null terminated
    libname ~= '\0';

    auto lib = dlopen(libname.ptr, RTLD_LAZY | RTLD_LOCAL);

    if (lib is null)
        return throwError(interp, instr, "RuntimeError", to!string(dlerror()));

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(cast(rawptr)lib),
        Type.RAWPTR
    );
}

extern (C) void op_close_lib(Interp interp, IRInstr instr)
{
    auto libArg = interp.getArgVal(instr, 0);

    assert (
        libArg.type == Type.RAWPTR,
        "invalid rawptr value"
    );

    if (dlclose(libArg.word.ptrVal) != 0)
         return throwError(interp, instr, "RuntimeError", "could not close lib.");
}

extern (C) void op_get_sym(Interp interp, IRInstr instr)
{
    auto libArg = interp.getArgVal(instr, 0);

    assert (
        libArg.type == Type.RAWPTR,
        "invalid rawptr value"
    );

    // Symbol name (D string)
    auto strArg = cast(IRString)instr.getArg(1);
    assert (strArg !is null);   
    auto symname = to!string(strArg.str);

    // String must be null terminated
    symname ~= '\0';

    auto sym = dlsym(libArg.word.ptrVal, symname.ptr);

    if (sym is null)
        return throwError(interp, instr, "RuntimeError", to!string(dlerror()));

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(cast(rawptr)sym),
        Type.RAWPTR
    );
}

