/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013, Maxime Chevalier-Boisvert. All rights reserved.
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
import ir.ir;
import ir.ast;
import interp.interp;
import interp.layout;
import interp.string;
import interp.object;
import interp.gc;

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
        if (curInstr.opcode is &CALL && curInstr.target !is null)
        {
            //writefln("found exception target");

            // Set the return value slot to the exception value
            interp.setSlot(
                curInstr.outSlot, 
                excVal
            );

            // Go to the exception target
            interp.ip = curInstr.target.firstInstr;

            // Stop unwinding the stack
            return;
        }

        auto numLocals = curInstr.fun.numLocals;
        auto numParams = curInstr.fun.params.length;
        auto argcSlot = curInstr.fun.argcSlot;
        auto raSlot = curInstr.fun.raSlot;

        // Get the calling instruction for the current stack frame
        curInstr = cast(IRInstr)interp.wsp[raSlot].ptrVal;

        // Get the argument count
        auto argCount = interp.wsp[argcSlot].intVal;

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

void op_set_int(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        Word.intv(instr.args[0].intVal),
        Type.INT
    );
}

void op_set_float(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        Word.floatv(instr.args[0].floatVal),
        Type.FLOAT
    );
}

void op_set_str(Interp interp, IRInstr instr)
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

void op_set_true(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        TRUE,
        Type.CONST
    );
}

void op_set_false(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        FALSE,
        Type.CONST
    );
}

void op_set_null(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        NULL,
        Type.REFPTR
    );
}

void op_set_undef(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        UNDEF,
        Type.CONST
    );
}

void op_set_value(Interp interp, IRInstr instr)
{
    auto wWord = interp.getWord(instr.args[0].localIdx);

    auto wType = interp.getWord(instr.args[1].localIdx);
    auto tType = interp.getType(instr.args[1].localIdx);

    assert (
        tType == Type.INT,
        "type should be integer"
    );

    assert (
        wType.intVal >= Type.min && wType.intVal <= Type.max,
        "type value out of range: " ~ to!string(wType.intVal)
    );

    interp.setSlot(
        instr.outSlot,
        Word.intv(wWord.intVal),
        cast(Type)wType.intVal
    );
}

void op_get_word(Interp interp, IRInstr instr)
{
    auto word = interp.getWord(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        word,
        Type.INT
    );
}

void op_get_type(Interp interp, IRInstr instr)
{
    auto type = interp.getType(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        Word.intv(cast(int)type),
        Type.INT
    );
}

void op_move(Interp interp, IRInstr instr)
{
    interp.move(
        instr.args[0].localIdx,
        instr.outSlot
    );
}

void TypeCheckOp(Type type)(Interp interp, IRInstr instr)
{
    auto typeTag = interp.getType(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        (typeTag == type)? TRUE:FALSE,
        Type.CONST
    );
}

alias TypeCheckOp!(Type.INT) op_is_int;
alias TypeCheckOp!(Type.FLOAT) op_is_float;
alias TypeCheckOp!(Type.REFPTR) op_is_refptr;
alias TypeCheckOp!(Type.RAWPTR) op_is_rawptr;
alias TypeCheckOp!(Type.CONST) op_is_const;

void op_i32_to_f64(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        Word.floatv(cast(int32)w0.intVal),
        Type.FLOAT
    );
}

void op_i64_to_f64(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        Word.floatv(w0.intVal),
        Type.FLOAT
    );
}

void op_f64_to_i32(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        Word.intv(cast(int32)w0.floatVal),
        Type.FLOAT
    );
}

void op_f64_to_i64(Interp interp, IRInstr instr)
{
    auto w0 = interp.getWord(instr.args[0].localIdx);

    interp.setSlot(
        instr.outSlot,
        Word.intv(cast(int64)w0.floatVal),
        Type.FLOAT
    );
}

