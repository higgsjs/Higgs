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
immutable TypeFlags TYPE_UNDEF    = 1 << 0;   // May be undefined
immutable TypeFlags TYPE_MISSING  = 1 << 1;   // Missing property
immutable TypeFlags TYPE_NULL     = 1 << 2;   // May be null
immutable TypeFlags TYPE_TRUE     = 1 << 3;   // May be true
immutable TypeFlags TYPE_FALSE    = 1 << 4;   // May be false
immutable TypeFlags TYPE_INT      = 1 << 5;   // May be integer
immutable TypeFlags TYPE_FLOAT    = 1 << 6;   // May be floating-point
immutable TypeFlags TYPE_STRING   = 1 << 7;   // May be string
immutable TypeFlags TYPE_OBJECT   = 1 << 8;   // May be string
immutable TypeFlags TYPE_ARRAY    = 1 << 9;   // May be string
immutable TypeFlags TYPE_CLOS     = 1 << 10;  // May be closure
immutable TypeFlags TYPE_CELL     = 1 << 11;  // May be closure cell

// Boolean type flag
immutable TypeFlags TYPE_BOOL =
    TYPE_TRUE |
    TYPE_FALSE;

// Number type flag
immutable TypeFlags TYPE_NUMBER =
    TYPE_INT |
    TYPE_FLOAT;

// Extended object (object or array or function)
immutable TypeFlags TYPE_EXTOBJ =
    TYPE_OBJECT    |
    TYPE_ARRAY     |
    TYPE_CLOS;

// Memory allocated object
immutable TypeFlags TYPE_MEMOBJ =
    TYPE_EXTOBJ    |
    TYPE_STRING    |
    TYPE_CELL;

// Unknown/any type flag
immutable TypeFlags TYPE_ANY =
    TYPE_UNDEF    |
    TYPE_NULL     |
    TYPE_TRUE     |
    TYPE_FALSE    |
    TYPE_INT      |
    TYPE_FLOAT    |
    TYPE_STRING   |
    TYPE_OBJECT   |
    TYPE_ARRAY    |
    TYPE_CLOS     |
    TYPE_CELL;

/// Empty/uninferred type flag (before analysis)
immutable TypeFlags TYPE_EMPTY = 0;

/// Maximum object set size
immutable TypeFlags MAX_OBJ_SET_SIZE = 4;

/**
Type set representation
*/
struct TypeSet
{
    @disable this();

    /**
    Construct a new type set
    */
    this(
        Interp interp, 
        TypeFlags flags = TYPE_EMPTY,
        double rangeMin = 0,
        double rangeMax = 0,
        refptr[MAX_OBJ_SET_SIZE]* objSet = null
    )
    {
        this.interp = interp;

        // Add this type set to the linked list
        this.prev = null;
        this.next = interp.firstSet;
        interp.firstSet = &this;

        this.flags = flags;

        this.rangeMin = rangeMin;
        this.rangeMax = rangeMax;

        for (size_t i = 0; i < this.objSet.length; ++i)
            this.objSet[i] = (objSet !is null)? (*objSet)[i]:null;

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
                flags = TYPE_NULL;
                break;
            }
            this.objSet[0] = word.ptrVal;
            this.numObjs = 1;
            if (valIsLayout(word, LAYOUT_STR))
                flags = TYPE_STRING;
            else if (valIsLayout(word, LAYOUT_OBJ))
                flags = TYPE_OBJECT;
            else if (valIsLayout(word, LAYOUT_ARR))
                flags = TYPE_ARRAY;
            else if (valIsLayout(word, LAYOUT_CLOS))
                flags = TYPE_CLOS;
            else // TODO: misc object type?
                assert (false, "unknown layout type");
            break;

            case Type.CONST:
            if (word == UNDEF)
                flags = TYPE_UNDEF;
            else if (word == TRUE)
                flags = TYPE_TRUE;
            else if (word == FALSE)
                flags = TYPE_FALSE;
            else
                assert (false, "unknown const type");
            break;

            case Type.FLOAT:
            flags = TYPE_INT | TYPE_FLOAT;
            rangeMin = word.floatVal;
            rangeMax = word.floatVal;
            break;

            case Type.INT32:
            flags = TYPE_INT;
            rangeMin = word.int32Val;
            rangeMax = word.int32Val;
            break;

