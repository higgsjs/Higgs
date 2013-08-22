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
import jit.codeblock;

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

void throwError(
    Interp interp,
    IRInstr instr,
    string ctorName, 
    string errMsg
)
{
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
                    null, 
                    errProto.ptr,
                    CLASS_INIT_SIZE,
                    CLASS_INIT_SIZE
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

    //writefln("setting str %s", instr.args[0].stringVal);

    interp.setSlot(
        instr.outSlot,
        interp.getLinkWord(*linkIdx),
        Type.REFPTR
    );
}

extern (C) void op_set_true(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        TRUE,
        Type.CONST
    );
}

extern (C) void op_make_value(Interp interp, IRInstr instr)
{
    auto word = interp.getArgVal(instr, 0).word;
    auto typeVal = interp.getArgVal(instr, 1);

    assert (
        typeVal.type == Type.INT32,
        "type should be int32"
    );

    auto type = cast(Type)typeVal.word.uint8Val;

    assert (
        type >= Type.min && type <= Type.max,
        "type value out of range: " ~ to!string(type)
    );

    interp.setSlot(
        instr.outSlot,
        word,
        type
    );
}

extern (C) void op_get_word(Interp interp, IRInstr instr)
{
    auto word = interp.getArgVal(instr, 0).word;

    interp.setSlot(
        instr.outSlot,
        word,
        Type.INT32
    );
}

extern (C) void op_get_type(Interp interp, IRInstr instr)
{
    auto type = interp.getArgVal(instr, 0).type;

    interp.setSlot(
        instr.outSlot,
        Word.uint32v(cast(uint8)type),
        Type.INT32
    );
}

extern (C) void TypeCheckOp(Type type)(Interp interp, IRInstr instr)
{
    auto typeTag = interp.getArgVal(instr, 0).type;

    interp.setSlot(
        instr.outSlot,
        (typeTag == type)? TRUE:FALSE,
        Type.CONST
    );
}

alias TypeCheckOp!(Type.INT32) op_is_i32;
alias TypeCheckOp!(Type.INT64) op_is_i64;
alias TypeCheckOp!(Type.FLOAT64) op_is_f64;
alias TypeCheckOp!(Type.REFPTR) op_is_refptr;
alias TypeCheckOp!(Type.RAWPTR) op_is_rawptr;
alias TypeCheckOp!(Type.CONST) op_is_const;

extern (C) void op_i32_to_f64(Interp interp, IRInstr instr)
{
    auto w0 = interp.getArgVal(instr, 0).word;

    interp.setSlot(
        instr.outSlot,
        Word.float64v(w0.int32Val),
        Type.FLOAT64
    );
}

extern (C) void op_f64_to_i32(Interp interp, IRInstr instr)
{
    auto w0 = interp.getArgVal(instr, 0).word;

    // Convert based on the ECMAScript toInt32 specs (see section 9.5)
    auto intVal = cast(int32)cast(int64)w0.floatVal;

    interp.setSlot(
        instr.outSlot,
        Word.int32v(intVal),
        Type.INT32
    );
}

extern (C) void ArithOp(Type typeTag, uint arity, string op)(Interp interp, IRInstr instr)
{
    static assert (
        typeTag == Type.INT32 || typeTag == Type.FLOAT64
    );

    static assert (
        arity <= 2
    );

    static if (arity > 0)
    {
        auto vX = interp.getArgVal(instr, 0);

        assert (
            vX.type == typeTag,
            "invalid operand 1 type in op \"" ~ op ~ "\" (" ~ typeToString(typeTag) ~ ")"
        );
    }
    static if (arity > 1)
    {
        auto vY = interp.getArgVal(instr, 1);

        assert (
            vY.type == typeTag,
            "invalid operand 2 type in op \"" ~ op ~ "\" (" ~ typeToString(typeTag) ~ ")"
        );
    }

    Word output;

    static if (typeTag == Type.INT32)
    {
        static if (arity > 0)
            auto x = vX.word.int32Val;
        static if (arity > 1)
            auto y = vY.word.int32Val;
    }
    static if (typeTag == Type.FLOAT64)
    {
        static if (arity > 0)
            auto x = vX.word.floatVal;
        static if (arity > 1)
            auto y = vY.word.floatVal;
    }

    mixin(op);

    static if (typeTag == Type.INT32)
        output.int32Val = r;
    static if (typeTag == Type.FLOAT64)
        output.floatVal = r;

    interp.setSlot(
        instr.outSlot,
        output,
        typeTag
    );
}

