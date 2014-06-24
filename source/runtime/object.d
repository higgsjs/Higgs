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

/// Minimum object capacity (number of slots)
const uint32_t OBJ_MIN_CAP = 8;

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

    bool knownShape() const { return shape !is null; }

    /**
    Test if this type fits within (is more specific than) another type
    */
    bool isSubType(ValType that)
    {
        if (that.knownType)
        {
            if (!this.knownType)
                return false;

            if (this.type !is that.type)
                return false;

            if (that.knownShape)
            {
                if (!this.knownShape)
                    return false;

                if (this.knownShape !is that.knownShape)
                    return false;
            }
        }

        return true;
    }

    // TODO: union? wait and see if needed
}

/**
Object shape tree representation.
Each shape defines or redefines a property.
*/
class ObjShape
{
    /// Parent shape in the tree
    const(ObjShape) parent;

    // TODO
    /// Cache of property names to defining shapes, to accelerate lookups
    //const(ObjShape)[wstring] propCache;

    /// Name of this property, null if array element property
    wstring propName;

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

    /// Sub-shape transitions, mapped by prop name, then prop type
    const(ObjShape)[][ValType][wstring] subShapes;

    /// Empty shape constructor
    this()
    {
        this.parent = null;
        this.propName = null;

        this.slotIdx = uint32_t.max;
        this.nextIdx = 0;
    }

    /// Property definition constructor
    private this(
        const(ObjShape) parent,
        wstring propName,
        ValType type
    )
    {
        this.parent = parent;
        this.propName = propName;

        this.type = type;

        this.slotIdx = parent.nextIdx;
        this.nextIdx = this.slotIdx + 1;
    }

    /// Test if this shape defines a getter-setter
    bool isGetSet() const { return type.knownType && type.type is Type.GETSET; }

    /**
    Method to define or redefine a property.
    Either finds an existing sub-shape or create one.
    */
    const(ObjShape) defProp(wstring propName, ValType type)
    {
        if (propName in subShapes)
        {
            if (type in subShapes[propName])
            {
                foreach (shape; subShapes[propName][type])
                {
                    // If this shape matches, return it
                    if (shape.writable is true &&
                        shape.enumerable is true &&
                        shape.configurable is true &&
                        shape.deleted is false)
                        return shape;
                }
            }
        }

        // Create the new shape
        auto newShape = new ObjShape(this, propName, type);

        // Add it to the sub-shapes
        subShapes[propName][type] ~= newShape;
        assert (subShapes[propName][type].length > 0);

        return newShape;
    }

    /**
    Get the shape defining a given property
    */
    const(ObjShape) getDefShape(wstring propName) const
    {
        // TODO: propCache? should only store at lookup point
        // need hidden lookup start shape arg?

        writeln("propName: ", propName);
        writeln("  this.propName: ", this.propName);

        // If the name matches, and this is not the root empty shape
        if (propName == this.propName)
        {
            if (this.deleted || this.parent is null)
                return null;

            return this;
        }

        if (parent !is null)
        {
            return parent.getDefShape(propName);
        }

        return null;
    }
}

ValuePair newObj(
    VM vm,
    ValuePair proto,
    uint32_t initCap = OBJ_MIN_CAP
)
{
    assert (initCap >= OBJ_MIN_CAP);

    // Create a root for the prototype object
    auto protoObj = GCRoot(vm, proto);

    // Allocate the object
    auto objPtr = obj_alloc(vm, initCap);
    auto objPair = ValuePair(objPtr, Type.OBJECT);

    obj_set_shape(objPtr, cast(rawptr)vm.emptyShape);

    setProp(vm, objPair, "__proto__"w, protoObj.pair);

    return objPair;
}

ValuePair newClos(
    VM vm,
    ValuePair proto,
    uint32_t allocNumCells,
    IRFunction fun
)
{
    // Create a root for the prototype object
    auto protoObj = GCRoot(vm, proto);

    // Register this function in the function reference set
    vm.funRefs[cast(void*)fun] = fun;

    // Allocate the closure object
    auto objPtr = clos_alloc(vm, OBJ_MIN_CAP, allocNumCells);
    auto objPair = ValuePair(objPtr, Type.CLOSURE);

    obj_set_shape(objPtr, cast(rawptr)vm.emptyShape);

    setProp(vm, objPair, "__proto__"w, protoObj.pair);

    setProp(vm, objPair, "__fptr__"w, ValuePair(fun));

    return objPair;
}

/**
Get the function pointer from a closure object
*/
IRFunction getFunPtr(refptr closPtr)
{
    return cast(IRFunction)cast(refptr)clos_get_word(closPtr, FPTR_SLOT_IDX);
}

