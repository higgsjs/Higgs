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

module interp.gc;

import core.memory;
import std.stdio;
import std.string;
import interp.layout;
import interp.interp;
import interp.string;
import util.misc;

/**
GC root object
*/
struct GCRoot
{
    this(Interp interp, ValuePair pair)
    {
        this.interp = interp;

        this.prev = null;
        this.next = interp.firstRoot;
        interp.firstRoot = &this;

        this.pair = pair;
    }

    this(Interp interp, Word w, Type t)
    {
        this(interp, ValuePair(w, t));
    }

    this(Interp interp, refptr p = null)
    {
        this(interp, Word.ptrv(p), Type.REFPTR);
    }

    @disable this();

    ~this()
    {
        assert (
            interp !is null,
            "interp is null"
        );

        if (prev)
            prev.next = next;
        else
            this.interp.firstRoot = next;

        if (next)
            next.prev = prev;
    }

    refptr opAssign(refptr p)
    {
        pair.word.ptrVal = p;
        return p;
    }

    ValuePair opAssign(ValuePair v)
    {
        pair = v;
        return v;
    }

    Word word()
    {
        return pair.word;
    }

    Type type()
    {
        return pair.type;
    }

    refptr ptr()
    {
        return pair.word.ptrVal;
    }

    private Interp interp;

    private GCRoot* prev;
    private GCRoot* next;

    ValuePair pair;
}

/**
Allocate an object in the heap
*/
refptr heapAlloc(Interp interp, size_t size)
{
    // If this allocation exceeds the heap limit
    if (interp.allocPtr + size > interp.heapLimit)
    {
        /*
        writefln("from-start: %s", interp.heapStart);
        writefln("from-limit: %s", interp.heapLimit);
        writefln("to-start: %s", interp.toStart);
        writefln("to-start: %s", interp.toLimit);
        */

        //writefln("gc on alloc of size %s", size);

        // Perform garbage collection
        gcCollect(interp);

        // If this allocation exceeds the heap limit
        if (interp.allocPtr + size > interp.heapLimit)
        {
            throw new Error("heap space exhausted");
        }
    }

    // Store the pointer to the new object
    refptr ptr = interp.allocPtr;

    // Update and align the allocation pointer
    interp.allocPtr = alignPtr(interp.allocPtr + size);

    // Return the object pointer
    return ptr;
}

