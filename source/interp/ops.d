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

import std.stdio;
import std.algorithm;
import std.string;
import std.conv;
import std.math;
import std.datetime;
import std.stdint;
import core.sys.posix.dlfcn;
import parser.parser;
import ir.ir;
import ir.ast;
import interp.interp;
import interp.layout;
import interp.string;
import interp.object;
import interp.gc;
import interp.ffi;
import jit.codeblock;

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
        if (curInstr.opcode is &CALL && curInstr.excTarget !is null)
        {
            //writefln("found exception target");

            // Set the return value slot to the exception value
            interp.setSlot(
                curInstr.outSlot, 
                excVal
            );

            // Go to the exception target
            interp.jump(curInstr.excTarget);

            // Stop unwinding the stack
            return;
        }

        auto numLocals = curInstr.block.fun.numLocals;
        auto numParams = curInstr.block.fun.params.length;
        auto argcSlot = curInstr.block.fun.argcSlot;
        auto raSlot = curInstr.block.fun.raSlot;

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

extern (C) void op_set_int32(Interp interp, IRInstr instr)
{
    //writefln("interp: %s", cast(int64)cast(void*)interp);
    //writefln(" instr: %s", cast(int64)cast(void*)instr);

    interp.setSlot(
        instr.outSlot,
        Word.int32v(instr.args[0].int32Val),
        Type.INT32
    );
}

extern (C) void op_set_float(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        Word.floatv(instr.args[0].floatVal),
        Type.FLOAT
    );
}

extern (C) void op_set_str(Interp interp, IRInstr instr)
{
    auto linkIdx = instr.args[1].linkIdx;

    if (linkIdx is NULL_LINK)
    {
        linkIdx = interp.allocLink();
        auto strPtr = getString(interp, instr.args[0].stringVal);
        interp.setLinkWord(linkIdx, Word.ptrv(strPtr));
        interp.setLinkType(linkIdx, Type.REFPTR);
        instr.args[1].linkIdx = linkIdx;
    }

    //writefln("setting str %s", instr.args[0].stringVal);

    interp.setSlot(
        instr.outSlot,
        interp.getLinkWord(linkIdx),
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

extern (C) void op_set_false(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        FALSE,
        Type.CONST
    );
}

extern (C) void op_set_null(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        NULL,
        Type.REFPTR
    );
}

extern (C) void op_set_undef(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        UNDEF,
        Type.CONST
    );
}

extern (C) void op_set_missing(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        MISSING,
        Type.CONST
    );
}

extern (C) void op_set_value(Interp interp, IRInstr instr)
{
    auto wWord = interp.getWord(instr.args[0].localIdx);

    auto wType = interp.getWord(instr.args[1].localIdx);
    auto tType = interp.getType(instr.args[1].localIdx);

    assert (
        tType == Type.INT32,
        "type should be integer"
    );

    auto type = cast(Type)wType.uint8Val;

    assert (
        type >= Type.min && type <= Type.max,
        "type value out of range: " ~ to!string(type)
    );

    interp.setSlot(
        instr.outSlot,
        wWord,
        type
    );
}

extern (C) void op_get_word(Interp interp, IRInstr instr)
{
    auto word = interp.getWord(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        word,
        Type.INT32
    );
}

extern (C) void op_get_type(Interp interp, IRInstr instr)
{
    auto type = interp.getType(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        Word.uint32v(cast(uint8)type),
        Type.INT32
    );
}

extern (C) void op_move(Interp interp, IRInstr instr)
{
    interp.move(
        instr.args[0].localIdx,
        instr.outSlot
    );
}

extern (C) void TypeCheckOp(Type type)(Interp interp, IRInstr instr)
{
    auto typeTag = interp.getType(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        (typeTag == type)? TRUE:FALSE,
        Type.CONST
    );
}

alias TypeCheckOp!(Type.INT32) op_is_int32;
alias TypeCheckOp!(Type.FLOAT) op_is_float;
alias TypeCheckOp!(Type.REFPTR) op_is_refptr;
alias TypeCheckOp!(Type.RAWPTR) op_is_rawptr;
alias TypeCheckOp!(Type.CONST) op_is_const;

extern (C) void op_i32_to_f64(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        Word.floatv(w0.int32Val),
        Type.FLOAT
    );
}

