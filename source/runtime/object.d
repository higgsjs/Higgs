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

/// Minimum object capacity (number of slots)
const uint32_t OBJ_MIN_CAP = 8;

// Static offset for the word array in an object
const size_t OBJ_WORD_OFS = obj_ofs_word(null, 0);

/// Prototype property slot index
const uint32_t PROTO_SLOT_IDX = 0;

/// Function pointer property slot index (closures only)
const uint32_t FPTR_SLOT_IDX = 1;

/// Static offset for the function pointer in a closure object
const size_t FPTR_SLOT_OFS = clos_ofs_word(null, FPTR_SLOT_IDX);

/// Property attribute type
alias uint8_t PropAttr;

/// Property attribute flag bit definitions
const PropAttr ATTR_CONFIGURABLE    = 1 << 0;
const PropAttr ATTR_WRITABLE        = 1 << 1;
const PropAttr ATTR_ENUMERABLE      = 1 << 2;
const PropAttr ATTR_DELETED         = 1 << 3;
const PropAttr ATTR_GETSET          = 1 << 4;

/// Default property attributes
const PropAttr ATTR_DEFAULT = (
    ATTR_CONFIGURABLE |
    ATTR_WRITABLE |
    ATTR_ENUMERABLE
);

/**
Define object-related runtime constants in a VM instance
*/
void defObjConsts(VM vm)
{
    vm.defRTConst!(OBJ_MIN_CAP);

    vm.defRTConst!(PROTO_SLOT_IDX);
    vm.defRTConst!(FPTR_SLOT_IDX);

    vm.defRTConst!(ATTR_CONFIGURABLE);
    vm.defRTConst!(ATTR_WRITABLE);
    vm.defRTConst!(ATTR_ENUMERABLE);
    vm.defRTConst!(ATTR_DELETED);
    vm.defRTConst!(ATTR_GETSET);
    vm.defRTConst!(ATTR_DEFAULT);
}

/**
Value type representation
*/
struct ValType
{
    union
    {
        /// Shape (null if unknown)
        ObjShape shape;

        /// IR function, for function pointers
        IRFunction fun;
    }

    /// Bit field for compact encoding
    mixin(bitfields!(

        /// Type tag bits, if known
        Type, "typeTag", 4,

        /// Known type flag
        bool, "typeKnown", 1,

        /// Known shape flag
        bool, "shapeKnown", 1,

        /// Padding bits
        uint, "", 2
    ));

    /// Constructor taking a value pair
    this(ValuePair val)
    {
        this.typeTag = val.type;
        this.typeKnown = true;
        this.shapeKnown = false;

        if (isObject(this.typeTag))
        {
            // Get the object shape
            this.shape = cast(ObjShape)obj_get_shape(val.ptr);
        }
        else if (this.typeTag is Type.FUNPTR)
        {
            this.fun = val.word.funVal;
        }
        else
        {
            this.shape = null;
        }
    }

    /// Constructor taking a type tag only
    this(Type typeTag)
    {
        this.typeTag = typeTag;
        this.typeKnown = true;
        this.shape = null;
        this.shapeKnown = false;
    }

    /// Constructor taking a type tag and shape
    this(Type typeTag, ObjShape shape)
    {
        this.typeTag = typeTag;
        this.typeKnown = true;
        this.shape = shape;
        this.shapeKnown = true;
    }

    /**
    Test if this type fits within (is more specific than) another type
    */
    bool isSubType(ValType that)
    {
        if (that.typeKnown)
        {
            if (!this.typeKnown)
                return false;

            if (this.typeTag !is that.typeTag)
                return false;

            if (that.shapeKnown)
            {
                if (!this.shapeKnown)
                    return false;

                if (this.shape !is that.shape)
                    return false;
            }
        }

        return true;
    }
}

/**
Object shape tree representation.
Each shape defines or redefines a property.
*/
class ObjShape
{
    /// Parent shape in the tree
    ObjShape parent;

    /// Property definition transitions, mapped by name, then type
    ObjShape[][ValType][wstring] propDefs;

    /// Cache of property names to defining shapes, to accelerate lookups
    ObjShape[wstring] propCache;

    /// Name of this property, null if array element property
    wstring propName;

    /// Value type, may be unknown
    ValType type;

    /// Property attribute flags
    PropAttr attrs;

    /// Index at which this property is stored
    uint32_t slotIdx;

    /// Empty shape constructor
    this(VM vm)
    {
        // Increment the number of shapes allocated
        stats.numShapes++;

        this.parent = null;

        this.propName = null;
        this.type = ValType();
        this.attrs = 0;

        this.slotIdx = uint32_t.max;
    }