alias ArithOp!(Type.INT32, 2, "auto r = x + y;") op_add_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x - y;") op_sub_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x * y;") op_mul_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x / y;") op_div_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x % y;") op_mod_i32;

alias ArithOp!(Type.INT32, 2, "auto r = x & y;") op_and_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x | y;") op_or_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x ^ y;") op_xor_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x << y;") op_lsft_i32;
alias ArithOp!(Type.INT32, 2, "auto r = x >> y;") op_rsft_i32;
alias ArithOp!(Type.INT32, 2, "auto r = cast(uint32)x >>> y;") op_ursft_i32;
alias ArithOp!(Type.INT32, 1, "auto r = ~x;") op_not_i32;

alias ArithOp!(Type.FLOAT64, 2, "auto r = x + y;") op_add_f64;
alias ArithOp!(Type.FLOAT64, 2, "auto r = x - y;") op_sub_f64;
alias ArithOp!(Type.FLOAT64, 2, "auto r = x * y;") op_mul_f64;
alias ArithOp!(Type.FLOAT64, 2, "auto r = x / y;") op_div_f64;
alias ArithOp!(Type.FLOAT64, 2, "auto r = fmod(x, y);") op_mod_f64;

alias ArithOp!(Type.FLOAT64, 1, "auto r = sin(x);") op_sin_f64;
alias ArithOp!(Type.FLOAT64, 1, "auto r = cos(x);") op_cos_f64;
alias ArithOp!(Type.FLOAT64, 1, "auto r = sqrt(x);") op_sqrt_f64;
alias ArithOp!(Type.FLOAT64, 1, "auto r = log(x);") op_log_f64;
alias ArithOp!(Type.FLOAT64, 1, "auto r = exp(x);") op_exp_f64;
alias ArithOp!(Type.FLOAT64, 2, "auto r = pow(x, y);") op_pow_f64;

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

extern (C) void ArithOpOvf(Type typeTag, string op)(Interp interp, IRInstr instr)
{
    auto vX = interp.getArgVal(instr, 0);
    auto vY = interp.getArgVal(instr, 1);

    assert (
        vX.type == Type.INT32 && vY.type == Type.INT32,
        "invalid operand types in ovf op \"" ~ op ~ "\" (" ~ typeToString(typeTag) ~ ")"
    );

    auto x = cast(int64)vX.word.int32Val;
    auto y = cast(int64)vY.word.int32Val;

    mixin(op);

    if (r >= int32.min && r <= int32.max)
    {
        interp.setSlot(
            instr.outSlot,
            Word.int32v(cast(int32)r),
            Type.INT32
        );

        interp.branch(instr.getTarget(0));
    }
    else
    {
        interp.branch(instr.getTarget(1));
    }
}

alias ArithOpOvf!(Type.INT32, "auto r = x + y;") op_add_i32_ovf;
alias ArithOpOvf!(Type.INT32, "auto r = x - y;") op_sub_i32_ovf;
alias ArithOpOvf!(Type.INT32, "auto r = x * y;") op_mul_i32_ovf;
alias ArithOpOvf!(Type.INT32, "auto r = x << y;") op_lsft_i32_ovf;

