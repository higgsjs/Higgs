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
 *  Copyright (c) 2011-2014, Universite de Montreal
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

/**
Default hash function implementation
*/
Map.defHashFn = function (val)
{
    if (typeof val === 'number')
    {
        return Math.floor(val);
    }

    else if (typeof val === 'string')
    {
        var hashCode = 0;

        for (var i = 0; i < val.length; ++i)
        {
            var ch = val.charCodeAt(i);
            hashCode = (((hashCode << 8) + ch) & 536870911) % 426870919;
        }

        return hashCode;
    }

    else if (typeof val === 'boolean')
    {
        return val? 1:0;
    }

    else if (val === null || val === undefined)
    {
        return 0;
    }

    else
    {
        if (val.__hashCode__ === undefined)
        {
            val.__hashCode__ = defHashFn.nextObjSerial++;
        }

        return val.__hashCode__;
    }
}
Object.defineProperty(Map, 'defHashFn', { writable:false });

/**
Next object serial number to be assigned
*/
Map.defHashFn.nextObjSerial = 1;

/**
Default equality function
*/
Map.defEqualFn = function (key1, key2)
{
    return key1 === key2;
}
Object.defineProperty(Map, 'defEqualFn', { writable:false });

// Default initial hash map size
Object.defineProperty(Map, 'DEFAULT_INIT_SIZE', { value: 128 });

// Hash map min and max load factors
Object.defineProperty(Map, 'MIN_LOAD_NUM'  , { value: 1 });
Object.defineProperty(Map, 'MIN_LOAD_DENOM', { value: 10 });
Object.defineProperty(Map, 'MAX_LOAD_NUM'  , { value: 6 });
Object.defineProperty(Map, 'MAX_LOAD_DENOM', { value: 10 });

// Key value for free hash table slots
Object.defineProperty(Map, 'FREE_KEY', { value: 'FREE_KEY' });

// Value returned for not found items
Object.defineProperty(Map, 'NOT_FOUND', { value: 'NOT_FOUND' });

/**
@class Hash map implementation
*/
function Map(hashFn, equalFn, initSize)
{
    // If no hash function was specified, use the default function
    if (hashFn === undefined || hashFn === null)
        hashFn = Map.defHashFn;

    // If no hash function was specified, use the default function
    if (equalFn === undefined || equalFn === null)
        equalFn = Map.defEqualFn;

    if (initSize === undefined)
        initSize = Map.DEFAULT_INIT_SIZE;

    /**
    Initial size of this hash map
    @field
    */
    this.initSize = initSize;

    /**
    Number of internal array slots
    @field
    */
    this.numSlots = initSize;

    /**
    Internal storage array
    @field
    */
    this.array = [];

    // Set the initial array size
    this.array.length = 2 * this.numSlots;

    // Initialize each array element
    for (var i = 0; i < this.numSlots; ++i)
        this.array[2 * i] = Map.FREE_KEY;

    /**
    Number of items stored
    @field
    */
    this.length = 0;

    /**
    Hash function
    @field
    */
    this.hashFn = hashFn;

    /**
    Key equality function
    @field
    */
    this.equalFn = equalFn;
}

/**
Add or change a key-value binding in the map
*/
Map.prototype.set = function (key, value)
{
    var index = 2 * (this.hashFn(key) % this.numSlots);

    // Until a free cell is found
    while (this.array[index] !== Map.FREE_KEY)
    {
        // If this slot has the item we want
        if (this.equalFn(this.array[index], key))
        {
            // Set the item's value
            this.array[index + 1] = value;

            // Exit the function
            return;
        }

        index = (index + 2) % this.array.length;
    }

    // Insert the new item at the free slot
    this.array[index] = key;
    this.array[index + 1] = value;

    // Increment the number of items stored
    this.length++;

    // Test if resizing of the hash map is needed
    // length > ratio * numSlots
    // length > num/denom * numSlots 
    // length * denom > numSlots * num
    if (this.length * Map.MAX_LOAD_DENOM >
        this.numSlots * Map.MAX_LOAD_NUM)
    {
        this.resize(2 * this.numSlots);
    }

    return this;
};

/**
Remove an item from the map
*/
Map.prototype.delete = function (key)
{    
    var index = 2 * (this.hashFn(key) % this.numSlots);

    // Until a free cell is found
    while (this.array[index] !== Map.FREE_KEY)
    {
        // If this slot has the item we want
        if (this.equalFn(this.array[index], key))
        {
            // Initialize the current free index to the removed item index
            var curFreeIndex = index;

            // For every subsequent item, until we encounter a free slot
            for (var shiftIndex = (index + 2) % this.array.length;
                this.array[shiftIndex] !== Map.FREE_KEY;
                shiftIndex = (shiftIndex + 2) % this.array.length)
            {
                // Calculate the index at which this item's hash key maps
                var origIndex = 2 * (this.hashFn(this.array[shiftIndex]) % this.numSlots);

                // Compute the distance from the element to its origin mapping
                var distToOrig =
                    (shiftIndex < origIndex)? 
                    (shiftIndex + this.array.length - origIndex):
                    (shiftIndex - origIndex);

                // Compute the distance from the element to the current free index
                var distToFree =
                    (shiftIndex < curFreeIndex)?
                    (shiftIndex + this.array.length - curFreeIndex):
                    (shiftIndex - curFreeIndex);                    

                // If the free slot is between the element and its origin
                if (distToFree <= distToOrig)
                {
                    // Move the item into the free slot
                    this.array[curFreeIndex] = this.array[shiftIndex];
                    this.array[curFreeIndex + 1] = this.array[shiftIndex + 1];

                    // Update the current free index
                    curFreeIndex = shiftIndex;
                }
            }

            // Clear the hash key at the current free position
            this.array[curFreeIndex] = Map.FREE_KEY;

            // Decrement the number of items stored
            this.length--;

            // If we are under the minimum load factor, shrink the internal array
            // length < ratio * numSlots 
            // length < num/denom * numSlots 
            // length * denom < numSlots * num
            if ((this.length * Map.MIN_LOAD_DENOM <
                 this.numSlots * Map.MIN_LOAD_NUM)
                &&
                this.numSlots > this.initSize)
            {
                this.resize(this.numSlots >> 1);
            }

            // Item removed
            return;
        }

        index = (index + 2) % this.array.length;
    }
};

