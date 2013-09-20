/* _________________________________________________________________________
 *
 *             Tachyon : A Self-Hosted JavaScript Virtual Machine
 *
 *
 *  This file is part of the Tachyon JavaScript project. Tachyon is
 *  distributed at:
 *  http://github.com/Tachyon-Team/Tachyon
 *
 *
 *  Copyright (c) 2011, Universite de Montreal
 *  All rights reserved.
 *
 *  This software is licensed under the following license (Modified BSD
 *  License):
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are
 *  met:
 *    * Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the Universite de Montreal nor the names of its
 *      contributors may be used to endorse or promote products derived
 *      from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 *  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 *  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 *  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL UNIVERSITE DE
 *  MONTREAL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * _________________________________________________________________________
 */

// TODO: refactor for ES6 conformance

/**
@class Set implementation using a hash map
*/
function HashSet(hashFunc, equalFunc, initSize)
{
    HashMap.call(this, hashFunc, equalFunc, initSize);
}

HashSet.prototype = Object.create(HashMap.prototype);

/**
Add a value to the set
*/
HashSet.prototype.add = function (val)
{
    HashMap.prototype.set.call(this, val, val);

    return this;
};

/**
Add all values from array to the set
*/
HashSet.prototype.addArray = function (arr)
{
    const that = this;

    arr.forEach(function (val)
    {
        that.add(val);    
    });

    return this;
};

/**
Remove all values in array from the set
*/
HashSet.prototype.remArray = function (arr)
{
    const that = this;

    arr.forEach(function (val)
    {
        that.rem(val);
    });

    return this;
};

/**
In-place set difference (relative complement)
*/
HashSet.prototype.diff = function (set)
{
    const that = this;

    for (var it = set.getItr(); it.valid(); it.next())
    {
        var item = it.get();
        that.rem(item);
    };
    
    return this;
};

/**
In-place union
*/
HashSet.prototype.union = function (that)
{
    for (var it = that.getItr(); it.valid(); it.next())
    {
        this.add(it.get());    
    }

    return this;
};

/*
In-place intersection
*/
HashSet.prototype.intr = function (set)
{
    const that = this;

    this.getKeys().forEach(function (key)
    {
        if (!set.has(key))
        {
            that.rem(key);
        }
    });

    return this;
};

/**
Test set for equality
*/
HashSet.prototype.equal = function (that)
{
    if (that.length !== this.length)
        return false;

    for (var it = HashMap.prototype.getItr.call(that); it.valid(); it.next())
    {
        if (this.has(it.get().key) === false)
            return false;
    }

    return true;
};

/**
Iterate through all items
*/
HashSet.prototype.getItr = function ()
{
    var itr = HashMap.prototype.getItr.call(this);

    // Redefine the get function because we only need to iterate through keys
    function get()
    {
        assert(
            this.valid(),
            'cannot get current list item, iterator not valid'
        );

        return this.map.array[this.index];
    }
    itr.get = get;

    return itr;
};