extern (C) void CompareOp(DataType, Type typeTag, string op)(Interp interp, IRInstr instr)
{
    auto vX = interp.getArgVal(instr, 0);
    auto vY = interp.getArgVal(instr, 1);

    assert (
        vX.type == typeTag && vY.type == typeTag,
        "invalid operand types in op \"" ~ op ~ "\" (" ~ DataType.stringof ~ ")"
    );

    // Boolean result
    bool r;

    static if (typeTag == Type.CONST)
    {
        auto x = cast(DataType)vX.word.int8Val;
        auto y = cast(DataType)vY.word.int8Val;
    }
    static if (typeTag == Type.INT32)
    {
        auto x = cast(DataType)vX.word.int32Val;
        auto y = cast(DataType)vY.word.int32Val;
    }
    static if (typeTag == Type.REFPTR || typeTag == Type.RAWPTR)
    {
        auto x = cast(DataType)vX.word.ptrVal;
        auto y = cast(DataType)vY.word.ptrVal;
    }
    static if (typeTag == Type.FLOAT64)
    {
        auto x = cast(DataType)vX.word.floatVal;
        auto y = cast(DataType)vY.word.floatVal;
    }

    mixin(op);        

    interp.setSlot(
        instr.outSlot,
        r? TRUE:FALSE,
        Type.CONST
    );
}

alias CompareOp!(int32, Type.INT32, "r = (x == y);") op_eq_i32;
alias CompareOp!(int32, Type.INT32, "r = (x != y);") op_ne_i32;
alias CompareOp!(int32, Type.INT32, "r = (x < y);") op_lt_i32;
alias CompareOp!(int32, Type.INT32, "r = (x > y);") op_gt_i32;
alias CompareOp!(int32, Type.INT32, "r = (x <= y);") op_le_i32;
alias CompareOp!(int32, Type.INT32, "r = (x >= y);") op_ge_i32;
alias CompareOp!(int8, Type.INT32, "r = (x == y);") op_eq_i8;

alias CompareOp!(refptr, Type.REFPTR, "r = (x == y);") op_eq_refptr;
alias CompareOp!(refptr, Type.REFPTR, "r = (x != y);") op_ne_refptr;

alias CompareOp!(rawptr, Type.RAWPTR, "r = (x == y);") op_eq_rawptr;
alias CompareOp!(rawptr, Type.RAWPTR, "r = (x != y);") op_ne_rawptr;

alias CompareOp!(int8, Type.CONST, "r = (x == y);") op_eq_const;
alias CompareOp!(int8, Type.CONST, "r = (x != y);") op_ne_const;

alias CompareOp!(float64, Type.FLOAT64, "r = (x == y);") op_eq_f64;
alias CompareOp!(float64, Type.FLOAT64, "r = (x != y);") op_ne_f64;
alias CompareOp!(float64, Type.FLOAT64, "r = (x < y);") op_lt_f64;
alias CompareOp!(float64, Type.FLOAT64, "r = (x > y);") op_gt_f64;
alias CompareOp!(float64, Type.FLOAT64, "r = (x <= y);") op_le_f64;
alias CompareOp!(float64, Type.FLOAT64, "r = (x >= y);") op_ge_f64;