            default:
            assert (false, "unhandled value type");
        }
    }

    /**
    Destroy this type set
    */
    ~this()
    {
        assert (
            interp !is null,
            "interp is null"
        );

        if (prev)
            prev.next = next;
        else
            this.interp.firstSet = next;

        if (next)
            next.prev = prev;
    }

    /**
    Union with another type set
    */
    TypeSet unionSet(TypeSet that)
    {
        auto flags = this.flags | that.flags;

        double rangeMin;
        double rangeMax;

        refptr[MAX_OBJ_SET_SIZE] objSet;
        for (size_t i = 0; i < objSet.length; ++i)
            objSet[i] = null;

        size_t numObjs = 0;

        if (flags & TYPE_NUMBER)
        {
            rangeMin = min(this.rangeMin, that.rangeMin);
            rangeMin = max(this.rangeMax, that.rangeMax);
        }

        if (flags & TYPE_MEMOBJ)
        {
            if (this.numObjs == -1 || that.numObjs == -1)
            {
                numObjs = -1;
            }
            else
            {
                for (int i = 0; i < this.numObjs; ++i)
                {
                    objSet[i] = this.objSet[i];
                    numObjs += 1;
                }

                OBJ_LOOP:
                for (int i = 0; i < that.numObjs; ++i)
                {
                    auto ptr = that.objSet[i];

                    for (int j = 0; j < numObjs; ++j)
                        if (objSet[j] == ptr)
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

        return TypeSet(
            interp,
            flags,
            rangeMin,
            rangeMax,
            &objSet
        );
    }

    /**
    Assign the value of another type set into this one
    */
    TypeSet* opAssign(TypeSet that)
    {
        flags = that.flags;

        rangeMin = that.rangeMin;
        rangeMax = that.rangeMax;

        for (size_t i = 0; i < objSet.length; ++i)
            objSet[i] = that.objSet[i];

        return &this;
    }

    /**
    Compare with another type set for equivalence
    */
    bool opEquals(TypeSet that)
    {
        if (this.flags != that.flags)
            return false;

        if (flags & TYPE_NUMBER)
        {
            if (this.rangeMin != that.rangeMin)
                return false;
            if (this.rangeMax != that.rangeMax)
                return false;
        }

        if (flags & TYPE_MEMOBJ)
        {
            OBJ_LOOP:
            for (size_t i = 0; i < this.numObjs; ++i)
            {
                auto ptr = this.objSet[i];
                for (size_t j = 0; j < that.numObjs; ++j)
                    if (that.objSet[i] == ptr)
                        continue OBJ_LOOP;
            }

        }

        return true;
    }

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
                case TYPE_UNDEF     : output ~= "undef"; break;
                case TYPE_MISSING   : output ~= "missing"; break;
                case TYPE_NULL      : output ~= "null"; break;
                case TYPE_TRUE      : output ~= "true"; break;
                case TYPE_FALSE     : output ~= "false"; break;
                case TYPE_INT       : output ~= "int"; break;
                case TYPE_FLOAT     : output ~= "float"; break;
                case TYPE_STRING    : output ~= "string"; break;
                case TYPE_OBJECT    : output ~= "object"; break;
                case TYPE_ARRAY     : output ~= "array"; break;
                case TYPE_CLOS      : output ~= "clos"; break;
                case TYPE_CELL      : output ~= "cell"; break;

                default:
                assert (false, "unhandled type flag");
            }
        }

        if (flags & TYPE_NUMBER)
        {
            output ~= "[";
            output ~= to!string(rangeMin);
            output ~= ",";
            output ~= to!string(rangeMax);
            output ~= "]";
        }

        if (flags & TYPE_MEMOBJ)
        {
            for (size_t i = 0; i < this.numObjs; ++i)
            {
                auto objPtr = this.objSet[i];
                auto word = Word.ptrv(objPtr);

                if (valIsLayout(word, LAYOUT_STR))
                {
                    output ~= valToString(ValuePair(word, Type.REFPTR));
                }
                else
                {
                    // TODO: source location, class id???
                }
            }
        }

        output ~= "}";

        return output;
    }

    // TODO: have these functions return booleans?
    // TODO
    //void obsvIsInt32(trace)
    //{
    //}

    //void obsvIntConst(trace)
    //{
    //}

    /// Associated interpreter
    private Interp interp;

    /// Linked list pointers, type sets contain 
    /// heap refs and must be tracked by the GC
    TypeSet* prev;
    TypeSet* next;

    /// Owner JS class, if applicable
    refptr ownerClass = null;

    /// Type flags
    TypeFlags flags;

    /// Numerical range minimum
    double rangeMin;

    /// Numerical range maximum
    double rangeMax;

    /// Object set (size limited)
    refptr[MAX_OBJ_SET_SIZE] objSet;

    /// Number of objects stored
    int numObjs;

    // TODO: store list of observation objects, 
    // each with a list of observer traces?
    // observation.check ?
    // List of type observations
    //private TypeObsv[] obsvs = null;
}

