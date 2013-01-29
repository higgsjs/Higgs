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
import interp.interp;
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



// TODO: template w.r.t. pointer repr
// One with GCRoot, one without


/**
Type set representation
*/
struct TypeSet
{
    @disable this();

    /**
    Construct a new type set
    */
    this(TypeFlags flags = FLAG_EMPTY)
    {
        this.flags = flags;

        strVal = GCRoot(null);

        for (size_t i = 0; i < objSet.length; ++i)
            objSet[i] = GCRoot(null);
    }

    /**
    Construct a type set from a value
    */
    this(ValuePair val)
    {
        strVal = GCRoot(null);

        flags = FLAG_EMPTY;

        // TODO




    }

    /**
    Union another type set into this one
    */
    void unionSet(TypeSet that)
    {
        flags = flags | that.flags;


        // TODO: look at Tachyon code





    }

    /// Type flags
    TypeFlags flags;

    /// Numerical range minimum
    long rangeMin;

    /// Numerical range maximum
    long rangeMax;

    /// String value
    GCRoot strVal;

    /// Object set (size limited)
    GCRoot[MAX_OBJ_SET_SIZE] objSet;
}



// TODO: KISS!





// TODO: decouple TypeSet from type monitor, TypeMon?
// Type monitor can have attached observations
// TypeMon.observeInt ...
class TypeMon
{
    // TODO



    /// Internal type representation
    private TypeSet type;
}