extern (C) void LoadOp(DataType, Type typeTag)(Interp interp, IRInstr instr)
{
    auto vPtr = interp.getArgVal(instr, 0);
    auto vOfs = interp.getArgVal(instr, 1);

    assert (
        vPtr.type is Type.REFPTR || vPtr.type is Type.RAWPTR,
        "pointer is not pointer type in load op:\n" ~
        instr.toString()
    );

    assert (
        vOfs.type is Type.INT32,
        "offset is not integer type in load op"
    );

    auto ptr = vPtr.word.ptrVal;
    auto ofs = vOfs.word.int32Val;

    assert (
        vPtr.type is Type.RAWPTR || interp.inFromSpace(ptr),
        "ref ptr not in from space in load op:\n" ~
        to!string(vPtr.word.ptrVal) ~
       "\nin function:\n" ~
        instr.block.fun.getName
    );

    auto val = *cast(DataType*)(ptr + ofs);

    Word word;

    static if (
        DataType.stringof == "byte"  ||
        DataType.stringof == "short" ||
        DataType.stringof == "int")
        word.int32Val = val;

    static if (DataType.stringof == "long")
        word.int64Val = val;

    static if (
        DataType.stringof == "ubyte"  ||
        DataType.stringof == "ushort" ||
        DataType.stringof == "uint")
        word.uint32Val = val;

    static if (DataType.stringof == "ulong")
        word.uint64Val = val;

    static if (DataType.stringof == "double")
        word.floatVal = val;

    static if (
        DataType.stringof == "void*" ||
        DataType.stringof == "ubyte*" ||
        DataType.stringof == "IRFunction")
        word.ptrVal = cast(refptr)val;

    interp.setSlot(
        instr.outSlot,
        word,
        typeTag
    );
}

extern (C) void StoreOp(DataType, Type typeTag)(Interp interp, IRInstr instr)
{
    auto vPtr = interp.getArgVal(instr, 0);
    auto vOfs = interp.getArgVal(instr, 1);

    auto ptr = vPtr.word.ptrVal;
    auto ofs = vOfs.word.int32Val;

    auto val = interp.getArgVal(instr, 2);

    assert (
        vPtr.type is Type.REFPTR || vPtr.type is Type.RAWPTR,
        "pointer is not pointer type in store op:\n" ~
        valToString(vPtr) ~
        "\nin function:\n" ~
        instr.block.fun.getName
    );

    assert (
        vPtr.type is Type.RAWPTR || interp.inFromSpace(ptr),
        "ref ptr not in from space in store op:\n" ~
        to!string(vPtr.word.ptrVal)
    );

    assert (
        vOfs.type == Type.INT32,
        "offset is not integer type in store op"
    );

    assert (
        val.type !is Type.REFPTR || 
        val.word.ptrVal is null ||
        interp.inFromSpace(val.word.ptrVal),
        "ref value stored not in from space: " ~ 
        to!string(val.word.ptrVal)
    );

    DataType storeVal;

    static if (
        DataType.stringof == "byte"  ||
        DataType.stringof == "short" ||
        DataType.stringof == "int")
        storeVal = cast(DataType)val.word.int32Val;

    static if (DataType.stringof == "long")
        storeVal = cast(DataType)val.word.int64Val;

    static if (
        DataType.stringof == "ubyte"  ||
        DataType.stringof == "ushort" ||
        DataType.stringof == "uint")
        storeVal = cast(DataType)val.word.uint32Val;

    static if (DataType.stringof == "ulong")
        storeVal = cast(DataType)val.word.uint64Val;

    static if (DataType.stringof == "double")
        storeVal = cast(DataType)val.word.floatVal;

    static if (
        DataType.stringof == "void*" ||
        DataType.stringof == "ubyte*" ||
        DataType.stringof == "IRFunction")
        storeVal = cast(DataType)val.word.ptrVal;

    *cast(DataType*)(ptr + ofs) = storeVal;
}

alias LoadOp!(uint8, Type.INT32) op_load_u8;
alias LoadOp!(uint16, Type.INT32) op_load_u16;
alias LoadOp!(uint32, Type.INT32) op_load_u32;
alias LoadOp!(uint64, Type.INT64) op_load_u64;
alias LoadOp!(float64, Type.FLOAT64) op_load_f64;
alias LoadOp!(refptr, Type.REFPTR) op_load_refptr;
alias LoadOp!(rawptr, Type.RAWPTR) op_load_rawptr;
alias LoadOp!(IRFunction, Type.FUNPTR) op_load_funptr;
alias StoreOp!(uint8, Type.INT32) op_store_u8;
alias StoreOp!(uint16, Type.INT32) op_store_u16;
alias StoreOp!(uint32, Type.INT32) op_store_u32;
alias StoreOp!(uint64, Type.INT64) op_store_u64;
alias StoreOp!(float64, Type.FLOAT64) op_store_f64;
alias StoreOp!(refptr, Type.REFPTR) op_store_refptr;
alias StoreOp!(rawptr, Type.RAWPTR) op_store_rawptr;
alias StoreOp!(IRFunction, Type.FUNPTR) op_store_funptr;

