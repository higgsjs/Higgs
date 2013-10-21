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

/**
Class field map
*/
class ClassMap
{
    alias Tuple!(uint32_t, "idx") Field;

    private uint32_t nextPropIdx;

    private Field[wstring] fields;

    this(uint32_t numRsvProps = 0)
    {
        this.nextPropIdx = numRsvProps;
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

        return propIdx;
    }

    /// Get a property index using a string object
    uint32_t getPropIdx(refptr propStr, bool allocField = false)
    {
        return getPropIdx(extractWStr(propStr), allocField);
    }
}

/// Initial object class size
immutable uint32_t CLASS_INIT_SIZE = 128;

/// Maximum class hash table load
immutable uint32_t CLASS_MAX_LOAD_NUM = 3;
immutable uint32_t CLASS_MAX_LOAD_DENOM = 5;

/**
Lazily allocate a class object
*/
refptr getClass(
    Interp interp, 
    refptr classPtr, 
    uint32_t classInitSize,
    uint32_t numRsvProps
)
{
    // If the class is not yet allocated
    if (classPtr is null)
    {
        // Lazily allocate the class
        classPtr = class_alloc(interp, classInitSize);

        // TODO: allocate class IDs
        class_set_id(classPtr, 0);

        // Set the number of pre-reserved property slots
        class_set_num_props(classPtr, numRsvProps);
    }    

    return classPtr;
}

refptr newObj(
    Interp interp, 
    refptr classPtr,
    refptr protoPtr, 
    uint32_t classInitSize,
    uint32_t allocNumProps
)
{
    // Create a root for the prototype object
    auto protoObj = GCRoot(interp, protoPtr);

    // Lazily allocate a class object
    auto classObj = GCRoot(
        interp,
        getClass(
            interp, 
            classPtr, 
            classInitSize,
            0
        )
    );

    auto classNumProps = class_get_num_props(classObj.ptr);
    if (classNumProps > allocNumProps)
        allocNumProps = classNumProps;

    // Allocate the object
    auto objPtr = obj_alloc(interp, allocNumProps);

    // Initialize the object
    obj_set_class(objPtr, classObj.ptr);
    obj_set_proto(objPtr, protoObj.ptr);

    return objPtr;
}