extern (C) void op_f64_to_i32(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);

    // Do the conversion according to the ECMAScript
    // toInt32 specs (see section 9.5)
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
        typeTag == Type.INT32 || typeTag == Type.FLOAT
    );

    static assert (
        arity <= 2
    );

    static if (arity > 0)
    {
        auto wX = interp.getWord(instr.args[0].localIdx);
        auto tX = interp.getType(instr.args[0].localIdx);

        assert (
            tX == typeTag,
            "invalid operand 1 type in op \"" ~ op ~ "\" (" ~ typeToString(typeTag) ~ ")"
        );
    }
    static if (arity > 1)
    {
        auto wY = interp.getWord(instr.args[1].localIdx);
        auto tY = interp.getType(instr.args[1].localIdx);

        assert (
            tY == typeTag,
            "invalid operand 2 type in op \"" ~ op ~ "\" (" ~ typeToString(typeTag) ~ ")"
        );
    }

    Word output;

    static if (typeTag == Type.INT32)
    {
        static if (arity > 0)
            auto x = wX.int32Val;
        static if (arity > 1)
            auto y = wY.int32Val;
    }
    static if (typeTag == Type.FLOAT)
    {
        static if (arity > 0)
            auto x = wX.floatVal;
        static if (arity > 1)
            auto y = wY.floatVal;
    }

    mixin(op);

    static if (typeTag == Type.INT32)
        output.int32Val = r;
    static if (typeTag == Type.FLOAT)
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

alias ArithOp!(Type.FLOAT, 2, "auto r = x + y;") op_add_f64;
alias ArithOp!(Type.FLOAT, 2, "auto r = x - y;") op_sub_f64;
alias ArithOp!(Type.FLOAT, 2, "auto r = x * y;") op_mul_f64;
alias ArithOp!(Type.FLOAT, 2, "auto r = x / y;") op_div_f64;
alias ArithOp!(Type.FLOAT, 2, "auto r = fmod(x, y);") op_mod_f64;

alias ArithOp!(Type.FLOAT, 1, "auto r = sin(x);") op_sin_f64;
alias ArithOp!(Type.FLOAT, 1, "auto r = cos(x);") op_cos_f64;
alias ArithOp!(Type.FLOAT, 1, "auto r = sqrt(x);") op_sqrt_f64;
alias ArithOp!(Type.FLOAT, 1, "auto r = log(x);") op_log_f64;
alias ArithOp!(Type.FLOAT, 1, "auto r = exp(x);") op_exp_f64;
alias ArithOp!(Type.FLOAT, 2, "auto r = pow(x, y);") op_pow_f64;

extern (C) void op_floor_f64(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);
    auto t0 = interp.getType(instr.args[0].localIdx);

    assert (t0 == Type.FLOAT, "invalid operand type in floor");

    auto r = floor(w0.floatVal);

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
            Word.floatv(r),
            Type.FLOAT
        );
    }
}

extern (C) void op_ceil_f64(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);
    auto t0 = interp.getType(instr.args[0].localIdx);

    assert (t0 == Type.FLOAT, "invalid operand type in ceil");

    auto r = ceil(w0.floatVal);

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
            Word.floatv(r),
            Type.FLOAT
        );
    }
}

extern (C) void ArithOpOvf(Type typeTag, string op)(Interp interp, IRInstr instr)
{
    auto wX = interp.getWord(instr.args[0].localIdx);
    auto tX = interp.getType(instr.args[0].localIdx);
    auto wY = interp.getWord(instr.args[1].localIdx);
    auto tY = interp.getType(instr.args[1].localIdx);

    assert (
        tX == Type.INT32 && tY == Type.INT32,
        "invalid operand types in ovf op \"" ~ op ~ "\" (" ~ typeToString(typeTag) ~ ")"
    );

    auto x = cast(int64)wX.int32Val;
    auto y = cast(int64)wY.int32Val;

    mixin(op);

    if (r >= int32.min && r <= int32.max)
    {
        interp.setSlot(
            instr.outSlot,
            Word.int32v(cast(int32)r),
            Type.INT32
        );

        interp.jump(instr.target);
    }
    else
    {
        interp.jump(instr.excTarget);
    }
}

