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

module interp.object;

import std.stdio;
import std.string;
import std.algorithm;
import ir.ir;
import interp.interp;
import interp.layout;
import interp.gc;

/// Expression evaluation delegate function
alias refptr delegate(
    Interp interp, 
    refptr classPtr, 
    uint32 allocNumProps
) ObjAllocFn;

refptr newExtObj(
    Interp interp, 
    refptr classPtr,
    refptr protoPtr, 
    uint32 classInitSize,
    uint32 allocNumProps,
    ObjAllocFn objAllocFn
)
{
    auto protoObj = GCRoot(interp, protoPtr);
    auto classObj = GCRoot(interp, classPtr);

    // If the class is not yet allocated
    if (classObj.ptr is null)
    {
        // Lazily allocate the class
        classObj = class_alloc(interp, classInitSize);
        class_set_id(classObj.ptr, 0);
    }    
    else
    {
        // Get the number of properties to allocate from the class
        allocNumProps = max(class_get_num_props(classObj.ptr), allocNumProps);
    }

    // Allocate the object
    auto obj = GCRoot(
        interp,
        objAllocFn(interp, classObj.ptr, allocNumProps)
    );

    // Initialize the object
    obj_set_class(obj.ptr, classObj.ptr);
    obj_set_proto(obj.ptr, protoObj.ptr);

    return obj.ptr;
}

refptr newObj(
    Interp interp, 
    refptr classPtr,
    refptr protoPtr, 
    uint32 classInitSize,
    uint32 allocNumProps
)
{
    return newExtObj(
        interp, 
        classPtr, 
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

refptr newClos(
    Interp interp, 
    refptr classPtr,
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
        classPtr, 
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

    //writefln("prop idx: %s", propIdx);

    auto pWord = obj_get_word(objPtr, propIdx);
    auto pType = cast(Type)obj_get_type(objPtr, propIdx);

    return ValuePair(Word.intv(pWord), pType);
}

void setProp(Interp interp, refptr objPtr, refptr propStr, ValuePair valPair)
{
    auto obj  = GCRoot(interp, objPtr);
    auto prop = GCRoot(interp, propStr);
    auto val  = GCRoot(interp, valPair);

    // Follow the next link chain
    for (;;)
    {
        auto nextPtr = obj_get_next(obj.ptr);
        if (nextPtr is null)
            break;
         obj = nextPtr;
    }

    // Get the number of class properties
    auto classPtr = obj_get_class(obj.ptr);
    auto numProps = class_get_num_props(classPtr);

    // Look for the property in the class
    uint32 propIdx;
    for (propIdx = 0; propIdx < numProps; ++propIdx)
    {
        auto nameStr = class_get_prop_name(classPtr, propIdx);
        if (prop.ptr == nameStr)
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
        class_set_prop_name(classPtr, propIdx, prop.ptr);

        // Increment the number of properties in this class
        class_set_num_props(classPtr, numProps + 1);
    }

    //writefln("prop idx: %s", propIdx);
    //writefln("intval: %s", wVal.intVal);

    // Get the length of the object
    auto objCap = obj_get_cap(obj.ptr);

    // If the object needs to be extended
    if (propIdx >= objCap)
    {
        //writeln("*** extending object ***");

        auto objType = obj_get_header(obj.ptr);

        refptr newObj;

        // Switch on the layout type
        switch (objType)
        {
            case LAYOUT_OBJ:
            newObj = obj_alloc(interp, objCap+1);
            break;

            case LAYOUT_CLOS:
            auto numCells = clos_get_num_cells(obj.ptr);
            newObj = clos_alloc(interp, objCap+1, numCells);
            clos_set_fptr(newObj, clos_get_fptr(obj.ptr));
            for (uint32 i = 0; i < numCells; ++i)
                clos_set_cell(newObj, i, clos_get_cell(obj.ptr, i));
            break;

            default:
            assert (false, "unhandled object type");
        }

        obj_set_class(newObj, classPtr);
        obj_set_proto(newObj, obj_get_proto(obj.ptr));

        // Copy over the property words and types
        for (uint32 i = 0; i < objCap; ++i)
        {
            obj_set_word(newObj, i, obj_get_word(obj.ptr, i));
            obj_set_type(newObj, i, obj_get_type(obj.ptr, i));
        }

        // Set the next pointer in the old object
        obj_set_next(obj.ptr, newObj);

        // Update the object pointer
        obj = newObj;
    }

    // Set the value and its type in the object
    obj_set_word(obj.ptr, propIdx, val.word.intVal);
    obj_set_type(obj.ptr, propIdx, val.type);
}

