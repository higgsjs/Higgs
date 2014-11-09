/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

module runtime.string;

import std.c.string;
import std.stdio;
import std.stdint;
import std.string;
import std.conv;
import runtime.vm;
import runtime.layout;
import runtime.gc;

immutable uint32 STR_TBL_INIT_SIZE = 16384;
immutable uint32 STR_TBL_MAX_LOAD_NUM = 3;
immutable uint32 STR_TBL_MAX_LOAD_DEN = 5;

/**
Extract a D wchar string from a Higgs string object
This copies the data into a newly allocated string.
*/
wstring extractWStr(refptr ptr)
{
    assert (
        obj_get_header(ptr) == LAYOUT_STR,
        "invalid string object in extractWStr, incorrect header"
    );

    auto len = str_get_len(ptr);

    wchar[] wchars = new wchar[len];
    for (uint32 i = 0; i < len; ++i)
        wchars[i] = str_get_data(ptr, i);

    return to!wstring(wchars);
}

/**
Create a temporary D wchar string view of a Higgs string object
The D string becomes invalid when the Higgs GC is triggered.
This is less safe, but much faster than extractWStr
*/
wstring tempWStr(refptr ptr)
{
    auto strData = ptr + str_ofs_data(ptr, 0);
    auto strLen = str_get_len(ptr);

    auto wcharPtr = cast(immutable wchar*)strData;
    auto dStr = wcharPtr[0..strLen];

    return dStr;
}

/**
Extract a D string from a string object
*/
string extractStr(refptr ptr)
{
    return to!string(extractWStr(ptr));
}

/**
Assemble the string represented by a rope
*/
wstring ropeToWStr(refptr rope)
{
    refptr rightStr = rope_get_right(rope);

    // If the string was already generated and cached
    if (rightStr is null)
        return extractWStr(rope_get_left(rope));

    wstring output;

    refptr leftStr;

    // Until we are done traversing the ropes
    for (auto curRope = rope;;)
    {
        output = tempWStr(rightStr) ~ output;

        // Move to the next rope
        curRope = rope_get_left(curRope);

        // If this is the last string in the chain, stop
        if (refIsLayout(curRope, LAYOUT_STR))
        {
            leftStr = curRope;
            break;
        }

        // Get the right-hand string for the current rope
        rightStr = rope_get_right(curRope);

        // If the rope was already converted to a string
        if (rightStr is null)
        {
            leftStr = rope_get_left(curRope);
            break;
        }
    }

    output = tempWStr(leftStr) ~ output;

    return output;
}

/**
Extract a D string from a rope object
*/
string ropeToStr(refptr ptr)
{
    return to!string(ropeToWStr(ptr));
}

/**
MurmurHash2, 64-bit version for 64-but platforms
All hail Austin Appleby
*/
uint64_t murmurHash64A(const void* key, size_t len, uint64_t seed = 1337)
{
	const uint64_t m = 0xc6a4a7935bd1e995;
	const int r = 47;

	uint64_t h = seed ^ (len * m);

    uint64_t* data = cast(uint64_t*)key;
	uint64_t* end = data + (len/8);

	while (data != end)
	{
		uint64_t k = *data++;

		k *= m;
		k ^= k >> r;
		k *= m;

		h ^= k;
		h *= m;
	}

	ubyte* tail = cast(ubyte*)data;

	switch (len & 7)
	{
	    case 7: h ^= uint64_t(tail[6]) << 48;
	    case 6: h ^= uint64_t(tail[5]) << 40;
	    case 5: h ^= uint64_t(tail[4]) << 32;
	    case 4: h ^= uint64_t(tail[3]) << 24;
	    case 3: h ^= uint64_t(tail[2]) << 16;
	    case 2: h ^= uint64_t(tail[1]) << 8;
	    case 1: h ^= uint64_t(tail[0]);
	            h *= m;
        default:
	};
 
	h ^= h >> r;
	h *= m;
	h ^= h >> r;

	return h;
}

/**
Compute the hash value for a given string object
*/
uint32 compStrHash(refptr str)
{
    auto len = str_get_len(str);
    auto ptr = str + str_ofs_data(null, 0);

    uint32 hashCode = cast(uint32_t)murmurHash64A(ptr, len);

    // Store the hash code on the string object
    str_set_hash(str, hashCode);

    return hashCode;
}