alias ArithOpOvf!(Type.INT32, "auto r = x + y;") op_add_i32_ovf;
alias ArithOpOvf!(Type.INT32, "auto r = x - y;") op_sub_i32_ovf;
alias ArithOpOvf!(Type.INT32, "auto r = x * y;") op_mul_i32_ovf;
alias ArithOpOvf!(Type.INT32, "auto r = x << y;") op_lsft_i32_ovf;

extern (C) void CompareOp(DataType, Type typeTag, string op)(Interp interp, IRInstr instr)
{
    auto wX = interp.getWord(instr.args[0].localIdx);
    auto tX = interp.getType(instr.args[0].localIdx);
    auto wY = interp.getWord(instr.args[1].localIdx);
    auto tY = interp.getType(instr.args[1].localIdx);

    assert (
        tX == typeTag && tY == typeTag,
        "invalid operand types in op \"" ~ op ~ "\" (" ~ DataType.stringof ~ ")"
    );

    // Boolean result
    bool r;

    static if (typeTag == Type.CONST)
    {
        auto x = cast(DataType)wX.int8Val;
        auto y = cast(DataType)wY.int8Val;
    }
    static if (typeTag == Type.INT32)
    {
        auto x = cast(DataType)wX.int32Val;
        auto y = cast(DataType)wY.int32Val;
    }
    static if (typeTag == Type.REFPTR || typeTag == Type.RAWPTR)
    {
        auto x = cast(DataType)wX.ptrVal;
        auto y = cast(DataType)wY.ptrVal;
    }
    static if (typeTag == Type.FLOAT)
    {
        auto x = cast(DataType)wX.floatVal;
        auto y = cast(DataType)wY.floatVal;
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

alias CompareOp!(int8, Type.CONST, "r = (x == y);") op_eq_const;
alias CompareOp!(int8, Type.CONST, "r = (x != y);") op_ne_const;

alias CompareOp!(float64, Type.FLOAT, "r = (x == y);") op_eq_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x != y);") op_ne_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x < y);") op_lt_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x > y);") op_gt_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x <= y);") op_le_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x >= y);") op_ge_f64;

extern (C) void LoadOp(DataType, Type typeTag)(Interp interp, IRInstr instr)
{
    auto wPtr = interp.getWord(instr.args[0].localIdx);
    auto tPtr = interp.getType(instr.args[0].localIdx);

    auto wOfs = interp.getWord(instr.args[1].localIdx);
    auto tOfs = interp.getType(instr.args[1].localIdx);

    assert (
        tPtr == Type.REFPTR || tPtr == Type.RAWPTR,
        "pointer is not pointer type in load op"
    );

    assert (
        tOfs == Type.INT32,
        "offset is not integer type in load op"
    );

    auto ptr = wPtr.ptrVal;
    auto ofs = wOfs.int32Val;

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
    auto wPtr = interp.getWord(instr.args[0].localIdx);
    auto tPtr = interp.getType(instr.args[0].localIdx);

    auto wOfs = interp.getWord(instr.args[1].localIdx);
    auto tOfs = interp.getType(instr.args[1].localIdx);

    assert (
        tPtr == Type.REFPTR || tPtr == Type.RAWPTR,
        "pointer is not pointer type in store op"
    );

    assert (
        tOfs == Type.INT32,
        "offset is not integer type in store op"
    );

    auto ptr = wPtr.ptrVal;
    auto ofs = wOfs.int32Val;

    auto word = interp.getWord(instr.args[2].localIdx);

    DataType val;

    static if (
        DataType.stringof == "byte"  ||
        DataType.stringof == "short" ||
        DataType.stringof == "int")
        val = cast(DataType)word.int32Val;

    static if (DataType.stringof == "long")
        val = cast(DataType)word.int64Val;

    static if (
        DataType.stringof == "ubyte"  ||
        DataType.stringof == "ushort" ||
        DataType.stringof == "uint")
        val = cast(DataType)word.uint32Val;

    static if (DataType.stringof == "ulong")
        val = cast(DataType)word.uint64Val;

    static if (DataType.stringof == "double")
        val = cast(DataType)word.floatVal;

    static if (
        DataType.stringof == "void*" ||
        DataType.stringof == "ubyte*" ||
        DataType.stringof == "IRFunction")
        val = cast(DataType)word.ptrVal;

    *cast(DataType*)(ptr + ofs) = val;
}