extern (C) void op_jump(Interp interp, IRInstr instr)
{
    interp.branch(instr.getTarget(0));
}

extern (C) void op_if_true(Interp interp, IRInstr instr)
{
    auto v0 = interp.getArgVal(instr, 0);

    assert (
        v0.type == Type.CONST,
        "input to if_true is not constant type:\n" ~
        instr.block.toString()
    );

    if (v0.word.int8Val == TRUE.int8Val)
        interp.branch(instr.getTarget(0));
    else
        interp.branch(instr.getTarget(1));
}

extern (C) void op_call(Interp interp, IRInstr instr)
{
    auto closVal = interp.getArgVal(instr, 0);
    auto thisVal = interp.getArgVal(instr, 1);

    if (closVal.type != Type.REFPTR || !valIsLayout(closVal.word, LAYOUT_CLOS))
        return throwError(interp, instr, "TypeError", "call to non-function");

    // Get the function object from the closure
    auto closPtr = closVal.word.ptrVal;
    auto fun = getClosFun(closPtr);

    /*
    write(core.memory.GC.addrOf(cast(void*)fun));
    write("\n");
    */

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

    // Allocate the "this" object
    auto thisObj = GCRoot(
        interp,
        newObj(
            interp, 
            clos_get_ctor_class(clos.ptr),
            protoObj.ptr,
            CLASS_INIT_SIZE,
            2
        )
    );
    clos_set_ctor_class(clos.ptr, obj_get_class(thisObj.ptr));

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
        /*        
        writeln("ret val: ");
        writeln("  word: ", retVal.word.int64Val);
        //writeln("   i32: ", retVal.word.int32Val);
        writeln("  type: ", retVal.type);
        */

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

extern (C) void op_throw(Interp interp, IRInstr instr)
{
    // Get the exception value
    auto excVal = interp.getArgVal(instr, 0);

    // Throw the exception
    throwExc(interp, instr, excVal);
}

extern (C) void op_get_arg(Interp interp, IRInstr instr)
{
    // Get the first argument slot
    auto argSlot = instr.block.fun.argcVal.outSlot + 1;

    // Get the argument index
    auto idx = interp.getArgUint32(instr, 0);

    // Get the argument value
    auto argVal = interp.getSlot(argSlot + idx);

    interp.setSlot(
        instr.outSlot,
        argVal
    );
}

/// Templated interpreter value access operation
extern (C) void GetValOp(Type typeTag, string op)(Interp interp, IRInstr instr)
{
    static assert (
        typeTag == Type.INT32 || typeTag == Type.REFPTR
    );

    mixin(op);

    Word output;

    static if (typeTag == Type.INT32)
        output.int32Val = r;
    static if (typeTag == Type.REFPTR)
        output.ptrVal = r;

    interp.setSlot(
        instr.outSlot,
        output,
        typeTag
    );
}

alias GetValOp!(Type.REFPTR, "auto r = interp.objProto;") op_get_obj_proto;
alias GetValOp!(Type.REFPTR, "auto r = interp.arrProto;") op_get_arr_proto;
alias GetValOp!(Type.REFPTR, "auto r = interp.funProto;") op_get_fun_proto;
alias GetValOp!(Type.REFPTR, "auto r = interp.globalObj;") op_get_global_obj;
alias GetValOp!(Type.INT32, "auto r = cast(int32)interp.heapSize;") op_get_heap_size;
alias GetValOp!(Type.INT32, "auto r = cast(int32)(interp.heapLimit - interp.allocPtr);") op_get_heap_free;
alias GetValOp!(Type.INT32, "auto r = cast(int32)interp.gcCount;") op_get_gc_count;

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
    propIdx = getPropIdx(interp, obj_get_class(interp.globalObj), propStr.ptr);

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
    propIdx = getPropIdx(interp, obj_get_class(interp.globalObj), propStr.ptr);

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

    auto closLinkArg = cast(IRLinkIdx)instr.getArg(1);
    assert (closLinkArg !is null);
    auto closLinkIdx = &closLinkArg.linkIdx;

    auto protLinkArg = cast(IRLinkIdx)instr.getArg(2);
    assert (protLinkArg !is null);
    auto protLinkIdx = &protLinkArg.linkIdx;

    if (*closLinkIdx is NULL_LINK)
    {
        *closLinkIdx = interp.allocLink();
        interp.setLinkWord(*closLinkIdx, NULL);
        interp.setLinkType(*closLinkIdx, Type.REFPTR);
    }

    if (*protLinkIdx is NULL_LINK)
    {
        *protLinkIdx = interp.allocLink();
        interp.setLinkWord(*protLinkIdx, NULL);
        interp.setLinkType(*protLinkIdx, Type.REFPTR);
    }

    //writefln("allocating clos");

    // Allocate the closure object
    auto closPtr = GCRoot(
        interp,
        newClos(
            interp, 
            interp.wLinkTable[*closLinkIdx].ptrVal,
            interp.funProto,
            CLASS_INIT_SIZE,
            2,
            cast(uint32)fun.ast.captVars.length,
            fun
        )
    );
    interp.wLinkTable[*closLinkIdx].ptrVal = clos_get_class(closPtr.ptr);

    //writefln("allocating proto");

    // Allocate the prototype object
    auto objPtr = GCRoot(
        interp,
        newObj(
            interp, 
            interp.wLinkTable[*protLinkIdx].ptrVal, 
            interp.objProto,
            CLASS_INIT_SIZE,
            0
        )
    );
    interp.wLinkTable[*protLinkIdx].ptrVal = obj_get_class(objPtr.ptr);

    //writefln("setting proto");

    // Set the prototype property on the closure object
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

extern (C) void op_call_ffi(Interp interp, IRInstr instr)
{
    // Pointer to function to call
    auto funArg = interp.getArgVal(instr, 1);
    assert (
        funArg.type == Type.RAWPTR,
        "invalid rawptr value"
    );

    // Compiled code block argument
    auto cbArg = cast(IRCodeBlock)instr.getArg(0);
    assert (cbArg !is null);

    // Get the argument count
    auto argCount = instr.numArgs - 3;

    // Check if there is a cached CodeBlock, generate one if not
    if (cbArg.codeBlock is null)
    {
        // Type info (D string)
        auto typeArg = cast(IRString)instr.getArg(2);
        assert (typeArg !is null);
        auto typeinfo = to!string(typeArg.str);
        auto types = split(typeinfo, ",");

        assert (
            argCount == types.length - 1,
            "invalid number of args in ffi call"
        );

        // Compile the call stub
        cbArg.codeBlock = genFFIFn(interp, types, instr.outSlot, argCount);
    }

    // Allocate temporary storage for the argument values
    if (argCount > interp.tempVals.length)
        interp.tempVals.length = argCount;
    auto argVals = interp.tempVals.ptr;

    // Fetch the argument values
    for (size_t i = 0; i < argCount; ++i)
        argVals[i] = interp.getArgVal(instr, 3 + i);

    // Call the call stub passing the function
    // pointer argument array pointers as arguments
    FFIFn callerfun = cast(FFIFn)(cbArg.codeBlock.getAddress());
    callerfun(cast(void*)funArg.word.ptrVal, argVals);

    // Branch to the continuation target of the call_ffi instruction
    interp.branch(instr.getTarget(0));
}

