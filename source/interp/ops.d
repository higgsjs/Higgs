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

module interp.ops;

import std.stdio;
import std.algorithm;
import ir.ir;
import ir.ast;
import interp.interp;
import interp.layout;
import interp.string;

void opSetInt(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        Word.intv(instr.args[0].intVal),
        Type.INT
    );
}

void opSetFloat(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        Word.floatv(instr.args[0].floatVal),
        Type.FLOAT
    );
}

void opSetStr(Interp interp, IRInstr instr)
{
    auto objPtr = instr.args[1].ptrVal;

    // If the string is null, allocate it
    if (objPtr is null)
    {
        objPtr = getString(interp, instr.args[0].stringVal);
    }

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(objPtr),
        Type.STRING
    );
}

void opSetTrue(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        TRUE,
        Type.CONST
    );
}

void opSetFalse(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        FALSE,
        Type.CONST
    );
}

void opSetNull(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        NULL,
        Type.CONST
    );
}

void opSetUndef(Interp interp, IRInstr instr)
{
    interp.setSlot(
        instr.outSlot,
        UNDEF,
        Type.CONST
    );
}

void opMove(Interp interp, IRInstr instr)
{
    interp.move(
        instr.args[0].localIdx,
        instr.outSlot
    );
}

void opAdd(Interp interp, IRInstr instr)
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
            w0.intVal + w1.intVal
        );
    }

    // If either value is floating-point or integer
    else if (
        (t0 == Type.FLOAT || t0 == Type.INT) &&
        (t1 == Type.FLOAT || t1 == Type.INT))
    {
        auto f0 = (t0 == Type.FLOAT)? w0.floatVal:cast(float64)w0.intVal;
        auto f1 = (t1 == Type.FLOAT)? w1.floatVal:cast(float64)w1.intVal;

        interp.setSlot(
            instr.outSlot,
            f0 + f1
        );
    }

    // If either value is a string
    else if (t0 == Type.STRING || t1 == Type.STRING)
    {
        // Evaluate the string value of both arguments
        auto s0 = interp.stringVal(w0, t0);
        auto s1 = interp.stringVal(w1, t1);

        auto l0 = str_get_len(s0);
        auto l1 = str_get_len(s1);

        auto sO = str_alloc(interp, l0+l1);

        for (size_t i = 0; i < l0; ++i)
            str_set_data(sO, i, str_get_data(s0, i));
        for (size_t i = 0; i < l1; ++i)
            str_set_data(sO, l0+i, str_get_data(s1, i));

        compStrHash(sO);
        sO = getTableStr(interp, sO);

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

void opSub(Interp interp, IRInstr instr)
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
            w0.intVal - w1.intVal
        );
    }

    // If either value is floating-point or integer
    else if (
        (t0 == Type.FLOAT || t0 == Type.INT) &&
        (t1 == Type.FLOAT || t1 == Type.INT))
    {
        auto f0 = (t0 == Type.FLOAT)? w0.floatVal:cast(float64)w0.intVal;
        auto f1 = (t1 == Type.FLOAT)? w1.floatVal:cast(float64)w1.intVal;

        interp.setSlot(
            instr.outSlot, 
            f0 - f1
        );
    }

    else
    {
        assert (false, "unsupported types in sub");
    }
}

void opMul(Interp interp, IRInstr instr)
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
            w0.intVal * w1.intVal
        );
    }

    // If either value is floating-point or integer
    else if (
        (t0 == Type.FLOAT || t0 == Type.INT) &&
        (t1 == Type.FLOAT || t1 == Type.INT))
    {
        auto f0 = (t0 == Type.FLOAT)? w0.floatVal:cast(float64)w0.intVal;
        auto f1 = (t1 == Type.FLOAT)? w1.floatVal:cast(float64)w1.intVal;

        interp.setSlot(
            instr.outSlot, 
            f0 * f1
        );
    }

    else
    {
        assert (false, "unsupported types in mul");
    }
}

void opDiv(Interp interp, IRInstr instr)
{
    auto idx0 = instr.args[0].localIdx;
    auto idx1 = instr.args[1].localIdx;
    auto w0 = interp.getWord(idx0);
    auto w1 = interp.getWord(idx1);
    auto t0 = interp.getType(idx0);
    auto t1 = interp.getType(idx1);

    auto f0 = (t0 == Type.FLOAT)? w0.floatVal:cast(float64)w0.intVal;
    auto f1 = (t1 == Type.FLOAT)? w1.floatVal:cast(float64)w1.intVal;

    assert (
        (t0 == Type.INT || t0 == Type.FLOAT) ||
        (t1 == Type.INT || t1 == Type.FLOAT),
        "unsupported type in div"
    );

    // TODO: produce NaN or Inf on 0
    if (f1 == 0)
        throw new Error("division by 0");

    interp.setSlot(
        instr.outSlot, 
        f0 / f1
    );
}