/**
Perform a garbage collection
*/
void gcCollect(Interp interp, size_t heapSize = 0)
{
    /*
    Cheney's Algorithm:

    flip() =
        Fromspace, Tospace = Tospace, Fromspace
        top_of_space = Tospace + space_size
        scan = free = Tospace

        for R in roots
            R = copy(R)

        while scan < free
            for P in Children(scan)
                *P = copy(*P)
            scan = scan + size (scan)

    copy(P) =
        if forwarded(P)
            return forwarding_address(P)
        else
            addr = free
            move(P,free)
            free = free + size(P)
            forwarding_address(P) = addr
            return addr
    */

    //writeln("entering gcCollect");
    //writefln("from-space address: %s", interp.heapStart);

    if (heapSize != 0)
        interp.heapSize = heapSize;

    //writefln("allocating to-space heap of size: %s", interp.heapSize);

    // Allocate a memory block for the to-space
    interp.toStart = cast(ubyte*)GC.malloc(interp.heapSize);

    //writefln("allocated to-space block: %s", interp.toStart);

    assert (
        interp.toStart != null,
        "failed to allocate to-space heap"
    );

    // Compute the to-space heap limit
    interp.toLimit = interp.toStart + interp.heapSize;

    // Initialize the to-space allocation pointer
    interp.toAlloc = interp.toStart;
    
    //writeln("visiting interpreter roots");

    // Forward the interpreter root objects
    interp.objProto     = gcForward(interp, interp.objProto);
    interp.arrProto     = gcForward(interp, interp.arrProto);
    interp.funProto     = gcForward(interp, interp.funProto);
    interp.globalObj    = gcForward(interp, interp.globalObj);

    //writeln("visiting stack roots");

    // Visit the stack roots
    visitStackRoots(interp);

    //writeln("visiting link table");

    // Visit the link table cells
    for (size_t i = 0; i < interp.linkTblSize; ++i)
    {
        interp.wLinkTable[i] = gcForward(
            interp,
            interp.wLinkTable[i],
            interp.tLinkTable[i]
        );
    }

    //writeln("visiting GC root objects");

    // Visit the root objects
    for (GCRoot* pRoot = interp.firstRoot; pRoot !is null; pRoot = pRoot.next)
        pRoot.pair.word = gcForward(interp, pRoot.pair.word, pRoot.pair.type);    

    //writeln("scanning to-space");

    // Scan Pointer: All objects behind it (i.e. to its left) have been fully
    // processed; objects in front of it have been copied but not processed.
    // Free Pointer: All copied objects are behind it; Space to its right is free

    // Initialize the scan pointer at the to-space heap start
    auto scanPtr = interp.toStart;

    // Until the to-space scan is complete
    size_t numObjs;
    for (numObjs = 0;; ++numObjs)
    {
        // If we are past the free pointer, scanning done
        if (scanPtr >= interp.toAlloc)
            break;

        assert (
            scanPtr >= interp.toStart || scanPtr < interp.toLimit,
            "scan pointer past to-space limit"
        );

        // Get the object size
        auto objSize = layout_sizeof(scanPtr);

        assert (
            scanPtr + objSize <= interp.toLimit,
            "object extends past to-space limit"
        );

        //writefln("scanning object of size %s", objSize);
        //writefln("scanning %s (%s)", scanPtr, numObjs);

        // Visit the object layout, forward its references
        layout_visit_gc(interp, scanPtr);

        // Move to the next object
        scanPtr = alignPtr(scanPtr + objSize);
    }

    //writefln("objects copied/scanned: %s", numObjs);

    // Store a pointer to the from-space heap
    auto fromStart = interp.heapStart;
    auto fromLimit = interp.heapLimit;

    // Flip the from-space and to-space
    interp.heapStart = interp.toStart;
    interp.heapLimit = interp.toLimit;
    interp.allocPtr = interp.toAlloc;

    // Clear the to-space information
    interp.toStart = null;
    interp.toLimit = null;
    interp.toAlloc = null;

    //writefln("rebuilding string table");

    // Store a pointer to the old string table
    auto oldStrTbl = interp.strTbl;
    auto strTblCap = strtbl_get_cap(oldStrTbl);

    // Allocate a new string table
    interp.strTbl = strtbl_alloc(interp, strTblCap);

    // Add the forwarded strings to the new string table
    for (uint32 i = 0; i < strTblCap; ++i)
    {
        auto ptr = strtbl_get_str(oldStrTbl, i);

        if (ptr is null)
            continue;

        auto next = obj_get_next(ptr);

        if (next is null)
            continue;

        getTableStr(interp, next);
    }

    //writefln("old string count: %s", strtbl_get_num_strs(oldStrTbl));
    //writefln("new string count: %s", strtbl_get_num_strs(interp.strTbl));

    //writefln("clearing from-space heap");

    // For debugging, clear the old heap
    for (int64* p = cast(int64*)fromStart; p < cast(int64*)fromLimit; p++)
        *p = 0;

    // Free the from-space heap block
    GC.free(fromStart);

    // Increment the garbage collection count
    interp.gcCount++;

    //writeln("leaving gcCollect");
    //writefln("free space: %s", (interp.heapLimit - interp.allocPtr));
}

/**
Function to forward a memory object. The argument is an unboxed reference.
*/
refptr gcForward(Interp interp, refptr ptr)
{
    // Pseudocode:
    //
    // if forwarded(P)
    //     return forwarding_address(P)
    // else
    //     addr = free
    //     move(P,free)
    //     free = free + size(P)
    //     forwarding_address(P) = addr
    //     return addr

    if (ptr is null)
        return null;

    //writefln("forwarding %s", ptr);

    assert (
        ptr >= interp.heapStart && ptr < interp.heapLimit,
        xformat(
            "gcForward: object not in from-space heap\n" ~
            "ptr   : %s\n" ~
            "start : %s\n" ~
            "limit : %s\n" ~
            "header: %s",
            ptr,
            interp.heapStart,
            interp.heapLimit,
            obj_get_header(ptr)
        )        
    );

    // Follow the next pointer chain for as long as it points in the from-space
    refptr nextPtr = ptr;
    do
    {
        nextPtr = obj_get_next(nextPtr);

    } while (nextPtr >= interp.heapStart && nextPtr < interp.heapLimit);

    // If the object is not already forwarded
    if (nextPtr is null)
    {
        //writefln("copying");

        // Copy the object into the to-space
        nextPtr = gcCopy(interp, ptr, layout_sizeof(ptr));

        assert (
            nextPtr >= interp.toStart && nextPtr < interp.toLimit,
            xformat(
                "gcForward: newly forwarded address is outside of to-space\n" ~
                "ptr   : %s\n" ~
                "start : %s\n" ~
                "limit : %s\n",
                nextPtr,
                interp.toStart,
                interp.toLimit,
            )
        );
    }
    else
    {
        assert (
            nextPtr >= interp.toStart && nextPtr < interp.toLimit,
            xformat(
                "gcForward: next pointer from object is outside of to-space\n" ~
                "objPtr  : %s\n" ~
                "nextPtr : %s\n" ~
                "to-start: %s\n" ~
                "to-limit: %s\n",
                ptr,
                nextPtr,
                interp.toStart,
                interp.toLimit,
            )
        );
    }

    // Return the forwarded pointer
    return nextPtr;
}