refptr newClos(
    Interp interp, 
    refptr classPtr,
    refptr protoPtr, 
    uint32_t classInitSize,
    uint32_t allocNumProps,
    uint32_t allocNumCells,
    IRFunction fun
)
{
    // Create a root for the prototype object
    auto protoObj = GCRoot(interp, protoPtr);

    // Lazily allocate a class object
    // We reserve one hidden property for the function pointer
    auto classObj = GCRoot(
        interp,
        getClass(
            interp, 
            classPtr, 
            classInitSize,
            1
        )
    );

    // Register this function in the function reference set
    interp.funRefs[cast(void*)fun] = fun;

    auto classNumProps = class_get_num_props(classObj.ptr);
    if (classNumProps > allocNumProps)
        allocNumProps = classNumProps;

    // Allocate the closure object
    auto objPtr = clos_alloc(interp, allocNumProps, allocNumCells);

    // Initialize the object
    obj_set_class(objPtr, classObj.ptr);
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

/**
Find or allocate the property index for a given property name string
*/
uint32_t getPropIdx(Interp interp, refptr classPtr, refptr propStr, refptr objPtr = null)
{
    // Get the size of the property table
    auto tblSize = class_get_cap(classPtr);

    // Get the hash code from the property string
    auto hashCode = str_get_hash(propStr);

    // Get the hash table index for this hash value
    auto hashIndex = hashCode % tblSize;

    // Until the key is found, or a free slot is encountered
    while (true)
    {
        // Get the string value at this hash slot
        auto strVal = class_get_prop_name(classPtr, hashIndex);

        // If this is the string we want
        if (strVal == propStr)
        {
            // Return the associated property index
            return class_get_prop_idx(classPtr, hashIndex);
        }

        // If we have reached an empty slot
        else if (strVal == null)
        {
            // Property not found
            break;
        }

        // Move to the next hash table slot
        hashIndex = (hashIndex + 1) % tblSize;
    }

    // If we are not to allocate new property indices, stop
    if (objPtr is null)
        return uint32.max;

    // Get the number of class properties
    auto numProps = class_get_num_props(classPtr);

    // Set the property name and index
    auto propIdx = numProps;
    class_set_prop_name(classPtr, hashIndex, propStr);
    class_set_prop_idx(classPtr, hashIndex, propIdx);

    // Update the number of class properties
    numProps++;
    class_set_num_props(classPtr, numProps);

    // Test if resizing of the property table is needed
    // numProps > ratio * tblSize
    // numProps > num/denom * tblSize
    // numProps * denom > tblSize * num
    if (numProps * CLASS_MAX_LOAD_DENOM >
        tblSize  * CLASS_MAX_LOAD_NUM)
    {
        // Extend the class
        extClass(interp, classPtr, tblSize, numProps, objPtr);
    }

    return propIdx;
}

void extClass(Interp interp, refptr classPtr, uint32_t curSize, uint32_t numProps, refptr objPtr)
{
    // Protect the class and object references with GC roots
    auto obj = GCRoot(interp, objPtr);
    auto cls = GCRoot(interp, classPtr);

    // Compute the new table size
    auto newSize = curSize * 2 + 1;

    writefln("extending class, old size: %s, new size: %s", curSize, newSize);

    // Allocate a new, larger hash table
    auto newClass = class_alloc(interp, newSize);

    // Set the class id
    class_set_id(newClass, class_get_id(cls.ptr));

    // Set the number of strings stored
    class_set_num_props(newClass, numProps);

    // For each entry in the current table
    for (uint32_t curIdx = 0; curIdx < curSize; curIdx++)
    {
        auto propName = class_get_prop_name(cls.ptr, curIdx);

        // If this slot is empty, skip it
        if (propName == null)
            continue;

        // Get the hash code for the value
        auto valHash = str_get_hash(propName);

        // Get the hash table index for this hash value in the new table
        auto startHashIndex = valHash % newSize;
        auto hashIndex = startHashIndex;

        // Until a free slot is encountered
        while (true)
        {
            // Get the value at this hash slot
            auto propName2 = class_get_prop_name(newClass, hashIndex);

            // If we have reached an empty slot
            if (propName2 == null)
            {
                // Set the corresponding key and value in the slot
                class_set_prop_name(
                    newClass, 
                    hashIndex, 
                    propName
                );
                class_set_prop_idx(
                    newClass, 
                    hashIndex, 
                    class_get_prop_idx(cls.ptr, curIdx)
                );

                // Break out of the loop
                break;
            }

            // Move to the next hash table slot
            hashIndex = (hashIndex + 1) % newSize;

            // Ensure that a free slot was found for this key
            assert (
                hashIndex != startHashIndex,
                "no free slots found in extended hash table"
            );
        }
    }

    // Update the class pointer in the object
    obj_set_class(obj.ptr, newClass);

    //writefln("done extending class");
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

    // Get the class from the object
    auto classPtr = obj_get_class(objPtr);

    // Lookup the property index in the class
    auto propIdx = getPropIdx(interp, classPtr, propStr);

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

    // Get the class from the object
    auto classPtr = obj_get_class(obj.ptr);

    // Find/allocate the property index in the class
    auto propIdx = getPropIdx(interp, classPtr, prop.ptr, obj.ptr);

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
            for (uint32_t i = 0; i < numCells; ++i)
                clos_set_cell(newObj, i, clos_get_cell(obj.ptr, i));
            break;

            default:
            assert (false, "unhandled object type");
        }

        obj_set_class(newObj, obj_get_class(obj.ptr));
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