void opMod(Interp interp, IRInstr instr)
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

void opTypeOf(Interp interp, IRInstr instr)
{
    auto idx = instr.args[0].localIdx;

    auto w = interp.getWord(idx);
    auto t = interp.getType(idx);

    refptr output;

    switch (t)
    {
        case Type.STRING:
        output = getString(interp, "string");
        break;

        case Type.INT:
        case Type.FLOAT:
        output = getString(interp, "number");
        break;

        case Type.CONST:
        if (w == TRUE)
            output = getString(interp, "boolean");
        else if (w == FALSE)
            output = getString(interp, "boolean");
        else if (w == NULL)
            output = getString(interp, "object");
        else if (w == UNDEF)
            output = getString(interp, "undefined");
        else
            assert (false, "unsupported constant");
        break;

        default:
        assert (false, "unsupported type in typeof");
    }

    interp.setSlot(
        instr.outSlot, 
        Word.ptrv(output),
        Type.STRING
    );
}

void opBoolVal(Interp interp, IRInstr instr)
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

        case Type.REFPTR:
        output = true;
        break;

        default:
        assert (false, "unsupported type in opBoolVal");
    }

    interp.setSlot(
        instr.outSlot, 
        output? TRUE:FALSE,
        Type.CONST
    );
}

void opCmpSe(Interp interp, IRInstr instr)
{
    // TODO: support for other types
    auto idx0 = instr.args[0].localIdx;
    auto idx1 = instr.args[1].localIdx;

    auto w0 = interp.getWord(idx0);
    auto w1 = interp.getWord(idx1);

    bool output = (w0.intVal == w1.intVal);

    writefln("output: %s", output);

    interp.setSlot(
        instr.outSlot, 
        output? TRUE:FALSE,
        Type.CONST
    );
}

void opCmpLt(Interp interp, IRInstr instr)
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
            w0.intVal < w1.intVal
        );
    }

    // If either value is floating-point or integer
    else if (
        (t0 == Type.FLOAT || t0 == Type.INT) &&
        (t1 == Type.FLOAT || t1 == Type.INT))
    {
        auto f0 = (t0 == Type.FLOAT)? w0.floatVal:cast(float64)w0.intVal;
        auto f1 = (t1 == Type.FLOAT)? w1.floatVal:cast(float64)w1.intVal;

        interp.setSlot(
            instr.outSlot, 
            f0 < f1
        );
    }

    else
    {
        assert (false, "unsupported types in mul");
    }
}

void opJump(Interp interp, IRInstr instr)
{
    auto block = instr.args[0].block;
    interp.ip = block.firstInstr;
}

void opJumpTrue(Interp interp, IRInstr instr)
{
    auto valIdx = instr.args[0].localIdx;
    auto block = instr.args[1].block;
    auto wVal = interp.getWord(valIdx);

    if (wVal == TRUE)
        interp.ip = block.firstInstr;
}

void opJumpFalse(Interp interp, IRInstr instr)
{
    auto valIdx = instr.args[0].localIdx;
    auto block = instr.args[1].block;
    auto wVal = interp.getWord(valIdx);

    if (wVal == FALSE)
        interp.ip = block.firstInstr;
}

void opSetArg(Interp interp, IRInstr instr)
{
    auto srcIdx = instr.args[0].localIdx;
    auto dstIdx = -(instr.args[1].intVal + 1);

    auto wArg = interp.getWord(srcIdx);
    auto tArg = interp.getType(srcIdx);

    interp.wsp[dstIdx] = wArg;
    interp.tsp[dstIdx] = tArg;
}

