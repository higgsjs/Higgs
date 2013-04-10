/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module util.bitset;

import std.stdio;
import std.array;
import std.stdint;

/**
Bit set with in-place operations
*/
class BitSet
{
    private uint32_t[] intVals;

    private size_t numBits;

    this(size_t numBits)
    {
        this.intVals.length = (numBits / 32) + ((numBits % 32)? 1:0);

        this.numBits = numBits;

        for (size_t i = 0; i < intVals.length; ++i)
            intVals[i] = 0;
    }

    /// Copy constructor
    this(BitSet that)
    {
        this.intVals.length = that.intVals.length;

        this.numBits = that.numBits;

        for (size_t i = 0; i < this.intVals.length; ++i)
            this.intVals[i] = that.intVals[i];
    }

    size_t length()
    {
        return numBits;
    }

    void add(size_t idx)
    {
        auto intIdx = idx >> 5;
        auto bitIdx = idx & 31;

        // Set the bit
        intVals[intIdx] |= (1 << bitIdx);
    }

    void remove(size_t idx)
    {
        auto intIdx = idx >> 5;
        auto bitIdx = idx & 31;

        intVals[intIdx] &= ~(1 << bitIdx);
    }

    bool has(size_t idx)
    {
        auto intIdx = idx >> 5;
        auto bitIdx = idx & 31;

        return (intVals[intIdx] >> bitIdx) & 1;
    }

    /// Compare two sets for equality
    override bool opEquals(Object o)
    {
        auto that = cast(BitSet)o;

        assert (o !is null);
        assert (this.numBits == that.numBits);

        for (size_t i = 0; i < this.intVals.length; ++i)
            if (this.intVals[i] != that.intVals[i])
                return false;

        return true;
    }

    /// Assignment method
    void assign(BitSet that)
    {
        assert (this.numBits == that.numBits);

        for (size_t i = 0; i < this.intVals.length; ++i)
            this.intVals[i] = that.intVals[i];
    }

    /// Merge operator (union)
    void setUnion(BitSet that)
    {
        assert (this.numBits == that.numBits);

        for (size_t i = 0; i < this.intVals.length; ++i)
            this.intVals[i] |= that.intVals[i];
    }
}

/**
Bit set with copy-on-write semantics
*/
class BitSetCW
{
    private uint32_t[] intVals;

    private size_t numBits;

    this(size_t numBits)
    {
        this.intVals.length = (numBits / 32) + ((numBits % 32)? 1:0);

        this.numBits = numBits;

        for (size_t i = 0; i < intVals.length; ++i)
            intVals[i] = 0;
    }

    size_t length()
    {
        return numBits;
    }

    BitSetCW add(size_t idx)
    {
        auto intIdx = idx >> 5;
        auto bitIdx = idx & 31;

        // If the bit is already set, return this map unchanged
        if ((intVals[intIdx] >> bitIdx) & 1)
            return this;

        // TODO: optimize copying

        auto newMap = new BitSetCW(numBits);

        for (size_t i = 0; i < this.intVals.length; ++i)
            newMap.intVals[i] = this.intVals[i];

        newMap.intVals[intIdx] |= (1 << bitIdx);

        return newMap;
    }

    bool has(size_t idx)
    {
        auto intIdx = idx >> 5;
        auto bitIdx = idx & 31;

        return (intVals[intIdx] >> bitIdx) & 1;
    }

    /// Compare two maps for equality
    bool opEqual(BitSetCW that)
    {
        assert (this.numBits == that.numBits);

        for (size_t i = 0; i < this.intVals.length; ++i)
            if (this.intVals[i] != that.intVals[i])
                return false;

        return true;
    }

    /// Merge operator (union)
    BitSetCW setUnion(BitSetCW that)
    {
        assert (this.numBits == that.numBits);

        for (size_t i = 0; i < this.intVals.length; ++i)
        {
            if ((this.intVals[i] | that.intVals[i]) != this.intVals[i])
            {
                auto newMap = new BitSetCW(numBits);

                for (size_t j = 0; j < i; ++j)
                    newMap.intVals[j] = this.intVals[j];

                for (size_t j = i; j < this.intVals.length; ++j)
                    newMap.intVals[j] = (this.intVals[j] | that.intVals[j]);

                return newMap;
            }
        }

        return this;
    }
}

unittest
{
    writefln("BitSetCW");

    auto m = new BitSetCW(100);

    assert (m.has(0) == false);
    assert (m.has(99) == false);
    assert (m.setUnion(m) == m);

    auto m2 = m.add(5).add(33);

    assert (m2.has(5) == true);
    assert (m2.has(33) == true);
    assert (m2 != m);
    assert (m2.setUnion(m) == m2);
    assert (m2.has(5) == true);
    assert (m2.has(33) == true);
    assert (m.has(5) == false);

    auto m3 = m.add(65);
    auto m4 = m2.setUnion(m3);

    assert (m4.has(0) == false);
    assert (m4.has(5) == true);
    assert (m4.has(65) == true);
}