alias LoadOp!(uint8, Type.INT32) op_load_u8;
alias LoadOp!(uint16, Type.INT32) op_load_u16;
alias LoadOp!(uint32, Type.INT32) op_load_u32;
alias LoadOp!(uint64, Type.INT32) op_load_u64;
alias LoadOp!(float64, Type.FLOAT) op_load_f64;
alias LoadOp!(refptr, Type.REFPTR) op_load_refptr;
alias LoadOp!(rawptr, Type.RAWPTR) op_load_rawptr;
alias LoadOp!(IRFunction, Type.FUNPTR) op_load_funptr;

alias StoreOp!(uint8, Type.INT32) op_store_u8;
alias StoreOp!(uint16, Type.INT32) op_store_u16;
alias StoreOp!(uint32, Type.INT32) op_store_u32;
alias StoreOp!(uint64, Type.INT32) op_store_u64;
alias StoreOp!(float64, Type.FLOAT) op_store_f64;
alias StoreOp!(refptr, Type.REFPTR) op_store_refptr;
alias StoreOp!(rawptr, Type.RAWPTR) op_store_rawptr;
alias StoreOp!(IRFunction, Type.FUNPTR) op_store_funptr;

extern (C) void op_jump(Interp interp, IRInstr instr)
{
    interp.jump(instr.target);
}

extern (C) void op_if_true(Interp interp, IRInstr instr)
{
    auto valIdx = instr.args[0].localIdx;
    auto wVal = interp.getWord(valIdx);
    auto tVal = interp.getType(valIdx);

    assert (
        tVal == Type.CONST,
        "input to if_true is not constant type"
    );

    if (wVal.int8Val == TRUE.int8Val)
        interp.jump(instr.target);
    else
        interp.jump(instr.excTarget);
}

void callFun(
    Interp interp,
    IRFunction fun,         // Function to call
    IRInstr callInstr,      // Return address
    refptr closPtr,         // Closure pointer
    Word thisWord,          // This value word
    Type thisType,          // This value type
    IRInstr.Arg[] argSlots  // Argument slots
)
{
    //writefln("call to %s (%s)", fun.name, cast(void*)fun);
    //writefln("num args: %s", argSlots.length);

    assert (
        fun !is null, 
        "null IRFunction pointer"
    );

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
    {
        /*    
        write("compiling");
        write("\n");
        write(core.memory.GC.addrOf(cast(void*)fun.ast));
        write("\n");
        */

        astToIR(fun.ast, fun);
    }

    // Compute the number of missing arguments
    size_t argDiff = (fun.params.length > argSlots.length)? (fun.params.length - argSlots.length):0;

    // Push undefined values for the missing last arguments
    for (size_t i = 0; i < argDiff; ++i)
        interp.push(UNDEF, Type.CONST);

    // Push the visible function arguments in reverse order
    for (size_t i = 0; i < argSlots.length; ++i)
    {
        auto argSlot = argSlots[$-(1+i)].localIdx + (argDiff + i);
        auto wArg = interp.getWord(cast(LocalIdx)argSlot);
        auto tArg = interp.getType(cast(LocalIdx)argSlot);
        interp.push(wArg, tArg);
    }

    // Push the argument count
    interp.push(Word.int32v(cast(int32)argSlots.length), Type.INT32);

    // Push the "this" argument
    interp.push(thisWord, thisType);

    // Push the closure argument
    interp.push(Word.ptrv(closPtr), Type.REFPTR);

    // Push the return address (caller instruction)
    auto retAddr = cast(rawptr)callInstr;
    interp.push(Word.ptrv(retAddr), Type.INSPTR);

    // Push space for the callee locals and initialize the slots to undefined
    auto numLocals = fun.numLocals - NUM_HIDDEN_ARGS - fun.params.length;
    interp.push(numLocals);

    // Jump to the function entry
    interp.jump(fun.entryBlock);

    // Count the number of times each callee is called
    if (callInstr !is null)
    {
        auto caller = callInstr.block.fun;
        
        if (callInstr !in caller.callCounts)
            caller.callCounts[callInstr] = uint64_t[IRFunction].init;

        if (fun !in caller.callCounts[callInstr])
            caller.callCounts[callInstr][fun] = 0;

        caller.callCounts[callInstr][fun]++;
    }
}

