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

module interp.string;

import std.stdio;
import std.string;
import interp.interp;
import interp.layout;
import interp.gc;

immutable uint32 STR_TBL_INIT_SIZE = 997;
immutable uint32 STR_TBL_MAX_LOAD_NUM = 3;
immutable uint32 STR_TBL_MAX_LOAD_DENOM = 5;

/**
Compute the hash value for a given string object
*/
uint32 compStrHash(refptr str)
{
    // TODO: operate on multiple characters at a time, look at Murmur hash

    auto len = str_get_len(str);

    uint32 hashCode = 0;

    for (uint32 i = 0; i < len; ++i)
    {
        auto ch = str_get_data(str, i);
        hashCode = (((hashCode << 8) + ch) & 536870911) % 426870919;
    }

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

    for (uint32 i = 0; i < lenA; ++i)
        if (str_get_data(strA, i) != str_get_data(strB, i))
            return false;

    return true;
}

/**
Find a string in the string table if duplicate, or add it to the string table
*/
refptr getTableStr(Interp interp, refptr str)
{
    auto strTbl = interp.strTbl;

    // Get the size of the string table
    auto tblSize = strtbl_get_cap(strTbl);

    // Get the hash code from the string object
    auto hashCode = str_get_hash(str);

    // Get the hash table index for this hash value
    auto hashIndex = hashCode % tblSize;

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

        // Otherwise, if this is the string we want
        else if (streq(strVal, str) == true)
        {
            // Return a reference to the string we found in the table
            return strVal;
        }

        // Move to the next hash table slot
        hashIndex = (hashIndex + 1) % tblSize;
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
    // numStrings > num/denom * tblSize
    // numStrings * denom > tblSize * num
    if (numStrings * STR_TBL_MAX_LOAD_DENOM >
        tblSize * STR_TBL_MAX_LOAD_NUM)
    {
        // Store the string pointer in a GC root object
        auto strRoot = GCRoot(interp, str);

        // Extend the string table
        extStrTable(interp, strTbl, tblSize, numStrings);

        // Restore the string pointer
        str = strRoot.ptr;
    }

    // Return a reference to the string object passed as argument
    return str;
}

/**
Extend the string table's capacity
*/
void extStrTable(Interp interp, refptr curTbl, uint32 curSize, uint32 numStrings)
{
    // Compute the new table size
    auto newSize = curSize * 2 + 1;

    writefln("extending string table, old size: %s, new size: %s", curSize, newSize);

    //printInt(curSize);
    //printInt(newSize);

    // Allocate a new, larger hash table
    auto newTbl = strtbl_alloc(interp, newSize);

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
        auto startHashIndex = valHash % newSize;
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
            hashIndex = (hashIndex + 1) % newSize;

            // Ensure that a free slot was found for this key
            assert (
                hashIndex != startHashIndex,
                "no free slots found in extended hash table"
            );
        }
    }

    // Update the string table reference
    interp.strTbl = newTbl;
}

/**
Get the string object for a given string
*/
refptr getString(Interp interp, wstring str)
{
    auto objPtr = str_alloc(interp, cast(uint32)str.length);

    for (uint32 i = 0; i < str.length; ++i)
        str_set_data(objPtr, i, str[i]);

    // Compute the hash code for the string
    compStrHash(objPtr);

    // Find/add the string in the string table
    objPtr = getTableStr(interp, objPtr);

    return objPtr;
}

