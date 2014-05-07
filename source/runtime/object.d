/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

module runtime.object;

import std.stdio;
import std.string;
import std.algorithm;
import std.stdint;
import std.typecons;
import ir.ir;
import runtime.vm;
import runtime.layout;
import runtime.string;
import runtime.gc;
import util.id;

/// Prototype property slot index
const uint32_t PROTO_SLOT_IDX = 0;

/// Function pointer property slot index (closures only)
const uint32_t FPTR_SLOT_IDX = 1;

/// Static offset for the function pointer in a closure object
const size_t FPTR_SLOT_OFS = clos_ofs_word(null, FPTR_SLOT_IDX);

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

    this(VM vm, uint32_t minNumProps)
    {
        // Register this map reference in the live set
        vm.mapRefs[cast(void*)this] = this;

        this.nextPropIdx = 0;
        this.minNumProps = minNumProps;

        // FIXME: temporary until proper shape system
        // Reserve hidden slots in all maps for the
        // prototype and function pointer
        reserveSlots(2);
    }

    /// Reserve property slots for private use (hidden)
    private void reserveSlots(uint32_t numSlots)
    {
        if (nextPropIdx != 0)
            return;

        nextPropIdx += numSlots;

        minNumProps += numSlots;

        for (size_t i = 0; i < numSlots; ++i)
            fieldNames ~= null;
    }

    /// Get the number of properties to allocate
    uint32_t numProps() const
    {
        return max(cast(uint32_t)fieldNames.length, minNumProps);
    }

    /// Find or allocate the property index for a given property name string
    uint32_t getPropIdx(wstring propStr, bool allocField = false)
    {
        //writeln("getPropIdx, propStr=", propStr);

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
    uint32_t getPropIdx(refptr jsPropStr, bool allocField = false)
    {
        auto propStr = tempWStr(jsPropStr);

        if (propStr in fields)
            return fields[propStr].idx;

        if (allocField is false)
            return uint32_t.max;

        // Here we copy the temporary string into storage
        // controlled by D, as this string may be stored
        // inside the fields map
        propStr = propStr.dup;

        auto propIdx = nextPropIdx++;
        fields[propStr] = Field(propIdx);
        fieldNames ~= propStr;

        return propIdx;
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

ValuePair newObj(
    VM vm,
    ObjMap map,
    ValuePair proto
)
{
    assert (map !is null);

    // Create a root for the prototype object
    auto protoObj = GCRoot(vm, proto);

    // Allocate the object
    auto objPtr = obj_alloc(vm, map.numProps);

    obj_set_map(objPtr, cast(rawptr)map);

    setProto(objPtr, protoObj.pair);

    return ValuePair(objPtr, Type.OBJECT);
}

ValuePair newClos(
    VM vm,
    ObjMap closMap,
    ValuePair proto,
    uint32_t allocNumCells,
    IRFunction fun
)
{
    assert (closMap !is null);

    // Create a root for the prototype object
    auto protoObj = GCRoot(vm, proto);

    // Register this function in the function reference set
    vm.funRefs[cast(void*)fun] = fun;

    // Allocate the closure object
    auto objPtr = clos_alloc(vm, closMap.numProps, allocNumCells);

    obj_set_map(objPtr, cast(rawptr)closMap);

    setProto(objPtr, protoObj.pair);

    // Set the function pointer
    setFunPtr(objPtr, fun);

    return ValuePair(objPtr, Type.CLOSURE);
}

/**
Set the prototype value for an object
*/
void setProto(refptr objPtr, ValuePair proto)
{
    obj_set_word(objPtr, PROTO_SLOT_IDX, proto.word.uint64Val);
    obj_set_type(objPtr, PROTO_SLOT_IDX, proto.type);
}

/**
Get the prototype value for an object
*/
ValuePair getProto(refptr objPtr)
{
    return ValuePair(
        Word.uint64v(obj_get_word(objPtr, PROTO_SLOT_IDX)),
        cast(Type)obj_get_type(objPtr, PROTO_SLOT_IDX)
    );
}

/**
Set the function pointer on a closure object
*/
void setFunPtr(refptr closPtr, IRFunction fun)
{
    clos_set_word(closPtr, FPTR_SLOT_IDX, cast(uint64_t)cast(rawptr)fun);
    clos_set_type(closPtr, FPTR_SLOT_IDX, cast(uint8)Type.FUNPTR);
}

/**
Get the function pointer from a closure object
*/
IRFunction getFunPtr(refptr closPtr)
{
    return cast(IRFunction)cast(refptr)clos_get_word(closPtr, FPTR_SLOT_IDX);
}

ValuePair getProp(VM vm, ValuePair obj, wstring propStr)
{
    auto objPtr = obj.word.ptrVal;

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
        if (pType != MISSING.type || pWord != MISSING.word)
            return ValuePair(pWord, pType);
    }

    // Get the prototype pointer
    auto proto = getProto(objPtr);

    // If the prototype is null, produce the missing constant
    if (proto is NULL)
        return MISSING;

    // Do a recursive lookup on the prototype
    return getProp(
        vm,
        proto,
        propStr
    );
}

void setProp(VM vm, ValuePair objPair, wstring propStr, ValuePair valPair)
{
    // Follow the next link chain
    for (;;)
    {
        auto nextPtr = obj_get_next(objPair.word.ptrVal);
        if (nextPtr is null)
            break;
        objPair.word.ptrVal = nextPtr;
    }

    auto obj = GCRoot(vm, objPair);
    auto val = GCRoot(vm, valPair);

    // Get the map from the object
    auto map = cast(ObjMap)obj_get_map(obj.word.ptrVal);
    assert (map !is null);

    // Find/allocate the property index in the class
    auto propIdx = map.getPropIdx(propStr, true);

    //writeln("propIdx: ", propIdx);

    // Get the length of the object
    auto objCap = obj_get_cap(obj.ptr);

    // If the object needs to be extended
    if (propIdx >= objCap)
    {
        // Compute the new object capacity
        uint32_t newObjCap = (propIdx < 32)? (propIdx + 1):(2 * propIdx);

        auto objType = obj_get_header(obj.ptr);

        refptr newObj;

        // Switch on the layout type
        switch (objType)
        {
            case LAYOUT_OBJ:
            newObj = obj_alloc(vm, newObjCap);
            break;

            case LAYOUT_CLOS:
            auto numCells = clos_get_num_cells(obj.ptr);
            newObj = clos_alloc(vm, newObjCap, numCells);
            for (uint32_t i = 0; i < numCells; ++i)
                clos_set_cell(newObj, i, clos_get_cell(obj.ptr, i));
            break;

            default:
            assert (false, "unhandled object type");
        }

        obj_set_map(newObj, obj_get_map(obj.ptr));
        setProto(newObj, getProto(obj.ptr));

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
        if (obj.pair == vm.globalObj)
            vm.globalObj = ValuePair(newObj, Type.OBJECT);

        // Update the object pointer
        obj = ValuePair(newObj, Type.OBJECT);

        //writefln("done extending object");
    }

    // Set the value and its type in the object
    obj_set_word(obj.ptr, propIdx, val.word.uint64Val);
    obj_set_type(obj.ptr, propIdx, val.type);
}