void ArithOp(DataType, Type typeTag, uint arity, string op)(Interp interp, IRInstr instr)
{
    static assert (
        typeTag == Type.INT || typeTag == Type.FLOAT
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
            "invalid operand 1 type in op \"" ~ op ~ "\" (" ~ DataType.stringof ~ ")"
        );
    }
    static if (arity > 1)
    {
        auto wY = interp.getWord(instr.args[1].localIdx);
        auto tY = interp.getType(instr.args[1].localIdx);

        assert (
            tY == typeTag,
            "invalid operand 2 type in op \"" ~ op ~ "\" (" ~ DataType.stringof ~ ")"
        );
    }

    Word output;

    static if (typeTag == Type.INT)
    {
        static if (arity > 0)
            auto x = cast(DataType)wX.intVal;
        static if (arity > 1)
            auto y = cast(DataType)wY.intVal;
    }
    static if (typeTag == Type.FLOAT)
    {
        static if (arity > 0)
            auto x = cast(DataType)wX.floatVal;
        static if (arity > 1)
            auto y = cast(DataType)wY.floatVal;
    }

    mixin(op);

    static if (typeTag == Type.INT)
        output.intVal = r;
    static if (typeTag == Type.FLOAT)
        output.floatVal = r;

    interp.setSlot(
        instr.outSlot,
        output,
        typeTag
    );
}

alias ArithOp!(int32, Type.INT, 2, "auto r = x + y;") op_add_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x - y;") op_sub_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x * y;") op_mul_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x / y;") op_div_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x % y;") op_mod_i32;

alias ArithOp!(int32, Type.INT, 2, "auto r = x & y;") op_and_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x | y;") op_or_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x ^ y;") op_xor_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x << y;") op_lsft_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = x >> y;") op_rsft_i32;
alias ArithOp!(int32, Type.INT, 2, "auto r = cast(uint32)x >>> y;") op_ursft_i32;
alias ArithOp!(int32, Type.INT, 1, "auto r = ~x;") op_not_i32;

alias ArithOp!(float64, Type.FLOAT, 2, "auto r = x + y;") op_add_f64;
alias ArithOp!(float64, Type.FLOAT, 2, "auto r = x - y;") op_sub_f64;
alias ArithOp!(float64, Type.FLOAT, 2, "auto r = x * y;") op_mul_f64;
alias ArithOp!(float64, Type.FLOAT, 2, "auto r = x / y;") op_div_f64;

alias ArithOp!(float64, Type.FLOAT, 1, "auto r = sin(x);") op_sin_f64;
alias ArithOp!(float64, Type.FLOAT, 1, "auto r = cos(x);") op_cos_f64;
alias ArithOp!(float64, Type.FLOAT, 1, "auto r = sqrt(x);") op_sqrt_f64;
alias ArithOp!(float64, Type.FLOAT, 1, "auto r = ceil(x);") op_ceil_f64;
alias ArithOp!(float64, Type.FLOAT, 1, "auto r = floor(x);") op_floor_f64;
alias ArithOp!(float64, Type.FLOAT, 1, "auto r = log(x);") op_log_f64;
alias ArithOp!(float64, Type.FLOAT, 1, "auto r = exp(x);") op_exp_f64;
alias ArithOp!(float64, Type.FLOAT, 2, "auto r = pow(x, y);") op_pow_f64;

void ArithOpOvf(DataType, Type typeTag, string op)(Interp interp, IRInstr instr)
{
    auto wX = interp.getWord(instr.args[0].localIdx);
    auto tX = interp.getType(instr.args[0].localIdx);
    auto wY = interp.getWord(instr.args[1].localIdx);
    auto tY = interp.getType(instr.args[1].localIdx);

    assert (
        tX == Type.INT && tY == Type.INT,
        "invalid operand types in ovf op \"" ~ op ~ "\" (" ~ DataType.stringof ~ ")"
    );

    auto x = wX.intVal;
    auto y = wY.intVal;

    mixin(op);

    if (r >= DataType.min && r <= DataType.max)
    {
        interp.setSlot(
            instr.outSlot,
            Word.intv(cast(DataType)r),
            Type.INT
        );
    }
    else
    {
        interp.ip = instr.target.firstInstr;
    }
}

alias ArithOpOvf!(int32, Type.INT, "auto r = x + y;") op_add_i32_ovf;
alias ArithOpOvf!(int32, Type.INT, "auto r = x - y;") op_sub_i32_ovf;
alias ArithOpOvf!(int32, Type.INT, "auto r = x * y;") op_mul_i32_ovf;
alias ArithOpOvf!(int32, Type.INT, "auto r = x << y;") op_lsft_i32_ovf;