void opCall(Interp interp, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto thisIdx = instr.args[1].localIdx;
    auto numArgs = instr.args[2].intVal;

    auto wThis = interp.getWord(thisIdx);
    auto tThis = interp.getType(thisIdx);

    // Get the function object from the closure
    auto closPtr = interp.getWord(closIdx).ptrVal;
    auto fun = cast(IRFunction)clos_get_fptr(closPtr);

    assert (
        fun !is null, 
        "null IRFunction pointer"
    );

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
    {
        astToIR(fun.ast, fun);
    }

    // Set the caller instruction as the return address
    auto retAddr = cast(rawptr)instr;

    // Push stack space for the arguments
    interp.push(numArgs);

    // Push the hidden call arguments
    interp.push(UNDEF, Type.CONST);                     // FIXME:Closure argument
    interp.push(wThis, tThis);                          // This argument
    interp.push(Word.intv(numArgs), Type.INT);          // Argument count
    interp.push(Word.ptrv(retAddr), Type.RAWPTR);       // Return address

    // Set the instruction pointer
    interp.ip = fun.entryBlock.firstInstr;
}

/// JavaScript new operator (constructor call)
void opCallNew(Interp interp, IRInstr instr)
{
    auto closIdx = instr.args[0].localIdx;
    auto numArgs = instr.args[1].intVal;

    // Get the function object from the closure
    auto closPtr = interp.getWord(closIdx).ptrVal;
    auto fun = cast(IRFunction)clos_get_fptr(closPtr);
    assert (
        fun !is null, 
        "null IRFunction pointer"
    );

    // Lookup the "prototype" property on the closure
    auto protoPtr = getProp(
        interp, 
        closPtr,
        getString(interp, "prototype")
    );

    // Allocate the "this" object
    auto thisPtr = newObj(
        interp, 
        &fun.classPtr, 
        protoPtr.word.ptrVal,
        CLASS_INIT_SIZE,
        2
    );

    // Set the this object pointer in the output slot
    interp.setSlot(
        instr.outSlot, 
        Word.ptrv(thisPtr),
        Type.REFPTR
    );

    // If the function is not yet compiled, compile it now
    if (fun.entryBlock is null)
    {
        astToIR(fun.ast, fun);
    }

    // Set the caller instruction as the return address
    auto retAddr = cast(rawptr)instr;

    // Push stack space for the arguments
    interp.push(numArgs);

    // Push the hidden call arguments
    interp.push(UNDEF, Type.CONST);                     // FIXME:Closure argument
    interp.push(Word.ptrv(thisPtr), Type.REFPTR);       // This argument
    interp.push(Word.intv(numArgs), Type.INT);          // Argument count
    interp.push(Word.ptrv(retAddr), Type.RAWPTR);       // Return address

    // Set the instruction pointer
    interp.ip = fun.entryBlock.firstInstr;
}