/**
Forward a word/value pair
*/
Word gcForward(Interp interp, Word word, Type type)
{
    // If this is not a heap pointer, don't change it
    if (type != Type.REFPTR)
        return word;

    // Forward the pointer
    return Word.ptrv(gcForward(interp, word.ptrVal));
}

/**
Forward a word/value pair
*/
uint64 gcForward(Interp interp, uint64 word, uint8 type)
{
    // Forward the pointer
    return gcForward(interp, Word.uintv(word), cast(Type)type).uintVal;
}

/**
Copy a live object into the to-space.
*/
refptr gcCopy(Interp interp, refptr ptr, size_t size)
{
    assert (
        ptr >= interp.heapStart && ptr < interp.heapLimit,
        xformat(
            "gcCopy: object not in from-space heap\n" ~
            "ptr   : %s\n" ~
            "start : %s\n" ~
            "limit : %s\n" ~
            "header: %s",
            ptr,
            interp.heapStart,
            interp.heapLimit,
            obj_get_header(ptr)
        )        
    );

    // The object will be copied at the to-space allocation pointer
    auto nextPtr = interp.toAlloc;

    assert (
        nextPtr + size <= interp.toLimit,
        xformat(
            "cannot copy in to-space, heap limit exceeded\n" ~
            "ptr     : %s\n" ~
            "size    : %s\n" ~
            "fr-limit: %s\n" ~
            "to-alloc: %s\n" ~
            "to-limit: %s\n" ~
            "header  : %s",
            ptr,
            size,
            interp.heapLimit,
            interp.toAlloc,
            interp.toLimit,
            obj_get_header(ptr)
        )
    );

    // Update the allocation pointer
    interp.toAlloc += size;
    interp.toAlloc = alignPtr(interp.toAlloc);

    // Copy the object to the to-space
    for (size_t i = 0; i < size; ++i)
        nextPtr[i] = ptr[i];

    assert (
        nextPtr >= interp.toStart && nextPtr < interp.toLimit,
        "gcCopy: next pointer is outside of to-space"
    );

    // Write the forwarding pointer in the old object
    obj_set_next(ptr, nextPtr);

    // Return the copied object pointer
    return nextPtr;
}

/**
Walk the stack and forward references to the to-space
*/
void visitStackRoots(Interp interp)
{
    if (interp.stackSize() == 0)
        return;

    //writefln("stack size: %s", interp.stackSize());

    // For each stack slot, from top to bottom
    for (size_t i = 0; i < interp.stackSize(); ++i)
    {
        //writefln("visiting stack slot %s/%s", (i+1), interp.stackSize());

        Word word = interp.getWord(i);
        Type type = interp.getType(i);

        // If this is a pointer, forward it
        interp.wsp[i] = gcForward(interp, word, type);

        auto fwdPtr = interp.wsp[i].ptrVal;
        assert (
            type != Type.REFPTR ||
            fwdPtr == null ||
            (fwdPtr >= interp.toStart && fwdPtr < interp.toLimit),
            xformat(
                "invalid forwarded stack pointer\n" ~
                "ptr     : %s\n" ~
                "to-alloc: %s\n" ~
                "to-limit: %s",
                fwdPtr,
                interp.toStart,
                interp.toLimit
            )
        );
    }
}