/**
Get an item in the map
*/
Map.prototype.get = function (key)
{
    var index = 2 * (this.hashFn(key) % this.numSlots);

    // Until a free cell is found
    while (this.array[index] !== Map.FREE_KEY)
    {
        // If this slot has the item we want
        if (this.equalFn(this.array[index], key))
        {
            // Return the item's value
            return this.array[index + 1];
        }

        index = (index + 2) % this.array.length;
    }

    // Key not found
    return undefined;
};

/**
Test if an item is in the map
*/
Map.prototype.has = function (key)
{
    var index = 2 * (this.hashFn(key) % this.numSlots);

    // Until a free cell is found
    while (this.array[index] !== Map.FREE_KEY)
    {
        // If this slot has the item we want
        if (this.equalFn(this.array[index], key))
        {
            // Key found
            return true;
        }

        index = (index + 2) % this.array.length;
    }

    // Key not found
    return false;
};

/**
Erase all contained items
*/
Map.prototype.clear = function ()
{
    // Set the initial number of slots
    this.numSlots = this.initSize;

    // Set the initial array size
    this.array.length = 2 * this.numSlots;

    // Reset each array key element
    for (var i = 0; i < this.numSlots; ++i)
        this.array[2 * i] = Map.FREE_KEY;

    // Reset the number of items stored
    this.length = 0;

    return this;
};

/**
Resize the hash map's internal storage
*/
Map.prototype.resize = function (newSize)
{
    // Ensure that the new size is valid
    assert (
        this.length <= newSize && Math.floor(newSize) === newSize,
        'cannot resize, more items than new size allows'
    );

    var oldNumSlots = this.numSlots;
    var oldArray = this.array;

    // Initialize a new internal array
    this.array = [];
    this.numSlots = newSize;
    this.array.length = 2 * this.numSlots;
    for (var i = 0; i < this.numSlots; ++i)
        this.array[2 * i] = Map.FREE_KEY;

    // Reset the number of elements stored
    this.length = 0;

    // Re-insert the elements from the old array
    for (var i = 0; i < oldNumSlots; ++i)
        if (oldArray[2 * i] !== Map.FREE_KEY)
            this.set(oldArray[2 * i], oldArray[2 * i + 1]);     
};

// FIXME: not spec-conformant
/**
Get the keys present in the hash map
*/
/*
Map.prototype.keys = function ()
{
    var keys = [];

    for (var i = 0; i < this.numSlots; ++i)
    {
        var index = 2 * i;

        if (this.array[index] !== Map.FREE_KEY)
            keys.push(this.array[index]);
    }

    return keys;
};
*/

// TODO: forEach

/**
Get an iterator for this hash map
*/
/*
Map.prototype.iterator = function ()
{
    return new Map.Iterator(this, 0);
};
*/

/**
@class Hash map iterator
*/
/*
Map.Iterator = function (map, slotIndex)
{
    /// Associated hash map
    this.map = map;

    /// Current hash map slot
    this.index = slotIndex;

    // Move to the next non-free slot
    this.nextFullSlot();
};
Map.Iterator.prototype = {};
*/

/**
Move the current index to the next non-free slot
*/
/*
Map.Iterator.prototype.nextFullSlot = function ()
{
    while (
        this.index < this.map.array.length &&
        this.map.array[this.index] === Map.FREE_KEY
    )
        this.index += 2;
};
*/

/**
Test if the iterator is at a valid position
*/
/*
Map.Iterator.prototype.valid = function ()
{
    return (this.index < this.map.array.length);
};
*/

/**
Move to the next list item
*/
/*
Map.Iterator.prototype.next = function ()
{
    assert (
        this.valid(),
        'cannot move to next list item, iterator not valid'
    );

    // Move to the next slot
    this.index += 2;

    // Move to the first non-free slot found
    this.nextFullSlot();
};
*/

/**
Get the current list item
*/
/*
Map.Iterator.prototype.get = function ()
{
    assert (
        this.valid(),
        'cannot get current list item, iterator not valid'
    );

    return { 
        key: this.map.array[this.index],  
        value: this.map.array[this.index + 1] 
    };
};
*/

