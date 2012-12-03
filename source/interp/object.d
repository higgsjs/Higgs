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

module interp.object;

import std.stdio;
import std.string;
import std.algorithm;
import ir.ir;
import interp.interp;
import interp.layout;

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
    // Register this function in the function reference set
    interp.funRefs[cast(void*)fun] = fun;

    //write(interp.funRefs.length);
    //write("\n");

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

/**
Get the property index for a given property name string
*/
uint32 getPropIdx(refptr classPtr, refptr propStr)
{
    // Get the number of class properties
    auto numProps = class_get_num_props(classPtr);

    // Look for the property in the global class
    for (uint32 propIdx = 0; propIdx < numProps; ++propIdx)
    {
        auto nameStr = class_get_prop_name(classPtr, propIdx);
        if (propStr == nameStr)
            return propIdx;
    }

    // Property not found
    return uint32.max;
}

// TODO: use getPropIdx in other prop access functions

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

    // Look for the property in the class
    uint32 propIdx;
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
        if (protoPtr is null)
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
    uint32 propIdx;
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

        auto objType = obj_get_header(objPtr);

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
            for (uint32 i = 0; i < numCells; ++i)
                clos_set_cell(newObj, i, clos_get_cell(objPtr, i));
            break;

            default:
            assert (false, "unhandled object type");
        }

        obj_set_class(newObj, classPtr);
        obj_set_proto(newObj, obj_get_proto(objPtr));

        // Copy over the property words and types
        for (uint32 i = 0; i < objCap; ++i)
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

