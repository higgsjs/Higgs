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
import interp.layout;
import interp.interp;
import util.misc;

/**
Perform a garbage collection
*/
void gcCollect(Interp interp)
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

    writeln("entering gcCollect");
    
    writefln("allocating heap of size: %s", interp.heapSize);

    // Allocate a memory block for the to-space
    interp.toStart = cast(ubyte*)GC.malloc(interp.heapSize);

    writefln("allocated to-space block: %s", interp.toStart);

    assert (
        interp.toStart != null,
        "failed to allocate to-space heap"
    );

    // Compute the to-space heap limit
    interp.toLimit = interp.toStart + interp.heapSize;

    // Initialize the to-space allocation pointer
    interp.toAlloc = interp.toStart;

    writeln("visiting interpreter roots");

    // Forward the interpreter root objects
    interp.strTbl       = gcForward(interp, interp.strTbl);
    interp.objProto     = gcForward(interp, interp.objProto);
    interp.arrProto     = gcForward(interp, interp.arrProto);
    interp.funProto     = gcForward(interp, interp.funProto);
    interp.globalClass  = gcForward(interp, interp.globalClass);
    interp.globalObj    = gcForward(interp, interp.globalObj);

    writeln("visiting stack roots");

    // Visit the stack roots
    visitStackRoots(interp);

    writeln("scanning to-space");

    // Scan Pointer: All objects behind it (i.e. to its left) have been fully
    // processed; objects in front of it have been copied but not processed.
    // Free Pointer: All copied objects are behind it; Space to its right is free

    // Initialize the scan pointer at the to-space heap start
    auto scanPtr = interp.toStart;

    // Until the to-space scan is complete
    size_t numObjs;
    for (numObjs = 0;; ++numObjs)
    {
        //iir.trace_print('scanning object');

        // If we are past the free pointer, scanning done
        if (scanPtr >= interp.toAlloc)
            break;

        // Get the current object reference
        refptr objPtr = scanPtr;

        assert (
            objPtr >= interp.toStart || objPtr < interp.toLimit,
            "object pointer past to-space limit"
        );

        // TODO: Get the object size
        // TODO: sizeof_layout
        //auto objSize = sizeof_layout(objRef);
        auto objSize = 0;

        assert (
            objPtr + objSize <= interp.toLimit,
            "object extends past to-space limit"
        );

        // TODO
        // Visit the object layout, forward its references
        //gc_visit_layout(objRef);

        // Move to the next object
        scanPtr = objPtr + objSize;
        scanPtr = alignPtr(scanPtr);
    }

    writefln("objects copied/scanned: %s", numObjs);

    // For debugging, clear the old heap
    for (int64* p = cast(int64*)interp.heapStart; p < cast(int64*)interp.heapLimit; p++)
        *p = 0;

    // Free the from-space heap block
    GC.free(interp.heapStart);

    // Flip the from-space and to-space
    interp.heapStart = interp.toStart;
    interp.heapLimit = interp.toLimit;
    interp.allocPtr = interp.toAlloc;

    // Clear the to-space information
    interp.toStart = null;
    interp.toLimit = null;
    interp.toAlloc = null;

    writeln("leaving gcCollect");
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

    // TODO
    // Get the forwarding pointer field of the object
    //refptr nextPtr = get_layout_next(ptr);
    refptr nextPtr = null;

    // If the object is not already forwarded
    if (nextPtr < interp.toStart && nextPtr >= interp.toLimit)
    {
        // TODO
        // Copy the object into the to-space
        nextPtr = gcCopy(interp, ptr, /*sizeof_layout(ref)*/0);
    }

    assert (
        nextPtr >= interp.toStart && nextPtr < interp.toLimit,
        "forwarded address is outside of to-space"
    );

    // Return the forwarded pointer
    return nextPtr;
}

/**
Copy a live object into the to-space.
*/
refptr gcCopy(Interp interp, refptr ptr, size_t size)
{
    //iir.trace_print('copying object:');
    //printPtr(objPtr);

    assert (
        ptr >= interp.heapStart && ptr < interp.heapLimit,
        "gcCopy: object not in heap"
    );

    // The object will be copied at the to-space allocation pointer
    auto nextPtr = interp.toAlloc;

    assert (
        nextPtr + size <= interp.heapLimit,
        "cannot copy in to-space, heap limit exceeded"
    );

    // Update the allocation pointer
    interp.toAlloc += size;
    interp.toAlloc = alignPtr(interp.toAlloc);

    // Copy the object to the to-space
    for (size_t i = 0; i < size; ++i)
        nextPtr[i] = ptr[i];

    // TODO
    // Write the forwarding pointer in the old object
    //set_layout_next(ref, newAddr);

    // Return the copied object pointer
    return nextPtr;
}