/// Allocate/adjust the stack frame on function entry
void opPushFrame(Interp interp, IRInstr instr)
{
    auto numParams = instr.fun.params.length;
    auto numLocals = instr.fun.numLocals;

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

void opRet(Interp interp, IRInstr instr)
{
    auto retSlot   = instr.args[0].localIdx;
    auto raSlot    = instr.fun.raSlot;
    auto numLocals = instr.fun.numLocals;

    // Get the return value
    auto wRet = interp.wsp[retSlot];
    auto tRet = interp.tsp[retSlot];

    // Get the calling instruction
    auto callInstr = cast(IRInstr)interp.getWord(raSlot).ptrVal;

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

        // Pop all local stack slots
        interp.pop(numLocals);

        // Set the instruction pointer to the post-call instruction
        interp.ip = callInstr.next;

        // Leave the return value in the call's return slot
        interp.setSlot(
            callInstr.outSlot, 
            wRet,
            tRet
        );
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

void opNewClos(Interp interp, IRInstr instr)
{
    auto fun = instr.args[0].fun;

    // TODO
    // TODO: num clos cells, can get this from fun object!
    // TODO

    // Allocate the prototype object
    auto objPtr = newObj(
        interp, 
        &instr.args[1].ptrVal, 
        NULL.ptrVal,        // TODO: object proto
        CLASS_INIT_SIZE,
        0
    );

    // Allocate the closure object
    auto closPtr = newClos(
        interp, 
        &instr.args[2].ptrVal, 
        NULL.ptrVal,        // TODO: function proto
        CLASS_INIT_SIZE,
        1,
        0,                  // TODO: num cells
        fun
    );

    // Set the prototype property on the closure object
    setProp(
        interp, 
        closPtr,
        getString(interp, "prototype"),
        ValuePair(Word.ptrv(objPtr), Type.REFPTR)
    );
   
    // Output a pointer to the closure
    interp.setSlot(
        instr.outSlot,
        Word.ptrv(closPtr),
        Type.REFPTR
    );    
}

/// Expression evaluation delegate function
alias refptr delegate(
    Interp interp, 
    refptr classPtr, 
    uint32 allocNumProps
) ObjAllocFn;

refptr newExtObj(
    Interp interp, 
    refptr* ppClass, 
    refptr protoPtr, 
    uint32 classInitSize,
    uint32 allocNumProps,
    ObjAllocFn objAllocFn
)
{
    auto classPtr = *ppClass;

    // If the class is not yet allocated
    if (classPtr is null)
    {
        // Lazily allocate the class
        classPtr = class_alloc(interp, classInitSize);
        class_set_id(classPtr, 0);

        // Update the instruction's class pointer
        *ppClass = classPtr;
    }    
    else
    {
        // Get the number of properties to allocate from the class
        allocNumProps = max(class_get_num_props(classPtr), allocNumProps);
    }

    // Allocate the object
    auto objPtr = objAllocFn(interp, classPtr, allocNumProps);

    // Initialize the object
    obj_set_class(objPtr, classPtr);
    obj_set_proto(objPtr, protoPtr);

    return objPtr;
}

refptr newObj(
    Interp interp, 
    refptr* ppClass, 
    refptr protoPtr, 
    uint32 classInitSize,
    uint32 allocNumProps
)
{
    return newExtObj(
        interp, 
        ppClass, 
        protoPtr, 
        classInitSize,
        allocNumProps,
        delegate refptr(Interp interp, refptr classPtr, uint32 allocNumProps)
        {
            auto objPtr = obj_alloc(interp, allocNumProps);
            return objPtr;
        }
    );
}

refptr newArr(
    Interp interp, 
    refptr* ppClass, 
    refptr protoPtr, 
    uint32 classInitSize,
    uint32 allocNumElems
)
{
    return newExtObj(
        interp, 
        ppClass, 
        protoPtr, 
        classInitSize,
        0,
        delegate refptr(Interp interp, refptr classPtr, uint32 allocNumProps)
        {
            auto objPtr = arr_alloc(interp, allocNumProps);
            auto tblPtr = arrtbl_alloc(interp, allocNumElems);
            arr_set_tbl(objPtr, tblPtr);
            arr_set_len(objPtr, 0);
            return objPtr;
        }
    );
}

refptr newClos(
    Interp interp, 
    refptr* ppClass, 
    refptr protoPtr, 
    uint32 classInitSize,
    uint32 allocNumProps,
    uint32 allocNumCells,
    IRFunction fun
)
{
    return newExtObj(
        interp, 
        ppClass, 
        protoPtr, 
        classInitSize,
        allocNumProps,
        delegate refptr(Interp interp, refptr classPtr, uint32 allocNumProps)
        {
            auto objPtr = clos_alloc(interp, allocNumProps, allocNumCells);
            clos_set_fptr(objPtr, cast(rawptr)fun);
            return objPtr;
        }
    );
}

void setProp(Interp interp, refptr objPtr, refptr propStr, ValuePair val)
{
    // Follow the next link chain
    for (;;)
    {
        auto nextPtr = obj_get_next(objPtr);
        if (nextPtr is null)
            break;
         objPtr = nextPtr;
    }

    // Get the number of class properties
    auto classPtr = obj_get_class(objPtr);
    auto numProps = class_get_num_props(classPtr);

    // Look for the property in the class
    size_t propIdx;
    for (propIdx = 0; propIdx < numProps; ++propIdx)
    {
        auto nameStr = class_get_prop_name(classPtr, propIdx);
        if (propStr == nameStr)
            break;
    }

    // If this is a new property
    if (propIdx == numProps)
    {
        //writefln("new property");

        // TODO: implement class extension
        auto classCap = class_get_cap(classPtr);
        assert (propIdx < classCap, "class capacity exceeded");

        // Set the property name
        class_set_prop_name(classPtr, propIdx, propStr);

        // Increment the number of properties in this class
        class_set_num_props(classPtr, numProps + 1);
    }

    //writefln("num props after write: %s", class_get_num_props(interp.globalClass));
    //writefln("prop idx: %s", propIdx);
    //writefln("intval: %s", wVal.intVal);

    // Get the length of the object
    auto objCap = obj_get_cap(objPtr);

    // If the object needs to be extended
    if (propIdx >= objCap)
    {
        //writeln("*** extending object ***");

        auto objType = obj_get_type(objPtr);

        refptr newObj;

        // Switch on the layout type
        switch (objType)
        {
            case LAYOUT_OBJ:
            newObj = obj_alloc(interp, objCap+1);
            break;

            case LAYOUT_CLOS:
            auto numCells = clos_get_num_cells(objPtr);
            newObj = clos_alloc(interp, objCap+1, numCells);
            clos_set_fptr(newObj, clos_get_fptr(objPtr));
            for (size_t i = 0; i < numCells; ++i)
                clos_set_cell(newObj, i, clos_get_cell(objPtr, i));
            break;

            default:
            assert (false, "unhandled object type");
        }

        obj_set_class(newObj, classPtr);
        obj_set_proto(newObj, obj_get_proto(objPtr));

        // Copy over the property words and types
        for (size_t i = 0; i < objCap; ++i)
        {
            obj_set_word(newObj, i, obj_get_word(objPtr, i));
            obj_set_type(newObj, i, obj_get_type(objPtr, i));
        }

        // Set the next pointer in the old object
        obj_set_next(objPtr, newObj);

        // Update the object pointer
        objPtr = newObj;
    }

    // Set the value and its type in the object
    obj_set_word(objPtr, propIdx, val.word.intVal);
    obj_set_type(objPtr, propIdx, val.type);
}

ValuePair getProp(Interp interp, refptr objPtr, refptr propStr)
{
    // Follow the next link chain
    for (;;)
    {
        auto nextPtr = obj_get_next(objPtr);
        if (nextPtr is null)
            break;
         objPtr = nextPtr;
    }

    // Get the number of class properties
    auto classPtr = obj_get_class(objPtr);
    auto numProps = class_get_num_props(classPtr);

    // Look for the property in the global class
    size_t propIdx;
    for (propIdx = 0; propIdx < numProps; ++propIdx)
    {
        auto nameStr = class_get_prop_name(classPtr, propIdx);
        if (propStr == nameStr)
            break;
    }

    // If the property was not found
    if (propIdx == numProps)
    {
        auto protoPtr = obj_get_proto(objPtr);

        // If the prototype is null, produce undefined
        if (protoPtr is NULL.ptrVal)
            return ValuePair(UNDEF, Type.CONST);

        // Do a recursive lookup on the prototype
        return getProp(
            interp,
            protoPtr,
            propStr
        );
    }

    //writefln("num props after write: %s", class_get_num_props(interp.globalClass));
    //writefln("prop idx: %s", propIdx);

    auto pWord = obj_get_word(objPtr, propIdx);
    auto pType = cast(Type)obj_get_type(objPtr, propIdx);

    return ValuePair(Word.intv(pWord), pType);
}

/**
Set an element of an array
*/
void setArrElem(Interp interp, refptr arr, uint32 index, ValuePair val)
{
    // Get the array length
    auto len = arr_get_len(arr);

    // Get the array table
    auto tbl = arr_get_tbl(arr);

    // If the index is outside the current size of the array
    if (index >= len)
    {
        // Compute the new length
        auto newLen = index + 1;

        //writefln("extending array to %s", newLen);

        // Get the array capacity
        auto cap = arrtbl_get_cap(tbl);

        // If the new length would exceed the capacity
        if (newLen > cap)
        {
            // Compute the new size to resize to
            auto newSize = 2 * cap;
            if (newLen > newSize)
                newSize = newLen;

            // Extend the internal table
            tbl = extArrTable(interp, arr, tbl, len, cap, newSize);
        }

        // Update the array length
        arr_set_len(arr, newLen);
    }

    // Set the element in the array
    arrtbl_set_word(tbl, index, val.word.intVal);
    arrtbl_set_type(tbl, index, val.type);
}

/**
Extend the internal array table of an array
*/
refptr extArrTable(
    Interp interp, 
    refptr arr, 
    refptr curTbl, 
    uint32 curLen, 
    uint32 curSize, 
    uint32 newSize
)
{
    // Allocate the new table without initializing it, for performance
    auto newTbl = arrtbl_alloc(interp, newSize);

    // Copy elements from the old table to the new
    for (uint32 i = 0; i < curLen; i++)
    {
        arrtbl_set_word(newTbl, i, arrtbl_get_word(curTbl, i));
        arrtbl_set_type(newTbl, i, arrtbl_get_type(curTbl, i));
    }

    // Initialize the remaining table entries to undefined
    for (uint32 i = curLen; i < newSize; i++)
    {
        arrtbl_set_word(newTbl, i, UNDEF.intVal);
        arrtbl_set_type(newTbl, i, Type.CONST);
    }

    // Update the table reference in the array
    arr_set_tbl(arr, newTbl);

    return newTbl;
}

/**
Get an element from an array
*/
ValuePair getArrElem(Interp interp, refptr arr, uint32 index)
{
    auto len = arr_get_len(arr);

    //writefln("cur len %s", len);

    if (index >= len)
        return ValuePair(UNDEF, Type.CONST);

    auto tbl = arr_get_tbl(arr);

    return ValuePair(
        Word.intv(arrtbl_get_word(tbl, index)),
        cast(Type)arrtbl_get_type(tbl, index),
    );
}

/// Create a new blank object
void opNewObj(Interp interp, IRInstr instr)
{
    auto numProps = max(instr.args[0].intVal, 2);
    auto ppClass  = &instr.args[1].ptrVal;

    // Allocate the object
    auto objPtr = newObj(
        interp, 
        ppClass, 
        NULL.ptrVal,    // FIXME: object prototype
        CLASS_INIT_SIZE,
        cast(uint)numProps
    );

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(objPtr),
        Type.REFPTR
    );
}

/// Create a new uninitialized array
void opNewArr(Interp interp, IRInstr instr)
{
    auto numElems = max(instr.args[0].intVal, 2);
    auto ppClass  = &instr.args[1].ptrVal;

    // Allocate the array
    auto arrPtr = newArr(
        interp, 
        ppClass, 
        NULL.ptrVal,    // FIXME: array prototype
        CLASS_INIT_SIZE,
        cast(uint)numElems
    );

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(arrPtr),
        Type.REFPTR
    );
}