ValuePair getSlotPair(refptr objPtr, uint32_t slotIdx)
{
    auto pWord = Word.uint64v(obj_get_word(objPtr, slotIdx));
    auto pType = cast(Type)obj_get_type(objPtr, slotIdx);
    return ValuePair(pWord, pType);
}

void setSlotPair(refptr objPtr, uint32_t slotIdx, ValuePair val)
{
    obj_set_word(objPtr, slotIdx, val.word.uint64Val);
    obj_set_type(objPtr, slotIdx, val.type);
}

ValuePair getProp(VM vm, ValuePair obj, wstring propStr)
{
    writeln("is global: ", obj == vm.globalObj);
    writeln("prop name: ", propStr);

    assert (obj_get_cap(obj.word.ptrVal) > 0);

    // Get the shape from the object
    auto objShape = cast(const(ObjShape))obj_get_shape(obj.word.ptrVal);
    assert (objShape !is null);

    // Find the shape defining this property (if it exists)
    auto defShape = objShape.getDefShape(propStr);

    // If the property is defined
    if (defShape !is null)
    {
        uint32_t slotIdx = defShape.slotIdx;
        auto objCap = obj_get_cap(obj.word.ptrVal);

        writeln("slotIdx: ", slotIdx);
        writeln("objCap: ", objCap);

        if (slotIdx < objCap)
        {
            return getSlotPair(obj.word.ptrVal, slotIdx);
        }
        else
        {
            slotIdx -= objCap;
            auto extTbl = obj_get_next(obj.word.ptrVal);
            writeln("extTbl: ", extTbl);
            assert (slotIdx < obj_get_cap(extTbl));
            return getSlotPair(extTbl, slotIdx);
        }
    }

    // Get the prototype pointer
    auto proto = getProp(vm, obj, "__proto__"w);

    // If the prototype is null, produce the undefined constant
    if (proto is NULL)
        return UNDEF;

    // Do a recursive lookup on the prototype
    return getProp(
        vm,
        proto,
        propStr
    );
}

ValuePair setProp(VM vm, ValuePair objPair, wstring propStr, ValuePair valPair)
{
    auto obj = GCRoot(vm, objPair);
    auto val = GCRoot(vm, valPair);

    // Get the shape from the object
    auto objShape = cast(ObjShape)obj_get_shape(obj.word.ptrVal);
    assert (objShape !is null);

    // Find the shape defining this property (if it exists)
    auto defShape = objShape.getDefShape(propStr);

    auto valType = ValType(valPair);

    // If the property is not defined
    if (defShape is null)
    {
        const(ObjShape) newShape = objShape.defProp(
            propStr,
            valType
        );

        obj_set_shape(obj.ptr, cast(rawptr)newShape);

        return setProp(vm, obj.pair, propStr, valPair);
    }

    // TODO: handle type mismatches with defShape

    uint32_t slotIdx = defShape.slotIdx;

    // Get the number of slots in the object
    auto objCap = obj_get_cap(obj.ptr);
    assert (objCap > 0);

    // If the slot is within the object
    if (slotIdx < objCap)
    {
        // If the property is a getter-setter
        if (defShape.isGetSet)
        {
            // Return the getter-setter object
            return getSlotPair(obj.ptr, slotIdx);
        }
        else
        {
            // Set the value and its type in the object
            setSlotPair(obj.ptr, slotIdx, val.pair);
            return NULL;
        }
    }

    // The property is past the object's capacity
    else 
    {
        assert (false, "extending object");

        slotIdx -= objCap;

        // Get the extension table pointer
        auto extTbl = GCRoot(vm, obj_get_next(obj.ptr), Type.OBJECT);

        // If the extension table isn't yet allocated
        if (extTbl.ptr is null)
        {
            extTbl = ValuePair(obj_alloc(vm, objCap), Type.OBJECT);
            obj_set_next(obj.ptr, extTbl.ptr);
        }

        auto extCap = obj_get_cap(extTbl.ptr);

        // If the extension table isn't big enough
        if (slotIdx >= extCap)
        {
            uint32_t newExtCap = 2 * extCap;
            auto newExtTbl = obj_alloc(vm, newExtCap);

            // Copy over the property words and types
            for (uint32_t i = 0; i < extCap; ++i)
                setSlotPair(newExtTbl, i, getSlotPair(extTbl.ptr, i));

            extTbl = ValuePair(newExtTbl, Type.OBJECT);
            obj_set_next(obj.ptr, extTbl.ptr);
        }

        // If the property is a getter-setter
        if (defShape.isGetSet)
        {
            // Return the getter-setter object
            return getSlotPair(extTbl.ptr, slotIdx);
        }
        else
        {
            // Set the value and its type in the extension table
            setSlotPair(extTbl.ptr, slotIdx, val.pair);
            return NULL;
        }
    }
}

