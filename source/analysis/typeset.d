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

module analysis.typeset;

import std.stdio;
import std.conv;
import std.math;
import std.string;
import std.algorithm;
import interp.interp;
import interp.layout;
import interp.gc;

alias uint TypeFlags;

// Possible type descriptor flags
const FLAG_UNDEF    = 1 << 0;   // May be undefined
const FLAG_MISSING  = 1 << 1;   // Missing property
const FLAG_NULL     = 1 << 2;   // May be null
const FLAG_TRUE     = 1 << 3;   // May be true
const FLAG_FALSE    = 1 << 4;   // May be false
const FLAG_INT      = 1 << 5;   // May be integer
const FLAG_FLOAT    = 1 << 6;   // May be floating-point
const FLAG_STRING   = 1 << 7;   // May be string
const FLAG_OBJECT   = 1 << 8;   // May be string
const FLAG_ARRAY    = 1 << 9;   // May be string
const FLAG_CLOS     = 1 << 10;  // May be closure
const FLAG_CELL     = 1 << 11;  // May be closure cell

// Boolean type flag
const FLAG_BOOL =
    FLAG_TRUE |
    FLAG_FALSE;

// Number type flag
const FLAG_NUMBER =
    FLAG_INT |
    FLAG_FLOAT;

// Extended object (object or array or function)
const FLAG_EXTOBJ =
    FLAG_OBJECT    |
    FLAG_ARRAY     |
    FLAG_CLOS;

// Memory allocated object
const FLAG_MEMOBJ =
    FLAG_EXTOBJ    |
    FLAG_STRING    |
    FLAG_CELL;

// Unknown/any type flag
const FLAG_ANY =
    FLAG_UNDEF    |
    FLAG_NULL     |
    FLAG_TRUE     |
    FLAG_FALSE    |
    FLAG_INT      |
    FLAG_FLOAT    |
    FLAG_STRING   |
    FLAG_OBJECT   |
    FLAG_ARRAY    |
    FLAG_CLOS     |
    FLAG_CELL;

/// Empty/uninferred type flag (before analysis)
const FLAG_EMPTY = 0;

/// Maximum object set size
const MAX_OBJ_SET_SIZE = 4;

/**
Dummy equivalent to GCRoot for non GC'd type sets
*/
struct NoRoot
{
    this(Interp interp, refptr ptr)
    {
        this.ptr = ptr;
    }

    NoRoot* opAssign(NoRoot r)
    {
        ptr = r.ptr;
        return &this;
    }

    NoRoot* opAssign(refptr p)
    {
        ptr = p;
        return &this;
    }

    refptr ptr;
}

/**
Type set representation
*/
struct TypeSet(alias PtrType)
{
    @disable this();

    /**
    Construct a new type set
    */
    this(
        Interp interp, 
        TypeFlags flags = FLAG_EMPTY,
        double rangeMin = 0,
        double rangeMax = 0,
        PtrType[MAX_OBJ_SET_SIZE]* objSet = null
    )
    {
        this.interp = interp;

        this.flags = flags;

        this.rangeMin = rangeMin;
        this.rangeMax = rangeMax;

        for (size_t i = 0; i < this.objSet.length; ++i)
        {
            auto objPtr = (objSet !is null)? (*objSet)[i].ptr:null;
            this.objSet[i] = PtrType(interp, objPtr);
        }

        this.numObjs = 0;
    }

    /**
    Construct a type set from a value
    */
    this(Interp interp, ValuePair val)
    {
        this(interp);

        auto word = val.word;

        // Switch on the value type
        switch (val.type)
        {
            case Type.REFPTR:
            if (word.ptrVal == null)
            {
                flags = FLAG_NULL;
                break;
            }
            this.objSet[0] = word.ptrVal;
            this.numObjs = 1;
            if (valIsLayout(word, LAYOUT_STR))
                flags = FLAG_STRING;
            else if (valIsLayout(word, LAYOUT_OBJ))
                flags = FLAG_OBJECT;
            else if (valIsLayout(word, LAYOUT_ARR))
                flags = FLAG_ARRAY;
            else if (valIsLayout(word, LAYOUT_CLOS))
                flags = FLAG_CLOS;
            else // TODO: misc object type?
                assert (false, "unknown layout type");
            break;

            case Type.CONST:
            if (word == UNDEF)
                flags = FLAG_UNDEF;
            else if (word == TRUE)
                flags = FLAG_TRUE;
            else if (word == FALSE)
                flags = FLAG_FALSE;
            else
                assert (false, "unknown const type");
            break;

            case Type.FLOAT:
            flags = FLAG_INT | FLAG_FLOAT;
            rangeMin = word.floatVal;
            rangeMax = word.floatVal;
            break;

            case Type.INT:
            flags = FLAG_INT;
            rangeMin = word.intVal;
            rangeMax = word.intVal;
            break;

            default:
            assert (false, "unhandled value type");
        }
    }