    /// Property definition constructor
    private this(
        VM vm,
        ObjShape parent,
        wstring propName,
        ValType type,
        PropAttr attrs
    )
    {
        // Increment the number of shapes allocated
        stats.numShapes++;

        this.parent = parent;

        this.propName = propName;
        this.type = type;
        this.attrs = attrs;

        this.slotIdx = parent.slotIdx+1;
    }

    /// Test if this shape defines a getter-setter
    bool isGetSet() const { return (attrs & ATTR_GETSET) != 0; }

    /// Test if this shape has a given attribute
    bool writable() const { return (attrs & ATTR_WRITABLE) != 0; }
    bool configurable() const { return (attrs & ATTR_CONFIGURABLE) != 0; }

    /**
    Method to define or redefine a property.
    This may fork the shape tree if redefining a property.
    */
    ObjShape defProp(
        VM vm,
        wstring propName,
        ValType type,
        PropAttr attrs,
        ObjShape defShape
    )
    {
        // Check if a shape object already exists for this definition
        if (propName in propDefs)
        {
            if (type in propDefs[propName])
            {
                foreach (shape; propDefs[propName][type])
                {
                    // If this shape matches, return it
                    if (shape.attrs == attrs)
                        return shape;
                }
            }
        }

        // If this is a new property addition
        if (defShape is null)
        {
            // Create the new shape
            auto newShape = new ObjShape(
                vm,
                defShape? defShape:this,
                propName,
                type,
                attrs
            );

            // Add it to the property definitions
            propDefs[propName][type] ~= newShape;
            assert (propDefs[propName][type].length > 0);

            return newShape;
        }

        // This is redefinition of an existing property
        else
        {
            // Assemble the list of properties added
            // after the original definition shape
            ObjShape[] shapes;
            for (auto shape = this; shape !is defShape; shape = shape.parent)
                shapes ~= shape;

            // Define the property with the same parent
            // as the original shape
            auto curParent = defShape.parent.defProp(
                vm,
                propName,
                type,
                attrs,
                null
            );

            // Redefine all the intermediate properties
            foreach_reverse (shape; shapes)
            {
                curParent = curParent.defProp(
                    vm,
                    shape.propName,
                    shape.type,
                    shape.attrs,
                    null
                );
            }

            // Add the last added shape to the property definitions
            propDefs[propName][type] ~= curParent;
            assert (propDefs[propName][type].length > 0);

            return curParent;
        }
    }

