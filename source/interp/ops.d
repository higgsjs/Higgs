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
        assert (false, "unsupported type in comparison");
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
        ValuePair(Word.ptrv(closPtr), Type.REFPTR),
        ValuePair(Word.ptrv(getString(interp, "prototype")), Type.STRING)
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
    interp.push(Word.ptrv(thisPtr), Type.REFPTR);       // This argument
    interp.push(Word.intv(numArgs), Type.INT);          // Argument count
    interp.push(Word.ptrv(retAddr), Type.RAWPTR);       // Return address

    // Set the instruction pointer
    interp.ip = fun.entryBlock.firstInstr;
}

/// Allocate/adjust the stack frame on function entry
void opPushFrame(Interp interp, IRInstr instr)
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

void opRet(Interp interp, IRInstr instr)
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

/// Get the callee's return value after a call
void opGetRet(Interp interp, IRInstr instr)
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

/// Get the callee's return value after a constructor call
void opGetRetNew(Interp interp, IRInstr instr)
{
    // Read and pop the value
    auto retVal = interp.getSlot(0);
    interp.pop(1);

    // Get the this value
    auto thisVal = interp.getSlot(instr.args[0].localIdx);

    // If the return value is undefined, output the this object
    auto outVal = (retVal.word == UNDEF)? thisVal:retVal;

    interp.setSlot(
        instr.outSlot,
        outVal
    );
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
        ValuePair(Word.ptrv(closPtr), Type.REFPTR),
        ValuePair(Word.ptrv(getString(interp, "prototype")), Type.STRING),
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
        class_set_num_props(classPtr, 0);
        class_set_next(classPtr, null);

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
    obj_set_next(objPtr, null);
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
            obj_set_next(objPtr, null);
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
            obj_set_next(objPtr, null);
            clos_set_fptr(objPtr, cast(rawptr)fun);
            return objPtr;
        }
    );
}

void setProp(Interp interp, ValuePair obj, ValuePair prop, ValuePair val)
{
    // TODO: handle null, undef as object

    if (obj.type != Type.REFPTR)
        return;

    auto objPtr = obj.word.ptrVal;

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

    // TODO: get string value for name?

    assert (prop.type == Type.STRING, "property name should be a string");
    auto propStr = prop.word.ptrVal;

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
        auto classLen = class_get_len(classPtr);
        assert (propIdx < classLen, "class capacity exceeded");

        // Set the property name
        class_set_prop_name(classPtr, propIdx, propStr);

        // Increment the number of properties in this class
        class_set_num_props(classPtr, numProps + 1);
    }

    //writefln("num props after write: %s", class_get_num_props(interp.globalClass));
    //writefln("prop idx: %s", propIdx);
    //writefln("intval: %s", wVal.intVal);

    // Get the length of the object
    auto objLen = obj_get_len(objPtr);

    // If the object needs to be extended
    if (propIdx >= objLen)
    {
        //writeln("*** extending object ***");

        auto objType = obj_get_type(objPtr);

        refptr newObj;

        // Switch on the layout type
        switch (objType)
        {
            case LAYOUT_OBJ:
            newObj = obj_alloc(interp, objLen+1);
            break;

            case LAYOUT_CLOS:
            auto numCells = clos_get_num_cells(objPtr);
            newObj = clos_alloc(interp, objLen+1, numCells);
            clos_set_fptr(newObj, clos_get_fptr(objPtr));
            for (size_t i = 0; i < numCells; ++i)
                clos_set_cell(newObj, i, clos_get_cell(objPtr, i));
            break;

            default:
            assert (false, "unhandled object type");
        }

        obj_set_class(newObj, classPtr);
        obj_set_next (newObj, null);
        obj_set_proto(newObj, obj_get_proto(objPtr));

        // Copy over the property words and types
        for (size_t i = 0; i < objLen; ++i)
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

ValuePair getProp(Interp interp, ValuePair obj, ValuePair prop)
{
    // TODO: toObject?
    assert (obj.type == Type.REFPTR, "base should have object type");
    auto objPtr = obj.word.ptrVal;

    // Follow the next link chain
    for (;;)
    {
        auto nextPtr = obj_get_next(objPtr);
        if (nextPtr is null)
            break;
         objPtr = nextPtr;
    }

    assert (prop.type == Type.STRING, "string type should be string");
    auto propStr = prop.word.ptrVal;

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
            ValuePair(Word.ptrv(protoPtr), Type.REFPTR),
            prop
        );
    }

    //writefln("num props after write: %s", class_get_num_props(interp.globalClass));
    //writefln("prop idx: %s", propIdx);

    auto pWord = obj_get_word(objPtr, propIdx);
    auto pType = cast(Type)obj_get_type(objPtr, propIdx);

    return ValuePair(Word.intv(pWord), pType);
}

/// Create a new blank object
void opNewObj(Interp interp, IRInstr instr)
{
    auto protoSlot = instr.args[0].localIdx;
    auto numProps  = max(instr.args[1].intVal, 2);
    auto ppClass   = &instr.args[2].ptrVal;

    auto wProto = interp.getWord(protoSlot);

    // Allocate the object
    auto objPtr = newObj(
        interp, 
        ppClass, 
        wProto.ptrVal,
        CLASS_INIT_SIZE,
        2
    );

    interp.setSlot(
        instr.outSlot,
        Word.ptrv(objPtr),
        Type.REFPTR
    );
}

/// Set an object property value
void opSetProp(Interp interp, IRInstr instr)
{
    auto base = interp.getSlot(instr.args[0].localIdx);
    auto prop = interp.getSlot(instr.args[1].localIdx);
    auto val  = interp.getSlot(instr.args[2].localIdx);

    setProp(
        interp,
        base, 
        prop,
        val
    );
}

/// Get an object property value
void opGetProp(Interp interp, IRInstr instr)
{
    auto base = interp.getSlot(instr.args[0].localIdx);
    auto prop = interp.getSlot(instr.args[1].localIdx);

    ValuePair val = getProp(
        interp,
        base,
        prop
    );

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

    setProp(
        interp, 
        ValuePair(Word.ptrv(interp.globalObj), Type.REFPTR),
        prop,
        val
    );
}

/// Get the value of a global variable
void opGetGlobal(Interp interp, IRInstr instr)
{
    auto prop = interp.getSlot(instr.args[0].localIdx);

    ValuePair val = getProp(
        interp,
        ValuePair(Word.ptrv(interp.globalObj), Type.REFPTR),
        prop
    );

    interp.setSlot(
        instr.outSlot,
        val
    );
}