    /**
    Union another type set into this one
    */
    TypeSetNR unionTmpl(alias RT)(TypeSet!RT that)
    {
        auto flags = this.flags | that.flags;

        double rangeMin;
        double rangeMax;

        NoRoot[MAX_OBJ_SET_SIZE] objSet;
        for (size_t i = 0; i < objSet.length; ++i)
            objSet[i] = null;

        size_t numObjs = 0;

        if (flags & FLAG_NUMBER)
        {
            rangeMin = min(this.rangeMin, that.rangeMin);
            rangeMin = max(this.rangeMax, that.rangeMax);
        }

        if (flags & FLAG_MEMOBJ)
        {
            if (this.numObjs == -1 || that.numObjs == -1)
            {
                numObjs = -1;
            }
            else
            {
                for (int i = 0; i < this.numObjs; ++i)
                {
                    objSet[i] = this.objSet[i].ptr;
                    numObjs += 1;
                }

                OBJ_LOOP:
                for (int i = 0; i < that.numObjs; ++i)
                {
                    auto ptr = that.objSet[i].ptr;

                    for (int j = 0; j < numObjs; ++j)
                        if (objSet[j].ptr == ptr)
                            continue OBJ_LOOP;

                    if (numObjs == objSet.length)
                    {
                        for (int k = 0; k < numObjs; ++k)
                            objSet[i] = null;
                        numObjs = -1;
                        break OBJ_LOOP;
                    }

                    objSet[i] = ptr;
                    numObjs += 1;
                }
            }
        }

        return TypeSet!NoRoot(
            interp,
            flags,
            rangeMin,
            rangeMax,
            &objSet
        );
    }

    TypeSet!NoRoot unionSet(TypeSet!NoRoot that) { return unionTmpl!NoRoot(that); }
    TypeSet!NoRoot unionSet(TypeSet!GCRoot that) { return unionTmpl!GCRoot(that); }

    /**
    Assign the value of another type set into this one
    */
    TypeSet* assign(alias RT)(TypeSet!RT that)
    {
        flags = that.flags;

        rangeMin = that.rangeMin;
        rangeMax = that.rangeMax;

        for (size_t i = 0; i < objSet.length; ++i)
            objSet[i] = that.objSet[i].ptr;

        return &this;
    }

    TypeSet* opAssign(TypeSet!NoRoot that) { return assign!NoRoot(that); }
    TypeSet* opAssign(TypeSet!GCRoot that) { return assign!GCRoot(that); }

    /**
    Compare with another type set for equivalence
    */
    bool equals(alias RT)(TypeSet!RT that)
    {
        if (this.flags != that.flags)
            return false;

        if (flags & FLAG_NUMBER)
        {
            if (this.rangeMin != that.rangeMin)
                return false;
            if (this.rangeMax != that.rangeMax)
                return false;
        }

        if (flags & FLAG_MEMOBJ)
        {
            OBJ_LOOP:
            for (size_t i = 0; i < this.objSet.length; ++i)
            {
                auto ptr = this.objSet[i].ptr;
                for (size_t j = 0; j < that.objSet.length; ++j)
                    if (that.objSet[i].ptr == ptr)
                        continue OBJ_LOOP;
            }

        }

        return true;
    }

    bool opEquals(TypeSet!NoRoot that) { return equals!NoRoot(that); }
    bool opEquals(TypeSet!GCRoot that) { return equals!GCRoot(that); }

    /**
    Produce a string representation of the type set
    */
    string toString()
    {
        string output;

        output ~= "{";

        auto flags = this.flags;

        for (size_t i = 0; i < TypeFlags.sizeof * 8; ++i)
        {
            auto flag = (1 << i);

            if (flags & flag)
                continue;

            switch (flag)
            {
                case FLAG_UNDEF     : output ~= "undef"; break;
                case FLAG_MISSING   : output ~= "missing"; break;
                case FLAG_NULL      : output ~= "null"; break;
                case FLAG_TRUE      : output ~= "true"; break;
                case FLAG_FALSE     : output ~= "false"; break;
                case FLAG_INT       : output ~= "int"; break;
                case FLAG_FLOAT     : output ~= "float"; break;
                case FLAG_STRING    : output ~= "string"; break;
                case FLAG_OBJECT    : output ~= "object"; break;
                case FLAG_ARRAY     : output ~= "array"; break;
                case FLAG_CLOS      : output ~= "clos"; break;
                case FLAG_CELL      : output ~= "cell"; break;

                default:
                assert (false, "unhandled type flag");
            }
        }

        if (flags & FLAG_NUMBER)
        {
            output ~= "[";
            output ~= to!string(rangeMin);
            output ~= ",";
            output ~= to!string(rangeMax);
            output ~= "]";
        }

        // TODO: string, object
        if (flags & FLAG_MEMOBJ)
        {

        }

        output ~= "}";

        return output;
    }

    /// Associated interpreter
    private Interp interp;

    /// Type flags
    TypeFlags flags;

    /// Numerical range minimum
    double rangeMin;

    /// Numerical range maximum
    double rangeMax;

    /// Object set (size limited)
    PtrType[MAX_OBJ_SET_SIZE] objSet;

    /// Number of objects stored
    int numObjs;
}

alias TypeSet!GCRoot TypeSetGC;
alias TypeSet!NoRoot TypeSetNR;

/**
Type monitor object, monitors a field or variable type
*/
class TypeMon
{
    this(Interp interp)
    {
        this.interp = interp;

        this.type = TypeSetGC(interp);
    }

    /// Union a value type into this type
    void unionVal(ValuePair val)
    {
        // Create a type set representing the new value
        auto valType = TypeSetNR(interp, val);

        // Union the value type with the local type
        auto newType = type.unionSet(valType);

        // Check if changed, if so, check observations
        if (type != newType)
        {
            // TODO: check observations
        }
    }

    // TODO: have these functions return booleans?
    // TODO
    //void obsvIsInt(trace)
    //{
    //}

    //void obsvIntConst(trace)
    //{
    //}

    // TODO: store list of observation objects, with list of observer traces?
    // observation.check ?
    // List of type observations
    //private TypeObsv[] obsvs;

    /// Associated interpreter
    private Interp interp;

    /// Internal type representation
    private TypeSetGC type;
}