extern (C) void op_call(Interp interp, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;

    auto wClos = interp.getWord(closIdx);
    auto tClos = interp.getType(closIdx);

    auto wThis = interp.getWord(thisIdx);
    auto tThis = interp.getType(thisIdx);

    if (tClos != Type.REFPTR || !valIsLayout(wClos, LAYOUT_CLOS))
        return throwError(interp, instr, "TypeError", "call to non-function");

    // Get the function object from the closure
    auto closPtr = wClos.ptrVal;
    auto fun = cast(IRFunction)clos_get_fptr(closPtr);

    /*
    write(core.memory.GC.addrOf(cast(void*)fun));
    write("\n");
    */

    callFun(
        interp,
        fun,
        instr,
        closPtr,
        wThis,
        tThis,
        instr.args[2..$]
    );
}

/// JavaScript new operator (constructor call)
extern (C) void op_call_new(Interp interp, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto wClos = interp.getWord(closIdx);
    auto tClos = interp.getType(closIdx);

    if (tClos != Type.REFPTR || !valIsLayout(wClos, LAYOUT_CLOS))
        return throwError(interp, instr, "TypeError", "new with non-function");

    // Get the function object from the closure
    auto clos = GCRoot(interp, wClos.ptrVal);
    auto fun = cast(IRFunction)clos_get_fptr(clos.pair.word.ptrVal);
    assert (
        fun !is null,
        "null IRFunction pointer"
    );

    // Lookup the "prototype" property on the closure
    auto proto = GCRoot(interp);
    auto protoStr = GCRoot(interp, getString(interp, "prototype"));
    proto = getProp(
        interp, 
        clos.ptr,
        protoStr.ptr
    );

    // Allocate the "this" object
    auto thisObj = GCRoot(
        interp,
        newObj(
            interp, 
            clos_get_class(clos.ptr),
            proto.ptr,
            CLASS_INIT_SIZE,
            2
        )
    );
    clos_set_class(clos.ptr, obj_get_class(thisObj.ptr));

    callFun(
        interp,
        fun,
        instr,
        clos.ptr,
        Word.ptrv(thisObj.ptr),
        Type.REFPTR,
        instr.args[1..$]
    );
}

extern (C) void op_call_apply(Interp interp, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;
    auto tblIdx  = instr.args[2].localIdx;
    auto argcIdx = instr.args[3].localIdx;

    auto wClos = interp.getWord(closIdx);
    auto tClos = interp.getType(closIdx);

    auto wThis = interp.getWord(thisIdx);
    auto tThis = interp.getType(thisIdx);

    auto wTbl = interp.getWord(tblIdx);
    auto tTbl = interp.getType(tblIdx);

    auto wArgc = interp.getWord(argcIdx);
    auto tArgc = interp.getType(argcIdx);

    if (tClos != Type.REFPTR || !valIsLayout(wClos, LAYOUT_CLOS))
        return throwError(interp, instr, "TypeError", "call to non-function");

    if (tTbl != Type.REFPTR || !valIsLayout(wTbl, LAYOUT_ARRTBL))
        return throwError(interp, instr, "TypeError", "invalid argument table");

    if (tArgc != Type.INT32)
        return throwError(interp, instr, "TypeError", "invalid argument count type");

    // Get the array table
    auto argTbl = wTbl.ptrVal;

    // Get the argument count
    auto argc = wArgc.uint32Val;

    // Get the function object from the closure
    auto closPtr = interp.getWord(closIdx).ptrVal;
    auto fun = cast(IRFunction)clos_get_fptr(closPtr);

    assert (
        fun !is null, 
        "null IRFunction pointer"
    );

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
        astToIR(fun.ast, fun);

    // Compute the number of missing arguments
    size_t argDiff = (fun.params.length > argc)? (fun.params.length - argc):0;

    // Push undefined values for the missing last arguments
    for (size_t i = 0; i < argDiff; ++i)
        interp.push(UNDEF, Type.CONST);

    // Push the visible function arguments in reverse order
    for (uint32 i = 0; i < argc; ++i)
    {
        uint32 argIdx = cast(uint32)argc - (1+i);
        auto wArg = Word.uint64v(arrtbl_get_word(argTbl, argIdx));
        auto tArg = cast(Type)arrtbl_get_type(argTbl, argIdx);
        interp.push(wArg, tArg);
    }

    // Push the argument count
    interp.push(Word.uint32v(argc), Type.INT32);

    // Push the "this" argument
    interp.push(wThis, tThis);

    // Push the closure argument
    interp.push(Word.ptrv(closPtr), Type.REFPTR);

    // Push the return address (caller instruction)
    auto retAddr = cast(rawptr)instr;
    interp.push(Word.ptrv(retAddr), Type.INSPTR);

    // Push space for the callee locals and initialize the slots to undefined
    auto numLocals = fun.numLocals - NUM_HIDDEN_ARGS - fun.params.length;
    interp.push(numLocals);

    // Jump to the function entry
    interp.jump(fun.entryBlock);
}