/// Set an object property value
void opSetProp(Interp interp, IRInstr instr)
{
    auto base = interp.getSlot(instr.args[0].localIdx);
    auto prop = interp.getSlot(instr.args[1].localIdx);
    auto val  = interp.getSlot(instr.args[2].localIdx);

    if (base.type == Type.REFPTR)
    {
        auto objPtr = base.word.ptrVal;
        auto type = obj_get_type(objPtr);

        if (type == LAYOUT_ARR)
        {
            // TODO: toUint32?
            assert (prop.type == Type.INT, "prop type should be int");
            auto index = prop.word.intVal;

            setArrElem(
                interp,
                objPtr,
                cast(uint32)index,
                val
            );
        }
        else
        {
            // TODO: toString
            assert (prop.type == Type.STRING, "prop type should be string");
            auto propStr = prop.word.ptrVal;

            setProp(
                interp,
                objPtr,
                propStr,
                val
            );
        }
    }
    else
    {
        // TODO: handle null, undef base
        // TODO: toObject
        assert (false, "invalid base in setProp");
    }
}

/// Get an object property value
void opGetProp(Interp interp, IRInstr instr)
{
    auto base = interp.getSlot(instr.args[0].localIdx);
    auto prop = interp.getSlot(instr.args[1].localIdx);

    ValuePair val;

    if (base.type == Type.REFPTR)
    {
        auto objPtr = base.word.ptrVal;
        auto type = obj_get_type(objPtr);

        if (type == LAYOUT_ARR)
        {
            // TODO: toUint32?
            assert (prop.type == Type.INT, "prop type should be int");
            auto index = prop.word.intVal;

            val = getArrElem(
                interp,
                objPtr,
                cast(uint32)index
            );
        }
        else
        {
            // TODO: toString
            assert (prop.type == Type.STRING, "prop type should be string");
            auto propStr = prop.word.ptrVal;

            val = getProp(
                interp,
                objPtr,
                propStr
            );
        }
    }
    else
    {
        // TODO: handle null, undef base
        // TODO: toObject
        assert (false, "invalid base in setProp");
    }

    interp.setSlot(
        instr.outSlot,
        val
    );
}

/// Set a global variable
void opSetGlobal(Interp interp, IRInstr instr)
{
    auto prop = interp.getSlot(instr.args[0].localIdx);
    auto val  = interp.getSlot(instr.args[1].localIdx);

    assert (prop.type == Type.STRING, "invalid global property");
    auto propStr = prop.word.ptrVal;

    setProp(
        interp,
        interp.globalObj,
        propStr,
        val
    );
}

/// Get the value of a global variable
void opGetGlobal(Interp interp, IRInstr instr)
{
    auto prop = interp.getSlot(instr.args[0].localIdx);

    assert (prop.type == Type.STRING, "invalid global property");
    auto propStr = prop.word.ptrVal;

    ValuePair val = getProp(
        interp,
        interp.globalObj,
        propStr
    );

    interp.setSlot(
        instr.outSlot,
        val
    );
}