void CompareOp(DataType, Type typeTag, string op)(Interp interp, IRInstr instr)
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

    static if (typeTag == Type.INT || typeTag == Type.CONST)
    {
        auto x = cast(DataType)wX.intVal;
        auto y = cast(DataType)wY.intVal;
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

alias CompareOp!(int32, Type.INT, "r = (x == y);") op_eq_i32;
alias CompareOp!(int32, Type.INT, "r = (x != y);") op_ne_i32;
alias CompareOp!(int32, Type.INT, "r = (x < y);") op_lt_i32;
alias CompareOp!(int32, Type.INT, "r = (x > y);") op_gt_i32;
alias CompareOp!(int32, Type.INT, "r = (x <= y);") op_le_i32;
alias CompareOp!(int32, Type.INT, "r = (x >= y);") op_ge_i32;
alias CompareOp!(int8, Type.INT, "r = (x == y);") op_eq_i8;

alias CompareOp!(refptr, Type.REFPTR, "r = (x == y);") op_eq_refptr;
alias CompareOp!(refptr, Type.REFPTR, "r = (x != y);") op_ne_refptr;

alias CompareOp!(uint8, Type.CONST, "r = (x == y);") op_eq_const;
alias CompareOp!(uint8, Type.CONST, "r = (x != y);") op_ne_const;

alias CompareOp!(float64, Type.FLOAT, "r = (x == y);") op_eq_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x != y);") op_ne_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x < y);") op_lt_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x > y);") op_gt_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x <= y);") op_le_f64;
alias CompareOp!(float64, Type.FLOAT, "r = (x >= y);") op_ge_f64;

void LoadOp(DataType, Type typeTag)(Interp interp, IRInstr instr)
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
        tOfs == Type.INT,
        "offset is not integer type in load op"
    );

    auto ptr = wPtr.ptrVal;
    auto ofs = wOfs.intVal;

    auto val = *cast(DataType*)(ptr + ofs);

    Word word;

    static if (
        DataType.stringof == "byte"  ||
        DataType.stringof == "short" ||
        DataType.stringof == "int"   ||
        DataType.stringof == "long")
        word.intVal = val;

    static if (
        DataType.stringof == "ubyte"  ||
        DataType.stringof == "ushort" ||
        DataType.stringof == "uint"   ||
        DataType.stringof == "ulong")
        word.uintVal = val;

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

void StoreOp(DataType, Type typeTag)(Interp interp, IRInstr instr)
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
        tOfs == Type.INT,
        "offset is not integer type in store op"
    );

    auto ptr = wPtr.ptrVal;
    auto ofs = wOfs.intVal;

    auto word = interp.getWord(instr.args[2].localIdx);

    DataType val;

    static if (
        DataType.stringof == "byte"  ||
        DataType.stringof == "short" ||
        DataType.stringof == "int"   ||
        DataType.stringof == "long")
        val = cast(DataType)word.intVal;

    static if (
        DataType.stringof == "ubyte"  ||
        DataType.stringof == "ushort" ||
        DataType.stringof == "uint"   ||
        DataType.stringof == "ulong")
        val = cast(DataType)word.uintVal;

    static if (DataType.stringof == "double")
        val = cast(DataType)word.floatVal;

    static if (
        DataType.stringof == "void*" ||
        DataType.stringof == "ubyte*" ||
        DataType.stringof == "IRFunction")
        val = cast(DataType)word.ptrVal;

    *cast(DataType*)(ptr + ofs) = val;
}

alias LoadOp!(uint8, Type.INT) op_load_u8;
alias LoadOp!(uint16, Type.INT) op_load_u16;
alias LoadOp!(uint32, Type.INT) op_load_u32;
alias LoadOp!(uint64, Type.INT) op_load_u64;
alias LoadOp!(float64, Type.FLOAT) op_load_f64;
alias LoadOp!(refptr, Type.REFPTR) op_load_refptr;
alias LoadOp!(rawptr, Type.RAWPTR) op_load_rawptr;
alias LoadOp!(IRFunction, Type.FUNPTR) op_load_funptr;

alias StoreOp!(uint8, Type.INT) op_store_u8;
alias StoreOp!(uint16, Type.INT) op_store_u16;
alias StoreOp!(uint32, Type.INT) op_store_u32;
alias StoreOp!(uint64, Type.INT) op_store_u64;
alias StoreOp!(float64, Type.FLOAT) op_store_f64;
alias StoreOp!(refptr, Type.REFPTR) op_store_refptr;
alias StoreOp!(rawptr, Type.RAWPTR) op_store_rawptr;
alias StoreOp!(IRFunction, Type.FUNPTR) op_store_funptr;

void op_jump(Interp interp, IRInstr instr)
{
    interp.ip = instr.target.firstInstr;
}

void op_jump_true(Interp interp, IRInstr instr)
{
    auto valIdx = instr.args[0].localIdx;
    auto wVal = interp.getWord(valIdx);

    if (wVal == TRUE)
        interp.ip = instr.target.firstInstr;
}

