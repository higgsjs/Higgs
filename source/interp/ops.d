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

/*
extern (C) void op_throw(Interp interp, IRInstr instr)
{
    // Get the exception value
    auto excVal = interp.getArgVal(instr, 0);

    // Throw the exception
    throwExc(interp, instr, excVal);
}
*/

extern (C) void op_gc_collect(Interp interp, IRInstr instr)
{
    auto heapSize = interp.getArgUint32(instr, 0);

    writeln("triggering gc");

    gcCollect(interp, heapSize);
}

/*
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
*/

/*
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
*/

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

        // FIXME
        /*
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
        */
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

    // FIXME
    /*
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
    */
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

