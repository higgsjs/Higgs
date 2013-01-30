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
import std.math;
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

// Extended object (object or array or function)
const FLAG_EXTOBJ =
    FLAG_OBJECT    |
    FLAG_ARRAY     |
    FLAG_CLOS;

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
struct NonRootPtr
{
    this(Interp interp, refptr ptr)
    {
        this.ptr = ptr;
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
    this(Interp interp, TypeFlags flags = FLAG_EMPTY)
    {
        this.flags = flags;

        strVal = PtrType(interp, null);

        for (size_t i = 0; i < objSet.length; ++i)
            objSet[i] = PtrType(interp, null);
    }

    /**
    Construct a type set from a value
    */
    this(Interp interp, ValuePair val)
    {
        this(interp);

        // Switch on the value type
        switch (val.type)
        {
            // TODO
            case Type.REFPTR:
            if (val.word.ptrVal == null)
                flags = FLAG_NULL;
            //else if

            break;

            case Type.CONST:
            if (val.word == UNDEF)
                flags = FLAG_UNDEF;
            else if (val.word == TRUE)
                flags = FLAG_TRUE;
            else if (val.word == FALSE)
                flags = FLAG_FALSE;
            else
                assert (false, "unknown const type");
            break;

            case Type.FLOAT:
            flags = FLAG_INT | FLAG_FLOAT;
            rangeMin = val.word.floatVal;
            rangeMax = val.word.floatVal;
            break;

            case Type.INT:
            flags = FLAG_INT;
            rangeMin = val.word.intVal;
            rangeMax = val.word.intVal;
            break;

            default:
            assert (false, "unhandled value type");
        }
    }

    /**
    Union another type set into this one
    */
    void unionSet(alias ThatRoot)(ref const TypeSet!ThatRoot that)
    {
        flags = flags | that.flags;


        // TODO: look at Tachyon code





    }

    /**
    Assign the value of another type set into this one
    */
    TypeSet* opAssign(alias ThatRoot)(ref const TypeSet!ThatRoot that)
    {
        // TODO



        return this;
    }

    /// Type flags
    TypeFlags flags;

    /// Numerical range minimum
    double rangeMin;

    /// Numerical range maximum
    double rangeMax;

    /// String value
    PtrType strVal;

    /// Object set (size limited)
    PtrType[MAX_OBJ_SET_SIZE] objSet;
}

alias TypeSet!GCRoot TypeSetGC;
alias TypeSet!NonRootPtr TypeSetNR;

/**
Type monitor object, monitors a field or variable type
*/
class TypeMon
{
    this(Interp interp)
    {
        type = TypeSetGC(interp);
    }

    /// Union a value type into this type
    void unionVal(ValuePair val)
    {
        auto valType = TypeSetNR(interp, val);


        // FIXME: not working
        //type.unionSet!TypeSetNR(valType);



        // TODO: might as well return new type set on union?
        // Need to check if changed anyways



        // TODO: check if changed, if so, check observations
        /*
        if ()
        {
        }
        */



    }

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

    /// Parent interpreter
    private Interp interp;

    /// Internal type representation
    private TypeSetGC type;
}