void op_jump_false(Interp interp, IRInstr instr)
{
    auto valIdx = instr.args[0].localIdx;
    auto wVal = interp.getWord(valIdx);

    if (wVal == FALSE)
        interp.ip = instr.target.firstInstr;
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
    //writefln("call to %s", fun.name);

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
        auto wArg = interp.getWord(argSlot);
        auto tArg = interp.getType(argSlot);
        interp.push(wArg, tArg);
    }

    // Push the argument count
    interp.push(Word.intv(argSlots.length), Type.INT);

    // Push the "this" argument
    interp.push(thisWord, thisType);

    // Push the closure argument
    interp.push(Word.ptrv(closPtr), Type.REFPTR);

    // Push the return address (caller instruction)
    auto retAddr = cast(rawptr)callInstr;
    interp.push(Word.ptrv(retAddr), Type.RAWPTR);

    // Push space for the callee locals
    interp.push(fun.numLocals - NUM_HIDDEN_ARGS - fun.params.length);

    // Set the instruction pointer
    interp.ip = fun.entryBlock.firstInstr;
}

void op_call(Interp interp, IRInstr instr)
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
    auto closPtr = interp.getWord(closIdx).ptrVal;
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
void op_call_new(Interp interp, IRInstr instr)
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

void op_ret(Interp interp, IRInstr instr)
{
    //writefln("ret from %s", instr.fun.name);

    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.fun.raSlot;
    auto argcSlot  = instr.fun.argcSlot;
    auto numParams = instr.fun.params.length;
    auto numLocals = instr.fun.numLocals;

    // Get the return value
    auto wRet = interp.wsp[retSlot];
    auto tRet = interp.tsp[retSlot];

    // Get the calling instruction
    auto callInstr = cast(IRInstr)interp.wsp[raSlot].ptrVal;

    // Get the argument count
    auto argCount = interp.wsp[argcSlot].intVal;

    // If the call instruction is valid
    if (callInstr !is null)
    {
        // If this is a new call and the return value is undefined
        if (callInstr.opcode == &CALL_NEW && wRet == UNDEF)
        {
            // Use the this value as the return value
            wRet = interp.getWord(instr.fun.thisSlot);
            tRet = interp.getType(instr.fun.thisSlot);
        }

        // Compute the actual number of extra arguments to pop
        size_t extraArgs = (argCount > numParams)? (argCount - numParams):0;

        // Pop all local stack slots and arguments
        interp.pop(numLocals + extraArgs);

        // Set the instruction pointer to the post-call instruction
        interp.ip = callInstr.next;

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
        interp.ip = null;

        // Leave the return value on top of the stack
        interp.push(wRet, tRet);
    }
}

void op_throw(Interp interp, IRInstr instr)
{
    // Get the exception value
    auto excSlot = instr.args[0].localIdx;
    auto excVal = interp.getSlot(excSlot);

    // Throw the exception
    throwExc(interp, instr, excVal);
}

void op_get_arg(Interp interp, IRInstr instr)
{
    // Get the first argument slot
    auto argSlot = instr.fun.argcSlot + 1;

    // Get the argument index
    auto idxVal = interp.getSlot(instr.args[0].localIdx);
    auto idx = idxVal.word.intVal;

    assert (
        idx >= 0,
        "negative argument index"
    );
    
    auto argVal = interp.getSlot(argSlot + idx);

    interp.setSlot(
        instr.outSlot,
        argVal
    );
}

void op_get_fun_ptr(Interp interp, IRInstr instr)
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
void GetValOp(Type typeTag, string op)(Interp interp, IRInstr instr)
{
    static assert (
        typeTag == Type.INT || typeTag == Type.REFPTR
    );

    mixin(op);

    Word output;

    static if (typeTag == Type.INT)
        output.intVal = r;
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
alias GetValOp!(Type.INT, "auto r = interp.heapSize;") op_get_heap_size;
alias GetValOp!(Type.INT, "auto r = interp.heapLimit - interp.allocPtr;") op_get_heap_free;
alias GetValOp!(Type.INT, "auto r = interp.gcCount;") op_get_gc_count;

void op_heap_alloc(Interp interp, IRInstr instr)
{
    auto wSize = interp.getWord(instr.args[0].localIdx);
    auto tSize = interp.getType(instr.args[0].localIdx);

    assert (
        tSize == Type.INT,
        "invalid size type"
    );

    assert (
        wSize.intVal > 0,
        "size must be positive"
    );

    auto ptr = heapAlloc(interp, wSize.intVal);

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(ptr),
        Type.REFPTR
    );
}

