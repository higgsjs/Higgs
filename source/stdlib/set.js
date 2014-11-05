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

// Default initial hash set size
Object.defineProperty(Set, 'DEFAULT_INIT_SIZE', { value: 128 });

// Hash map min and max load factors
Object.defineProperty(Set, 'MIN_LOAD_NUM'  , { value: 1 });
Object.defineProperty(Set, 'MIN_LOAD_DENOM', { value: 10 });
Object.defineProperty(Set, 'MAX_LOAD_NUM'  , { value: 6 });
Object.defineProperty(Set, 'MAX_LOAD_DENOM', { value: 10 });

// Key value for free hash table slots
Object.defineProperty(Set, 'FREE_KEY', { value: 'FREE_KEY' });

// Value returned for not found items
Object.defineProperty(Set, 'NOT_FOUND', { value: 'NOT_FOUND' });

/**
@class Hash map implementation
*/
function Set(hashFn, equalFn, initSize)
{
    // If no hash function was specified, use the default function
    if (hashFn === undefined || hashFn === null)
        hashFn = Map.defHashFn;

    // If no hash function was specified, use the default function
    if (equalFn === undefined || equalFn === null)
        equalFn = Map.defEqualFn;

    if (initSize === undefined)
        initSize = Set.DEFAULT_INIT_SIZE;

    /**
    Initial size of this hash map
    @field
    */
    this.initSize = initSize;

    /**
    Internal storage array
    @field
    */
    this.array = [];

    // Set the initial array size
    this.array.length = initSize;

    // Initialize each array element
    for (var i = 0; i < this.array.length; ++i)
        this.array[i] = Set.FREE_KEY;

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
Add a value to the set
*/
Set.prototype.add = function (key)
{
    var index = this.hashFn(key) % this.array.length;

    // Until a free cell is found
    while (this.array[index] !== Set.FREE_KEY)
    {
        // If this slot has the item we want
        if (this.equalFn(this.array[index], key))
        {
            // Exit the function
            return;
        }

        index = (index + 1) % this.array.length;
    }

    // Insert the new item at the free slot
    this.array[index] = key;

    // Increment the number of items stored
    this.length++;

    // Test if resizing of the hash map is needed
    // length > ratio * numSlots
    // length > num/denom * numSlots 
    // length * denom > numSlots * num
    if (this.length * Set.MAX_LOAD_DENOM >
        this.array.length * Set.MAX_LOAD_NUM)
    {
        this.resize(2 * this.array.length);
    }

    return this;
};

/**
Remove an item from the map
*/
Set.prototype.delete = function (key)
{    
    var index = (this.hashFn(key) % this.array.length);

    // Until a free cell is found
    while (this.array[index] !== Set.FREE_KEY)
    {
        // If this slot has the item we want
        if (this.equalFn(this.array[index], key))
        {
            // Initialize the current free index to the removed item index
            var curFreeIndex = index;

            // For every subsequent item, until we encounter a free slot
            for (var shiftIndex = (index + 1) % this.array.length;
                this.array[shiftIndex] !== Set.FREE_KEY;
                shiftIndex = (shiftIndex + 1) % this.array.length)
            {
                // Calculate the index at which this item's hash key maps
                var origIndex = (this.hashFn(this.array[shiftIndex]) % this.array.length);

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

                    // Update the current free index
                    curFreeIndex = shiftIndex;
                }
            }

            // Clear the hash key at the current free position
            this.array[curFreeIndex] = Set.FREE_KEY;

            // Decrement the number of items stored
            this.length--;

            // If we are under the minimum load factor, shrink the internal array
            // length < ratio * numSlots 
            // length < num/denom * numSlots 
            // length * denom < numSlots * num
            if ((this.length * Set.MIN_LOAD_DENOM <
                 this.array.length * Set.MIN_LOAD_NUM)
                &&
                this.array.length > this.initSize)
            {
                this.resize(this.array.length >> 1);
            }

            // Item removed
            return;
        }

        index = (index + 1) % this.array.length;
    }
};

/**
Test if an item is in the map
*/
Set.prototype.has = function (key)
{
    var index = (this.hashFn(key) % this.array.length);

    // Until a free cell is found
    while (this.array[index] !== Set.FREE_KEY)
    {
        // If this slot has the item we want
        if (this.equalFn(this.array[index], key))
        {
            // Return the item's value
            return true;
        }

        index = (index + 1) % this.array.length;
    }

    // Return the special not found value
    return false;
};

/**
Erase all contained items
*/
Set.prototype.clear = function ()
{
    // Set the initial array size
    this.array.length = this.initSize;

    // Reset each array key element
    for (var i = 0; i < this.array.length; ++i)
        this.array[i] = Set.FREE_KEY;

    // Reset the number of items stored
    this.length = 0;

    return this;
};

/**
Resize the hash map's internal storage
*/
Set.prototype.resize = function (newSize)
{
    // Ensure that the new size is valid
    assert (
        this.length <= newSize && Math.floor(newSize) === newSize,
        'cannot resize, more items than new size allows'
    );

    var oldArray = this.array;

    // Initialize a new internal array
    this.array = [];
    this.array.length = newSize;
    for (var i = 0; i < this.array.length; ++i)
        this.array[i] = Set.FREE_KEY;

    // Reset the number of elements stored
    this.length = 0;

    // Re-insert the elements from the old array
    for (var i = 0; i < oldNumSlots; ++i)
        if (oldArray[i] !== Set.FREE_KEY)
            this.set(oldArray[i]);
};

// FIXME: not spec-conformant
/**
Get the keys present in the hash map
*/
/*
Set.prototype.keys = function ()
{
    var keys = [];

    for (var i = 0; i < this.array.length; ++i)
    {
        if (this.array[i] !== Set.FREE_KEY)
            keys.push(this.array[i]);
    }

    return keys;
};
*/

// TODO: forEach

