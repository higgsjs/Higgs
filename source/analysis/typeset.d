/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012, Maxime Chevalier-Boisvert. All rights reserved.
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

/*
// Extended object (object or array or function)
TypeFlags.EXTOBJ =
    TypeFlags.OBJECT    |
    TypeFlags.ARRAY     |
    TypeFlags.FUNCTION;

// Unknown/any type flag
TypeFlags.ANY =
    TypeFlags.UNDEF    |
    TypeFlags.NULL     |
    TypeFlags.TRUE     |
    TypeFlags.FALSE    |
    TypeFlags.INT      |
    TypeFlags.FLOAT    |
    TypeFlags.STRING   |
    TypeFlags.OBJECT   |
    TypeFlags.ARRAY    |
    TypeFlags.FUNCTION |
    TypeFlags.CELL;
*/

// Empty/uninferred type flag (before analysis)
const FLAG_EMPTY = 0;

/**
Type set representation
*/
struct TypeSet
{
    this(TypeFlags flags)
    {
        // TODO
    }

    @disable this();

    this(ValuePair val)
    {
        // TODO
    }

    /**
    Union another type set into this one
    */
    void unionSet(TypeSet that)
    {
        // TODO
    }

    /// Type flags
    TypeFlags flags;

    // TODO
    /**
    Numerical range minimum
    */
    //this.rangeMin = rangeMin;

    /**
    Numerical range maximum
    */
    //this.rangeMax = rangeMax;

    // TODO
    /**
    String value
    */
    //this.strVal = strVal;

    // TODO
    /**
    Object set
    */
    //this.objSet = object;
}