extern (C) void op_ret(Interp interp, IRInstr instr)
{
    //writefln("ret from %s", instr.block.fun.name);

    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.block.fun.raSlot;
    auto argcSlot  = instr.block.fun.argcSlot;
    auto numParams = instr.block.fun.params.length;
    auto numLocals = instr.block.fun.numLocals;

    // Get the return value
    auto wRet = interp.wsp[retSlot];
    auto tRet = interp.tsp[retSlot];

    // Get the calling instruction
    auto callInstr = cast(IRInstr)interp.wsp[raSlot].ptrVal;

    // Get the argument count
    auto argCount = interp.wsp[argcSlot].uint32Val;

    // If the call instruction is valid
    if (callInstr !is null)
    {
        // If this is a new call and the return value is undefined
        if (callInstr.opcode == &CALL_NEW && (tRet == Type.CONST && wRet == UNDEF))
        {
            // Use the this value as the return value
            wRet = interp.getWord(instr.block.fun.thisSlot);
            tRet = interp.getType(instr.block.fun.thisSlot);
        }

        // Compute the actual number of extra arguments to pop
        size_t extraArgs = (argCount > numParams)? (argCount - numParams):0;

        //writefln("argCount: %s", argCount);
        //writefln("popping %s", numLocals + extraArgs);

        // Pop all local stack slots and arguments
        interp.pop(numLocals + extraArgs);

        // Set the instruction pointer to the call continuation instruction
        interp.jump(callInstr.target);

        // Leave the return value in the call's return slot, if any
        if (callInstr.outSlot !is NULL_LOCAL)
        {
            interp.setSlot(
                callInstr.outSlot,
                wRet,
                tRet
            );
        }
    }
    else
    {
        // Pop all local stack slots
        interp.pop(numLocals);

        // Terminate the execution
        interp.jump(null);

        // Leave the return value on top of the stack
        interp.push(wRet, tRet);
    }
}

extern (C) void op_throw(Interp interp, IRInstr instr)
{
    // Get the exception value
    auto excSlot = instr.args[0].localIdx;
    auto excVal = interp.getSlot(excSlot);

    // Throw the exception
    throwExc(interp, instr, excVal);
}

extern (C) void op_get_arg(Interp interp, IRInstr instr)
{
    // Get the first argument slot
    auto argSlot = instr.block.fun.argcSlot + 1;

    // Get the argument index
    auto idxVal = interp.getSlot(instr.args[0].localIdx);
    auto idx = idxVal.word.uint32Val;

    auto argVal = interp.getSlot(argSlot + idx);

    interp.setSlot(
        instr.outSlot,
        argVal
    );
}

extern (C) void op_get_fun_ptr(Interp interp, IRInstr instr)
{
    auto fun = instr.args[0].fun;

    // Register this function in the function reference set
    interp.funRefs[cast(void*)fun] = fun;

    //write(interp.funRefs.length);
    //write("\n");

    rawptr ptr = cast(rawptr)fun;

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(ptr),
        Type.FUNPTR
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
    auto wSize = interp.getWord(instr.args[0].localIdx);
    auto tSize = interp.getType(instr.args[0].localIdx);

    assert (
        tSize == Type.INT32,
        "invalid size type"
    );

    assert (
        wSize.uint32Val > 0,
        "size must be positive"
    );

    auto ptr = heapAlloc(interp, wSize.uint32Val);

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(ptr),
        Type.REFPTR
    );
}