    /**
    Get the shape defining a given property
    */
    ObjShape getDefShape(wstring propName)
    {
        // If there is a cached shape for this property name, return it
        auto cached = propCache.get(propName, null);
        if (cached !is null)
           return cached;

        // For each shape going down the tree, excluding the root
        for (auto shape = this; shape.parent !is null; shape = shape.parent)
        {
            // If the name matches
            if (propName == shape.propName)
            {
                // If the property is deleted, property not found
                if (shape.attrs & ATTR_DELETED)
                    return null;

                // Cache the shape found for this property name
                this.propCache[propName] = shape;

                // Return the shape
                return shape;
            }
        }

        // Root shape reached, property not found
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

    defConst(vm, objPair, "__proto__"w, protoObj.pair);

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

    obj_set_shape(objPair.word.ptrVal, cast(rawptr)vm.emptyShape);

    defConst(vm, objPair, "__proto__"w, protoObj.pair);
    defConst(vm, objPair, "__fptr__"w, ValuePair(fun));

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
    // Get the shape from the object
    auto objShape = cast(ObjShape)obj_get_shape(obj.word.ptrVal);
    assert (objShape !is null);

    // Find the shape defining this property (if it exists)
    auto defShape = objShape.getDefShape(propStr);

    // If the property is defined
    if (defShape !is null)
    {
        uint32_t slotIdx = defShape.slotIdx;
        auto objCap = obj_get_cap(obj.word.ptrVal);

        if (slotIdx < objCap)
        {
            return getSlotPair(obj.word.ptrVal, slotIdx);
        }
        else
        {
            slotIdx -= objCap;
            auto extTbl = obj_get_next(obj.word.ptrVal);
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

void setProp(
    VM vm,
    ValuePair objPair,
    wstring propStr,
    ValuePair valPair,
    PropAttr defAttrs = ATTR_DEFAULT
)
{
    static ValuePair allocExtTbl(VM vm, refptr obj, uint32_t extCap)
    {
        // Get the object layout type
        auto header = obj_get_header(obj);

        // Switch on the layout type
        switch (header)
        {
            case LAYOUT_OBJ:
            return ValuePair(obj_alloc(vm, extCap), Type.OBJECT);

            case LAYOUT_ARR:
            return ValuePair(arr_alloc(vm, extCap), Type.ARRAY);

            case LAYOUT_CLOS:
            auto numCells = clos_get_num_cells(obj);
            return ValuePair(clos_alloc(vm, extCap, numCells), Type.CLOSURE);

            default:
            assert (false, "unhandled object type");
        }
    }

    auto obj = GCRoot(vm, objPair);
    auto val = GCRoot(vm, valPair);

    auto valType = ValType(valPair);

    // Get the shape from the object
    auto objShape = cast(ObjShape)obj_get_shape(obj.word.ptrVal);
    assert (objShape !is null);

    // Find the shape defining this property (if it exists)
    auto defShape = objShape.getDefShape(propStr);

    // If the property is not already defined
    if (defShape is null)
    {
        // Create a new shape for the property
        defShape = objShape.defProp(
            vm,
            propStr,
            valType,
            defAttrs,
            null
        );

        // Set the new shape for the object
        obj_set_shape(obj.ptr, cast(rawptr)defShape);
    }
    else
    {
        // If the property is not writable, do nothing
        if (!defShape.writable)
        {
            //writeln("redefining constant: ", propStr);
            return;
        }

        // TODO: handle type mismatches with defShape
    }

    uint32_t slotIdx = defShape.slotIdx;

    // Get the number of slots in the object
    auto objCap = obj_get_cap(obj.ptr);
    assert (objCap > 0);

    // If the slot is within the object
    if (slotIdx < objCap)
    {
        // Set the value and its type in the object
        setSlotPair(obj.ptr, slotIdx, val.pair);
    }

    // The property is past the object's capacity
    else 
    {
        // Get the extension table pointer
        auto extTbl = GCRoot(vm, obj_get_next(obj.ptr), Type.OBJECT);

        // If the extension table isn't yet allocated
        if (extTbl.ptr is null)
        {
            auto extCap = 2 * objCap;
            extTbl = allocExtTbl(vm, obj.ptr, extCap);
            obj_set_next(obj.ptr, extTbl.ptr);
        }

        auto extCap = obj_get_cap(extTbl.ptr);

        // If the extension table isn't big enough
        if (slotIdx >= extCap)
        {
            auto newExtCap = 2 * extCap;
            auto newExtTbl = allocExtTbl(vm, obj.ptr, newExtCap);

            // Copy over the property words and types
            for (uint32_t i = objCap; i < extCap; ++i)
                setSlotPair(newExtTbl.ptr, i, getSlotPair(extTbl.ptr, i));

            extTbl = newExtTbl;
            obj_set_next(obj.ptr, extTbl.ptr);
        }

        // Set the value and its type in the extension table
        setSlotPair(extTbl.ptr, slotIdx, val.pair);
    }
}

/**
Define a constant on an object
*/
bool defConst(
    VM vm,
    ValuePair objPair,
    wstring propStr,
    ValuePair valPair,
    bool enumerable = false
)
{
    auto objShape = cast(ObjShape)obj_get_shape(objPair.word.ptrVal);
    assert (
        objShape !is null
    );

    auto defShape = objShape.getDefShape(propStr);

    // If the property is already defined, stop
    if (defShape !is null)
    {
        return false;
    }

    setProp(
        vm,
        objPair,
        propStr,
        valPair,
        enumerable? ATTR_ENUMERABLE:0
    );

    return true;
}

/**
Set the attributes for a given property
*/
bool setPropAttrs(
    VM vm,
    ValuePair obj,
    wstring propStr,
    PropAttr attrs
)
{
    // Get the shape from the object
    auto objShape = cast(ObjShape)obj_get_shape(obj.word.ptrVal);
    assert (objShape !is null);

    // Find the shape defining this property (if it exists)
    auto defShape = objShape.getDefShape(propStr);

    // If the property doesn't exist, do nothing
    if (defShape is null)
    {
        return false;
    }

    // If the property is not configurable, do nothing
    if (!(defShape.attrs & ATTR_CONFIGURABLE))
    {
        return false;
    }

    // Redefine the property
    auto newShape = objShape.defProp(
        vm,
        propStr,
        defShape? defShape.type:ValType(),
        attrs,
        defShape
    );

    // Set the new object shape
    obj_set_shape(obj.word.ptrVal, cast(rawptr)newShape);

    // Operation successful
    return true;
}