void op_gc_collect(Interp interp, IRInstr instr)
{
    auto wSize = interp.getWord(instr.args[0].localIdx);
    auto tSize = interp.getType(instr.args[0].localIdx);

    assert (
        tSize == Type.INT,
        "invalid heap size type"
    );

    gcCollect(interp, wSize.uintVal);
}

void op_make_link(Interp interp, IRInstr instr)
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
        Word.intv(linkIdx),
        Type.INT
    );
}

void op_set_link(Interp interp, IRInstr instr)
{
    auto linkIdx = interp.getWord(instr.args[0].linkIdx).intVal;

    auto wVal = interp.getWord(instr.args[1].localIdx);
    auto tVal = interp.getType(instr.args[1].localIdx);

    interp.setLinkWord(linkIdx, wVal);
    interp.setLinkType(linkIdx, tVal);
}

void op_get_link(Interp interp, IRInstr instr)
{
    auto linkIdx = interp.getWord(instr.args[0].linkIdx).intVal;

    auto wVal = interp.getLinkWord(linkIdx);
    auto tVal = interp.getLinkType(linkIdx);

    interp.setSlot(
        instr.outSlot,
        wVal,
        tVal
    );    
}

void op_get_str(Interp interp, IRInstr instr)
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
void op_get_global(Interp interp, IRInstr instr)
{
    // Name string (D string)
    auto nameStr = instr.args[0].stringVal;

    // Cached property index
    auto propIdx = instr.args[1].intVal;

    // If a property index was cached
    if (propIdx >= 0)
    {
        auto wVal = obj_get_word(interp.globalObj, cast(uint32)propIdx);
        auto tVal = obj_get_type(interp.globalObj, cast(uint32)propIdx);

        interp.setSlot(
            instr.outSlot,
            Word.intv(wVal),
            cast(Type)tVal
        );

        return;
    }

    auto propStr = GCRoot(interp, getString(interp, nameStr));

    // Lookup the property index in the class
    propIdx = getPropIdx(obj_get_class(interp.globalObj), propStr.ptr);

    // If the property was found, cache it
    if (propIdx != uint32.max)
    {
        // Cache the property index
        instr.args[1].intVal = propIdx;
    }
    else
    {
        // TODO: remove, throw error when getProp fails to find
        writefln("global prop unresolved %s", nameStr);
    }

    // Lookup the property
    ValuePair val = getProp(
        interp,
        interp.globalObj,
        propStr.ptr
    );

    interp.setSlot(
        instr.outSlot,
        val
    );
}

/// Set the value of a global variable
void op_set_global(Interp interp, IRInstr instr)
{
    // Name string (D string)
    auto nameStr = instr.args[0].stringVal;

    // Property value
    auto wVal = interp.getWord(instr.args[1].localIdx);
    auto tVal = interp.getType(instr.args[1].localIdx);

    // Cached property index
    auto propIdx = instr.args[2].intVal;

    // If a property index was cached
    if (propIdx >= 0)
    {
        obj_set_word(interp.globalObj, cast(uint32)propIdx, wVal.intVal);
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
    propIdx = getPropIdx(obj_get_class(interp.globalObj), propStr.ptr);

    // If the property was found, cache it
    if (propIdx != uint32.max)
    {
        // Cache the property index
        instr.args[2].intVal = propIdx;
    }
}

void op_new_clos(Interp interp, IRInstr instr)
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

    //writefln("leaving newclos");
   
    // Output a pointer to the closure
    interp.setSlot(
        instr.outSlot,
        closPtr.word,
        Type.REFPTR
    );
}

void op_print_str(Interp interp, IRInstr instr)
{
    auto wStr = interp.getWord(instr.args[0].localIdx);
    auto tStr = interp.getType(instr.args[0].localIdx);

    assert (
        valIsString(wStr, tStr),
        "expected string in print_str"
    );

    auto ptr = wStr.ptrVal;

    auto len = str_get_len(ptr);
    wchar[] wchars = new wchar[len];
    for (uint32 i = 0; i < len; ++i)
        wchars[i] = str_get_data(ptr, i);

    auto str = to!string(wchars);

    // Print the string to standard output
    write(str);
}

void op_get_ast_str(Interp interp, IRInstr instr)
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

void op_get_ir_str(Interp interp, IRInstr instr)
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

void op_f64_to_str(Interp interp, IRInstr instr)
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