extern (C) void op_gc_collect(Interp interp, IRInstr instr)
{
    auto wSize = interp.getWord(instr.args[0].localIdx);
    auto tSize = interp.getType(instr.args[0].localIdx);

    assert (
        tSize == Type.INT32,
        "invalid heap size type"
    );

    gcCollect(interp, wSize.uint32Val);
}

extern (C) void op_make_link(Interp interp, IRInstr instr)
{
    auto linkIdx = instr.args[0].linkIdx;

    if (linkIdx is NULL_LINK)
    {
        linkIdx = interp.allocLink();
        instr.args[0].linkIdx = linkIdx;

        interp.setLinkWord(linkIdx, NULL);
        interp.setLinkType(linkIdx, Type.REFPTR);
    }

    interp.setSlot(
        instr.outSlot,
        Word.uint32v(linkIdx),
        Type.INT32
    );
}

extern (C) void op_set_link(Interp interp, IRInstr instr)
{
    auto linkIdx = interp.getWord(instr.args[0].linkIdx).uint32Val;

    auto wVal = interp.getWord(instr.args[1].localIdx);
    auto tVal = interp.getType(instr.args[1].localIdx);

    interp.setLinkWord(linkIdx, wVal);
    interp.setLinkType(linkIdx, tVal);
}

extern (C) void op_get_link(Interp interp, IRInstr instr)
{
    auto linkIdx = interp.getWord(instr.args[0].linkIdx).uint32Val;

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
    auto wStr = interp.getWord(instr.args[0].localIdx);
    auto tStr = interp.getType(instr.args[0].localIdx);

    assert (
        valIsString(wStr, tStr),
        "expected string in get_str"
    );

    auto ptr = wStr.ptrVal;

    // Compute and set the hash code for the string
    auto hashCode = compStrHash(ptr);
    str_set_hash(ptr, hashCode);

    // Find the corresponding string in the string table
    ptr = getTableStr(interp, ptr);

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(ptr),
        Type.REFPTR
    );
}

/// Get the value of a global variable
extern (C) void op_get_global(Interp interp, IRInstr instr)
{
    // Name string (D string)
    auto nameStr = instr.args[0].stringVal;

    // Cached property index
    auto propIdx = instr.args[1].int32Val;

    // If a property index was cached
    if (propIdx >= 0)
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
        instr.args[1].int32Val = propIdx;
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
    auto nameStr = instr.args[0].stringVal;

    // Property value
    auto wVal = interp.getWord(instr.args[1].localIdx);
    auto tVal = interp.getType(instr.args[1].localIdx);

    // Cached property index
    auto propIdx = instr.args[2].int32Val;

    // If a property index was cached
    if (propIdx >= 0)
    {
        obj_set_word(interp.globalObj, cast(uint32)propIdx, wVal.uint64Val);
        obj_set_type(interp.globalObj, cast(uint32)propIdx, tVal);

        return;
    }

    // Save the value in a GC root
    auto val = GCRoot(interp, wVal, tVal);

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
        instr.args[2].int32Val = propIdx;
    }
}

extern (C) void op_new_clos(Interp interp, IRInstr instr)
{
    //writefln("entering newclos");

    auto fun = instr.args[0].fun;
    auto closLinkIdx = &instr.args[1].linkIdx;
    auto protLinkIdx = &instr.args[2].linkIdx;

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
            1,
            cast(uint32)fun.captVars.length,
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
    auto wFile = interp.getWord(instr.args[0].localIdx);
    auto tFile = interp.getType(instr.args[0].localIdx);

    assert (
        valIsString(wFile, tFile),
        "expected string filename argument in load_file"
    );

    auto fileName = extractStr(wFile.ptrVal);

    // Parse the source file and generate IR
    auto ast = parseFile(fileName);
    auto fun = astToIR(ast);

    // Register this function in the function reference set
    interp.funRefs[cast(void*)fun] = fun;

    // Setup the callee stack frame
    callFun(
        interp,
        fun,
        instr,      // Calling instruction
        null,       // Null closure argument
        NULL,       // Null this argument
        Type.REFPTR,// This value is a reference
        []          // 0 arguments
    );
}

