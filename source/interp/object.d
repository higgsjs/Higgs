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

module interp.object;

import std.stdio;
import std.string;
import std.algorithm;
import std.stdint;
import std.typecons;
import ir.ir;
import interp.interp;
import interp.layout;
import interp.string;
import interp.gc;
import util.id;

/**
Object field/slot layout map
*/
class ObjMap : IdObject
{
    alias Tuple!(uint32_t, "idx") Field;

    private uint32_t minNumProps;

    private uint32_t nextPropIdx;

    /// Map of field names to field entries
    private Field[wstring] fields;

    /// Map of property indices to field names
    private wstring[] fieldNames;

    this(Interp interp, uint32_t minNumProps)
    {
        // Register this map reference in the live set
        interp.mapRefs[cast(void*)this] = this;

        this.nextPropIdx = 0;
        this.minNumProps = minNumProps;
    }

    /// Reserve property slots for private use (hidden)
    void reserveSlots(uint32_t numSlots)
    {
        if (nextPropIdx != 0)
            return;

        nextPropIdx += numSlots;

        for (size_t i = 0; i < numSlots; ++i)
            fieldNames ~= null;
    }

    /// Get the number of properties to allocate
    uint32_t numProps() const
    {
        return max(cast(uint32_t)fields.length, minNumProps);
    }

    /// Find or allocate the property index for a given property name string
    uint32_t getPropIdx(wstring propStr, bool allocField = false)
    {
        if (propStr in fields)
            return fields[propStr].idx;

        if (allocField is false)
            return uint32_t.max;

        auto propIdx = nextPropIdx++;
        fields[propStr] = Field(propIdx);
        fieldNames ~= propStr;

        return propIdx;
    }

    /// Get a property index using a string object
    uint32_t getPropIdx(refptr propStr, bool allocField = false)
    {
        return getPropIdx(extractWStr(propStr), allocField);
    }

    /// Get the name string for a given property
    wstring getPropName(uint32_t idx)
    {
        assert (idx < numProps);

        if (idx < fieldNames.length)
            return fieldNames[idx];

        return null;
    }
}

refptr newObj(
    Interp interp, 
    ObjMap map,
    refptr protoPtr
)
{
    assert (map !is null);

    // Create a root for the prototype object
    auto protoObj = GCRoot(interp, protoPtr);

    // Allocate the object
    auto objPtr = obj_alloc(interp, map.numProps);

    // Initialize the object
    obj_set_map(objPtr, cast(rawptr)map);
    obj_set_proto(objPtr, protoObj.ptr);

    return objPtr;
}

refptr newClos(
    Interp interp, 
    ObjMap closMap,
    refptr protoPtr,
    uint32_t allocNumCells,
    IRFunction fun
)
{
    assert (closMap !is null);

    // Reserve a hidden slot for the function pointer
    closMap.reserveSlots(1);

    // Create a root for the prototype object
    auto protoObj = GCRoot(interp, protoPtr);

    // Register this function in the function reference set
    interp.funRefs[cast(void*)fun] = fun;

    // Allocate the closure object
    auto objPtr = clos_alloc(interp, closMap.numProps, allocNumCells);

    // Initialize the object
    obj_set_map(objPtr, cast(rawptr)closMap);
    obj_set_proto(objPtr, protoObj.ptr);

    // Set the function pointer
    setClosFun(objPtr, fun);

    return objPtr;
}

/**
Set the function pointer on a closure object
*/
void setClosFun(refptr closPtr, IRFunction fun)
{
    // Write the function pointer in the first property slot
    clos_set_word(closPtr, 0, cast(uint64_t)cast(rawptr)fun);
    clos_set_type(closPtr, 0, cast(uint8)Type.FUNPTR);
}

/**
Get the function pointer from a closure object
*/
IRFunction getClosFun(refptr closPtr)
{
    return cast(IRFunction)cast(refptr)clos_get_word(closPtr, 0);
}

/// Static offset for the function pointer in a closure object
immutable size_t CLOS_OFS_FPTR = clos_ofs_word(null, 0);

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

    // Get the map from the object
    auto map = cast(ObjMap)obj_get_map(objPtr);
    assert (map !is null);

    // Lookup the property index in the class
    auto propIdx = map.getPropIdx(propStr);

    // If the property index was found
    if (propIdx != uint32.max)
    {
        auto pWord = Word.uint64v(obj_get_word(objPtr, propIdx));
        auto pType = cast(Type)obj_get_type(objPtr, propIdx);

        // If the property is not the "missing" value, return it directly
        if (pType != Type.CONST || pWord != MISSING)
            return ValuePair(pWord, pType);
    }

    // Get the prototype pointer
    auto protoPtr = obj_get_proto(objPtr);

    // If the prototype is null, produce the missing constant
    if (protoPtr is null)
        return ValuePair(MISSING, Type.CONST);

    // Do a recursive lookup on the prototype
    return getProp(
        interp,
        protoPtr,
        propStr
    );
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

    // Get the map from the object
    auto map = cast(ObjMap)obj_get_map(objPtr);
    assert (map !is null);

    // Find/allocate the property index in the class
    auto propIdx = map.getPropIdx(prop.ptr, true);

    //writeln("propIdx: ", propIdx);

    // Get the length of the object
    auto objCap = obj_get_cap(obj.ptr);

    // If the object needs to be extended
    if (propIdx >= objCap)
    {
        //writeln("*** extending object ***");

        // Compute the new object capacity
        uint32_t newObjCap = (propIdx < 32)? (propIdx + 1):(2 * propIdx);

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
            for (uint32_t i = 0; i < numCells; ++i)
                clos_set_cell(newObj, i, clos_get_cell(obj.ptr, i));
            break;

            default:
            assert (false, "unhandled object type");
        }

        obj_set_map(newObj, obj_get_map(obj.ptr));
        obj_set_proto(newObj, obj_get_proto(obj.ptr));

        // Copy over the property words and types
        for (uint32_t i = 0; i < objCap; ++i)
        {
            obj_set_word(newObj, i, obj_get_word(obj.ptr, i));
            obj_set_type(newObj, i, obj_get_type(obj.ptr, i));
        }

        // Set the next pointer in the old object
        obj_set_next(obj.ptr, newObj);

        // If this is the global object, update
        // the global object pointer
        if (obj.ptr == interp.globalObj)
            interp.globalObj = newObj;

        // Update the object pointer
        obj = newObj;

        //writefln("done extending object");
    }

    // Set the value and its type in the object
    obj_set_word(obj.ptr, propIdx, val.word.uint64Val);
    obj_set_type(obj.ptr, propIdx, val.type);
}