/**
Compare two string objects for equality by comparing their contents
*/
bool streq(refptr strA, refptr strB)
{
    auto lenA = str_get_len(strA);
    auto lenB = str_get_len(strB);

    if (lenA != lenB)
        return false;

    auto ptrA = strA + str_ofs_data(strA, 0);
    auto ptrB = strB + str_ofs_data(strB, 0);
    return memcmp(ptrA, ptrB, uint16_t.sizeof * lenA) == 0;
}

/**
Find a string in the string table if duplicate, or add it to the string table
*/
refptr getTableStr(VM vm, refptr str)
{
    auto strTbl = vm.strTbl;

    // Get the size of the string table
    auto tblSize = strtbl_get_cap(strTbl);

    // Get the hash code from the string object
    auto hashCode = str_get_hash(str);

    // Get the hash table index for this hash value
    auto hashIndex = hashCode & (tblSize - 1);

    // Until the key is found, or a free slot is encountered
    while (true)
    {
        // Get the string value at this hash slot
        auto strVal = strtbl_get_str(strTbl, hashIndex);

        // If we have reached an empty slot
        if (strVal == null)
        {
            // Break out of the loop
            break;
        }

        // If this is the string we want
        if (streq(strVal, str) == true)
        {
            // Return a reference to the string we found in the table
            return strVal;
        }

        // Move to the next hash table slot
        hashIndex = (hashIndex + 1) & (tblSize - 1);
    }

    //
    // Hash table updating
    //

    // Set the corresponding key and value in the slot
    strtbl_set_str(strTbl, hashIndex, str);

    // Get the number of strings and increment it
    auto numStrings = strtbl_get_num_strs(strTbl);
    numStrings++;
    strtbl_set_num_strs(strTbl, numStrings);

    // Test if resizing of the string table is needed
    // numStrings > ratio * tblSize
    // numStrings > num/den * tblSize
    // numStrings * den > tblSize * num
    if (numStrings * STR_TBL_MAX_LOAD_DEN >
        tblSize * STR_TBL_MAX_LOAD_NUM)
    {
        // Store the string pointer in a GC root object
        auto strRoot = GCRoot(vm, str, Tag.STRING);

        // Extend the string table
        extStrTable(vm, strTbl, tblSize, numStrings);

        // Restore the string pointer
        str = strRoot.ptr;
    }

    // Return a reference to the string object passed as argument
    return str;
}

/**
Extend the string table's capacity
*/
void extStrTable(VM vm, refptr curTbl, uint32 curSize, uint32 numStrings)
{
    // Compute the new table size
    auto newSize = 2 * curSize;

    //writefln("extending string table, old size: %s, new size: %s", curSize, newSize);

    //printInt(curSize);
    //printInt(newSize);

    // Allocate a new, larger hash table
    auto newTbl = strtbl_alloc(vm, newSize);

    // Set the number of strings stored
    strtbl_set_num_strs(newTbl, numStrings);

    // Initialize the string array
    for (uint32 i = 0; i < newSize; ++i)
        strtbl_set_str(newTbl, i, null);

    // For each entry in the current table
    for (uint32 curIdx = 0; curIdx < curSize; curIdx++)
    {
        // Get the value at this hash slot
        auto slotVal = strtbl_get_str(curTbl, curIdx);

        // If this slot is empty, skip it
        if (slotVal == null)
            continue;

        // Get the hash code for the value
        auto valHash = str_get_hash(slotVal);

        // Get the hash table index for this hash value in the new table
        auto startHashIndex = valHash & (newSize - 1);
        auto hashIndex = startHashIndex;

        // Until a free slot is encountered
        while (true)
        {
            // Get the value at this hash slot
            auto slotVal2 = strtbl_get_str(newTbl, hashIndex);

            // If we have reached an empty slot
            if (slotVal2 == null)
            {
                // Set the corresponding key and value in the slot
                strtbl_set_str(newTbl, hashIndex, slotVal);

                // Break out of the loop
                break;
            }

            // Move to the next hash table slot
            hashIndex = (hashIndex + 1) & (newSize - 1);

            // Ensure that a free slot was found for this key
            assert (
                hashIndex != startHashIndex,
                "no free slots found in extended hash table"
            );
        }
    }

    // Update the string table reference
    vm.strTbl = newTbl;
}

/**
Get the interned string object for a given character string
*/
refptr getString(VM vm, wstring str)
{
    auto objPtr = str_alloc(vm, cast(uint32)str.length);

    for (uint32 i = 0; i < str.length; ++i)
        str_set_data(objPtr, i, str[i]);

    // Compute the hash code for the string
    compStrHash(objPtr);

    // Find/add the string in the string table
    objPtr = getTableStr(vm, objPtr);

    return objPtr;
}