extern (C) void op_eval_str(Interp interp, IRInstr instr)
{
    auto wStr = interp.getWord(instr.args[0].localIdx);
    auto tStr = interp.getType(instr.args[0].localIdx);

    assert (
        valIsString(wStr, tStr),
        "expected string argument in eval_str"
    );

    auto codeStr = extractStr(wStr.ptrVal);

    // Parse the source file and generate IR
    auto ast = parseString(codeStr, "eval_str");
    auto fun = astToIR(ast);

    // Register this function in the function reference set
    interp.funRefs[cast(void*)fun] = fun;

    // Setup the callee stack frame
    callFun(
        interp,
        fun,
        instr,      // Calling instruction
        null,       // Null closure argument
        NULL,       // Null this argument
        Type.REFPTR,// This value is a reference
        []          // 0 arguments
    );
}

extern (C) void op_print_str(Interp interp, IRInstr instr)
{
    auto wStr = interp.getWord(instr.args[0].localIdx);
    auto tStr = interp.getType(instr.args[0].localIdx);

    assert (
        valIsString(wStr, tStr),
        "expected string in print_str"
    );

    auto str = extractStr(wStr.ptrVal);

    // Print the string to standard output
    write(str);
}

extern (C) void op_get_ast_str(Interp interp, IRInstr instr)
{
    auto wFn = interp.getWord(instr.args[0].localIdx);
    auto tFn = interp.getType(instr.args[0].localIdx);

    assert (
        tFn == Type.REFPTR && valIsLayout(wFn, LAYOUT_CLOS),
        "invalid closure object"
    );

    auto fun = cast(IRFunction)clos_get_fptr(wFn.ptrVal);
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
    auto wFn = interp.getWord(instr.args[0].localIdx);
    auto tFn = interp.getType(instr.args[0].localIdx);

    assert (
        tFn == Type.REFPTR && valIsLayout(wFn, LAYOUT_CLOS),
        "invalid closure object"
    );

    auto fun = cast(IRFunction)clos_get_fptr(wFn.ptrVal);

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
    auto val = interp.getSlot(instr.args[0].localIdx);

    assert (
        val.type == Type.FLOAT,
        "invalid float value"
    );

    auto str = format("%G", val.word.floatVal);
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

    // Library to load (D string)
    auto libname = to!string(instr.args[0].stringVal);

    // String must be null terminated
    // todo: use lib for this?
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
    auto lib = interp.getSlot(instr.args[0].localIdx);

    assert (
        lib.type == Type.RAWPTR,
        "invalid rawptr value"
    );

    if (dlclose(lib.word.ptrVal) != 0)
         return throwError(interp, instr, "RuntimeError", "could not close lib.");
}

extern (C) void op_get_sym(Interp interp, IRInstr instr)
{
    // handle for shared lib
    auto lib = interp.getSlot(instr.args[0].localIdx);

    assert (
        lib.type == Type.RAWPTR,
        "invalid rawptr value"
    );

    // Symbol name (D string)
    auto symname = to!string(instr.args[1].stringVal);

    // String must be null terminated
    // todo: use lib for this?
    symname ~= '\0';

    auto sym = dlsym(lib.word.ptrVal, symname.ptr);

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
    auto fun = interp.getSlot(instr.args[1].localIdx);

    assert (
        fun.type == Type.RAWPTR,
        "invalid rawptr value"
    );

    CodeBlock cb;

    // Check if there is a cached CodeBlock, generate one if not
    if (instr.args[0].codeBlock is null)
    {
        // Type info (D string)
        auto typeinfo = to!string(instr.args[2].stringVal);
        auto types = split(typeinfo, ",");
        // Slots for arguments
        LocalIdx[] argSlots;

        foreach(a;instr.args[3..$])
            argSlots ~= a.localIdx;

        assert (
            argSlots.length == types.length - 1,
            "invalid number of args in ffi call"
        );

        cb = genFFIFn(interp, types, instr.outSlot, argSlots);
        instr.args[0].codeBlock = cb;
    }
    else
    {
        cb = instr.args[0].codeBlock;
    }

    FFIFn callerfun = cast(FFIFn)(cb.getAddress());
    callerfun(cast(void*)fun.word.ptrVal);

    interp.jump(instr.target);
}