/**
Walk the stack and forward references to the to-space
*/
void visitStackRoots(Interp interp)
{
    Word* wPtr = interp.wLowerLimit;
    Type* tPtr = interp.tLowerLimit;

    // For each stack slot, from bottom to top
    while (wPtr < interp.wUpperLimit)
    {
        // If this is a pointer, forward it
        if (*tPtr == Type.REFPTR)
            wPtr.ptrVal = gcForward(interp, wPtr.ptrVal);

        // Move to the next stack slot
        ++wPtr;
        ++tPtr;
    }
}

const uint64 NEXT_FLAG = 1L << 63;

refptr getNext(refptr obj)
{
    auto iVal = *cast(uint64*)obj;

    if ((iVal & NEXT_FLAG) == 0)
        return null;

    return cast(refptr)(iVal ^ NEXT_FLAG);
}

void setNext(refptr obj, refptr next)
{
    auto iVal = cast(uint64)next;

    assert (
        (iVal & NEXT_FLAG) == 0,
        "top bit of next pointer is already set"
    );

    auto iPtr = cast(uint64*)obj;

    *iPtr = iVal | NEXT_FLAG;
}

//============================================================================
//============================================================================

/**
Visit a function pointer and its references
*/
/*
function gcVisitFptr(ptr, offset)
{
    "tachyon:static";
    "tachyon:noglobal";
    "tachyon:arg ptr rptr";
    "tachyon:arg offset pint";

    //iir.trace_print('fptr');

    // Read the function pointer
    var funcPtr = iir.load(IRType.rptr, ptr, offset);

    // Visit the function's machine code block
    gcVisitMCB(funcPtr, MCB_HEADER_SIZE);
}
*/

/**
Visit and update a reference value
*/
/*
function gcVisitRef(ptr, offset)
{
    "tachyon:static";
    "tachyon:noglobal";
    "tachyon:arg ptr rptr";
    "tachyon:arg offset pint";

    //iir.trace_print('ref');

    // Read the reference
    var refVal = iir.load(IRType.ref, ptr, offset);

    assert (
        ptrInHeap(iir.icast(IRType.rptr, refVal)) === true,
        'ref val points out of heap'
    );

    // Get a forwarded reference in the to-space
    var newRef = gcForward(refVal);

    // Update the reference
    iir.store(IRType.ref, ptr, offset, newRef);
}
*/

/**
Visit and update a boxed value
*/
/*
function gcVisitBox(ptr, offset)
{
    "tachyon:static";
    "tachyon:noglobal";
    "tachyon:arg ptr rptr";
    "tachyon:arg offset pint";

    //iir.trace_print('box');

    // Read the value
    var boxVal = iir.load(IRType.box, ptr, offset);

    //print('box val: ' + val);

    // If the boxed value is a reference
    if (boxIsRef(boxVal) === true)
    {
        //iir.trace_print('boxed ref');

        // Unbox the reference
        var refVal = unboxRef(boxVal);
        var refTag = getRefTag(boxVal);

        assert (
            ptrInHeap(iir.icast(IRType.rptr, refVal)) === true,
            'ref val points out of heap'
        );

        // Get a forwarded reference in the to-space
        var newRef = gcForward(refVal);

        // Rebox the reference value
        var newBox = boxRef(newRef, refTag);

        // Update the boxed value
        iir.store(IRType.box, ptr, offset, newBox);
    }
}
*/

/**
Get the amount of memory allocated in KBs
*/
/*
function memAllocatedKBs()
{
    "tachyon:static";
    "tachyon:noglobal";

    var ctx = iir.get_ctx();

    var freePtr = get_ctx_freeptr(ctx);
    var heapStart = get_ctx_heapstart(ctx);
    var heapSizeKBs = (freePtr - heapStart) / pint(1024);

    return boxInt(heapSizeKBs);
}
*/

/**
Shrink the heap to a smaller size, for testing purposes
*/
/*
function shrinkHeap(freeSpace)
{
    "tachyon:static";
    "tachyon:noglobal";
    "tachyon:arg freeSpace puint";

    gcCollect();

    var ctx = iir.get_ctx();

    // Get the current heap parameters
    var heapSize = get_ctx_heapsize(ctx);
    var heapStart = get_ctx_heapstart(ctx);
    var heapLimit = get_ctx_heaplimit(ctx);
    var freePtr = get_ctx_freeptr(ctx);

    var curAlloc = freePtr - heapStart;

    var newLimit = freePtr + freeSpace;
    var newSize = iir.icast(IRType.puint, newLimit - heapStart);

    assert (
        newSize <= heapSize,
        'invalid new heap size'
    );

    assert (
        newLimit >= heapStart && newLimit <= heapLimit,
        'invalid new heap limit'
    );

    set_ctx_heapsize(ctx, newSize);
    set_ctx_heaplimit(ctx, newLimit);
}
*/

