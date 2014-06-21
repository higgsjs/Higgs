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
import std.bitmanip;
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

/// Default initial object size
const uint32_t OBJ_INIT_SIZE = 8;

void defObjConsts()
{
    // TODO
}

/**
Value type representation
*/
struct ValType
{
    union
    {
        /// Shape (null if unknown)
        const(ObjShape) shape;

        /// IR function, for function pointers
        IRFunction fun;
    }

    /// Bit field for compact encoding
    mixin(bitfields!(

        /// Type, if known
        Type, "type", 4,

        /// Known type flag
        bool, "knownType", 1,

        /// Padding bits
        uint, "", 3
    ));

    /// Constructor taking a value pair
    this(ValuePair val)
    {
        this.type = val.type;
        this.knownType = true;

        if (this.type is Type.OBJECT ||
            this.type is Type.CLOSURE ||
            this.type is Type.ARRAY)
        {
            // TODO: get IRFunction if fptr
            // TODO: get object shape
            this.shape = null;
        }
    }

    // TODO: union? wait and see if needed

    bool knownShape() const { return shape !is null; }
}

/**
Object shape tree representation.
Each shape defines or redefines a property.
Note: getters/setters allocate two closure slots in an object.
*/
class ObjShape
{
    /// Parent shape in the tree
    const(ObjShape) parent;

    /// Cache of property names to defining shapes, to accelerate lookups
    const(ObjShape)[wstring] propCache;

    /// Name of this property, null if array element property
    wstring propName;

    /// Shape of the getter closure (if getter)
    const(ObjShape) getter;

    /// Shape of the setter closure (if setter)
    const(ObjShape) setter;

    /// Value type, may be unknown
    ValType type;

    /// Property attribute flags
    mixin(bitfields!(

        /// Property writable (not read-only)
        bool, "writable", 1,

        /// Property enumerable
        bool, "enumerable", 1,

        // Property configurable
        bool, "configurable", 1,

        /// Property deleted
        bool, "deleted", 1,

        /// Padding bits
        uint, "", 4
    ));

    /// Index at which this property is stored
    uint32_t slotIdx;

    /// Next slot index to allocate
    uint32_t nextIdx;

    /// Empty shape constructor
    this()
    {
        this.parent = null;
        this.propName = null;
        this.setter = null;
        this.getter = null;
    }

    // TODO: method to define/redefine a property, get a new shape object
    // - want to set type too...
    // - normally, we only call this if we know that a transition is necessary
    // - early on, may call this on every set prop
    //ObjShape setProp(wstring propName, ValType type)

    /**
    Get the shape defining a given property
    */
    const(ObjShape) getDefShape(wstring propName) const
    {
        if (propName == this.propName)
            return this;

        if (parent)
            return parent.getDefShape(propName);

        return null;
    }
}

ValuePair newObj(
    VM vm,
    ValuePair proto,
    uint32_t initSize = OBJ_INIT_SIZE
)
{
    // TODO: hosted newObj, needed for global object, etc.
    /*
    // Create a root for the prototype object
    auto protoObj = GCRoot(vm, proto);

    // Allocate the object
    auto objPtr = obj_alloc(vm, map.numProps);

    obj_set_map(objPtr, cast(rawptr)map);

    setProto(objPtr, protoObj.pair);

    return ValuePair(objPtr, Type.OBJECT);
    */

    assert (false);
}

ValuePair newClos(
    VM vm,
    ValuePair proto,
    uint32_t allocNumCells,
    IRFunction fun
)
{
    // TODO
    assert (false);

    /*
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
    */
}

/**
Set the prototype value for an object
*/
/*
void setProto(refptr objPtr, ValuePair proto)
{
    obj_set_word(objPtr, PROTO_SLOT_IDX, proto.word.uint64Val);
    obj_set_type(objPtr, PROTO_SLOT_IDX, proto.type);
}
*/

/**
Get the prototype value for an object
*/
/*
ValuePair getProto(refptr objPtr)
{
    return ValuePair(
        Word.uint64v(obj_get_word(objPtr, PROTO_SLOT_IDX)),
        cast(Type)obj_get_type(objPtr, PROTO_SLOT_IDX)
    );
}
*/

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
    // TODO: how do we handle getters, want to indicate this?

    // TODO
    assert (false);

    /*
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
    */
}

void setProp(VM vm, ValuePair objPair, wstring propStr, ValuePair valPair)
{
    // TODO: how do we handle setters, want to indicate this?

    // TODO
    assert (false);

    /*
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
    */
}

