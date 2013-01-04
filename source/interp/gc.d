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

import std.stdio;
import interp.layout;
import interp.interp;

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

    //var startTime = currentTimeMillis();

    /*
    // Update the garbage collection count    
    var colNo = get_ctx_gccount(ctx) + u32(1);
    set_ctx_gccount(ctx, colNo);

    //iir.trace_print('collection no.: ');
    //printInt(iir.icast(IRType.pint, colNo));

    // Get the current heap parameters (from-space)
    var fromStart = get_ctx_heapstart(ctx);
    var fromLimit = get_ctx_heaplimit(ctx);

    // Get the size of heap to use
    // Note: this may differ from the current heap size
    var heapSize = get_ctx_heapsize(ctx);
    
    //iir.trace_print('allocating heap of size:');
    //printInt(iir.icast(IRType.pint, heapSize));

    // Allocate a memory block for the to-space
    var toStart = malloc(iir.icast(IRType.pint, heapSize));

    //iir.trace_print('allocated to-space block:');
    //printPtr(toStart);

    assert (
        toStart !== NULL_PTR,
        'failed to allocate to-space heap'
    );

    // Compute the to-space heap limit
    var toLimit = toStart + heapSize;

    // Set the to-space heap parameters in the context
    set_ctx_tostart(ctx, toStart);
    set_ctx_tolimit(ctx, toLimit);
    set_ctx_tofree(ctx, toStart);

    //iir.trace_print('visiting context roots');

    // Visit the context roots
    gc_visit_ctx(ctx);
    */

    writeln("visiting stack roots");

    // Visit the stack roots
    visitStackRoots(interp);

    writeln("scanning to-space");

    /*
    // Scan Pointer: All objects behind it (i.e. to its left) have been fully
    // processed; objects in front of it have been copied but not processed.
    // Free Pointer: All copied objects are behind it; Space to its right is free

    // Initialize the scan pointer at the to-space heap start
    var scanPtr = toStart;

    // Until the to-space scan is complete
    for (var numObjs = pint(0);; ++numObjs)
    {
        //iir.trace_print('scanning object');

        // Get the current free pointer
        var freePtr = get_ctx_tofree(ctx);

        // If we are past the free pointer, scanning done
        if (scanPtr >= freePtr)
            break;

        // Get the current object reference
        var objPtr = alignPtr(scanPtr, HEAP_ALIGN);
        var objRef = iir.icast(IRType.ref, objPtr);        

        if (objPtr < toStart || objPtr >= toLimit)
        {
            iir.trace_print('object pointer past to-space limit');
            error(0);
        }

        var objSize = sizeof_layout(objRef);
        if (objPtr + objSize > toLimit)
        {
            iir.trace_print('object extends past to-space limit');
            error(0);
        }

        // Visit the object layout, forward its references
        gc_visit_layout(objRef);

        // Get the object size
        var objSize = sizeof_layout(objRef);

        // Move to the next object
        scanPtr = objPtr + objSize;
    }

    //iir.trace_print('objects copied/scanned:');
    //printInt(numObjs);

    // Flip the from-space and to-space
    // Set the heap start, limit and free pointers in the context
    set_ctx_heapstart(ctx, toStart);
    set_ctx_heaplimit(ctx, toLimit);
    set_ctx_freeptr(ctx, get_ctx_tofree(ctx));

    // For debugging, clear the old heap
    //for (var p = fromStart; p < fromLimit; p += pint(1))
    //    iir.store(IRType.u8, p, pint(0), u8(0x00));

    // Free the from-space heap block
    free(fromStart);
    */

    //var endTime = currentTimeMillis();
    //var gcTime = endTime - startTime;
    //iir.trace_print('gc time (ms):');
    //printInt(unboxInt(gcTime));

    /*
    // Clear the to-space information
    set_ctx_tostart(ctx, NULL_PTR);
    set_ctx_tolimit(ctx, NULL_PTR);
    set_ctx_tofree(ctx, NULL_PTR);
    */

    writeln("leaving gcCollect");
}

/**
Function to forward a memory object. The argument is an unboxed reference.
*/
refptr gcForward(refptr ptr)
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

    /*
    // Get the to-space heap extents
    var toStart = get_ctx_tostart(ctx);
    var toLimit = get_ctx_tolimit(ctx);

    // Get the forwarding pointer in the object
    var nextPtr = get_layout_next(ref);

    // If the object is already forwarded
    if (nextPtr >= toStart && nextPtr < toLimit)
    {
        //iir.trace_print('already forwarded');

        // Use the forwarding pointer as the new address
        var newAddr = iir.icast(IRType.ref, nextPtr);
    }
    else
    {
        //iir.trace_print('copying');

        // Copy the object into the to-space
        var newAddr = gcCopy(ref, sizeof_layout(ref), HEAP_ALIGN);
    }

    var newPtr = iir.icast(IRType.rptr, newAddr);
    assert (
        newPtr >= toStart && newPtr < toLimit,
        'forwarded address outside of to-space'
    );

    return newAddr;
    */

    // TODO
    return null;
}

/**
Copy a live object into the to-space.
*/
refptr gcCopy(refptr ptr, size_t size)
{
    /*
    var objPtr = iir.icast(IRType.rptr, ref);

    //iir.trace_print('copying object:');
    //printPtr(objPtr);

    assert (
        ptrInHeap(objPtr) === true,
        'gcCopy: object not in heap'
    );

    // Get the to-space heap parameters
    var heapStart = get_ctx_tostart(ctx);
    var heapLimit = get_ctx_tolimit(ctx);
    var freePtr = get_ctx_tofree(ctx);

    // Align the free pointer to get the new address
    var newAddr = alignPtr(freePtr, align);

    assert (
        newAddr >= heapStart && newAddr < heapLimit,
        'new address outside of to-space heap'
    );

    // Compute the next allocation pointer
    var nextPtr = newAddr + size;

    assert (
        nextPtr <= heapLimit,
        'cannot copy in to-space, heap limit exceeded'
    );

    // Copy the object to the to-space
    memCopy(newAddr, iir.icast(IRType.rptr, ref), size);

    // Update the free pointer in the context
    set_ctx_tofree(ctx, nextPtr);

    // Write the forwarding pointer in the old object
    set_layout_next(ref, newAddr);

    // Return the to-space pointer
    return iir.icast(IRType.ref, newAddr);
    */

    // TODO
    return null;
}

/**
Function to test if a pointer points inside the heap
*/
bool ptrInHeap(Interp interp, refptr ptr)
{
    /*    
    // Get the from and to-space heap extents
    var fromStart = get_ctx_heapstart(ctx);
    var fromLimit = get_ctx_heaplimit(ctx);
    var toStart = get_ctx_tostart(ctx);
    var toLimit = get_ctx_tolimit(ctx);

    return (
        (ptr >= fromStart && ptr < fromLimit) ||
        (ptr >= toStart && ptr < toLimit)
    );
    */

    // TODO
    return false;
}

/**
Walk the stack and forward references to the to-space
*/
void visitStackRoots(Interp interp)
{
    // TODO: gcForward all references on the stack



}

//============================================================================
//============================================================================

/**
Allocate a memory block of a given size on the heap
*/
/*
function heapAlloc(size)
{
    assert (
        get_ctx_tostart(ctx) === NULL_PTR,
        'heapAlloc called during GC'
    );

    // Get the heap parameters
    var heapStart = get_ctx_heapstart(ctx);
    var heapLimit = get_ctx_heaplimit(ctx);
    var freePtr = get_ctx_freeptr(ctx);

    assert (
        freePtr <= heapLimit,
        'free ptr past heap limit'
    );

    // Align the allocation pointer
    freePtr = alignPtr(freePtr, HEAP_ALIGN);

    // Compute the next allocation pointer
    var nextPtr = freePtr + size;

    //printInt(iir.icast(IRType.pint, size));
    //printPtr(nextPtr);
    //printPtr(heapLimit);

    // If this allocation exceeds the heap limit
    if (nextPtr > heapLimit)
    {
        // Log that we are going to perform GC
        puts('Performing garbage collection');

        // Call the garbage collector
        gcCollect();

        // Get the new heap parameters
        var heapStart = get_ctx_heapstart(ctx);
        var heapLimit = get_ctx_heaplimit(ctx);
        var freePtr = get_ctx_freeptr(ctx);

        assert (
            freePtr >= heapStart && freePtr < heapLimit,
            'free pointer outside of heap after GC'
        );

        // Align the allocation pointer
        freePtr = alignPtr(freePtr, HEAP_ALIGN);

        // Compute the next allocation pointer
        var nextPtr = freePtr + size;

        // If this allocation still exceeds the heap limit
        if (nextPtr > heapLimit)
        {
            // Report an error and abort
            error('allocation exceeds heap limit');
        }
    }

    assert (
        freePtr >= heapStart && freePtr < heapLimit,
        'new address outside of heap'
    );

    // Update the allocation pointer in the context object
    set_ctx_freeptr(ctx, nextPtr);

    // Allocate the object at the current position
    return freePtr;
}
*/

/**
Visit a machine code block and its references
*/
/*
function gcVisitMCB(funcPtr, offset)
{
    "tachyon:static";
    "tachyon:noglobal";
    "tachyon:arg funcPtr rptr";
    "tachyon:arg offset pint";

    //iir.trace_print('visiting mcb');
    //printPtr(funcPtr);

    // Get the address of the machine code block start
    var mcbPtr = funcPtr - offset;

    // Get the garbage collection count
    var ctx = iir.get_ctx();
    var gcCount = get_ctx_gccount(ctx);

    var lastCol = iir.load(IRType.u32, mcbPtr, pint(0));

    // If this block has been visited in this collection, stop
    if (lastCol === gcCount)
    {
        //iir.trace_print('already visited');
        return; 
    }

    // Mark the block as visited
    iir.store(IRType.u32, mcbPtr, pint(0), gcCount);

    // Load the offset to the ref entries
    var dataOffset = iir.icast(IRType.pint, iir.load(IRType.u32, mcbPtr, pint(4)));

    // Load the number of ref entries
    var numEntries = iir.icast(IRType.pint, iir.load(IRType.u32, mcbPtr, pint(8)));

    // For each reference entry
    for (var i = pint(0); i < numEntries; ++i)
    {
        // Load the reference offset and kind
        var offset = iir.icast(IRType.pint, iir.load(IRType.u32, mcbPtr, dataOffset + i * MCB_REF_ENTRY_SIZE));
        var kind = iir.load(IRType.u32, mcbPtr, dataOffset + i * MCB_REF_ENTRY_SIZE + pint(4));

        // Function pointer
        if (kind === u32(1))
        {
            gcVisitFptr(mcbPtr, offset);
        }

        // Ref
        if (kind === u32(2))
        {
            gcVisitRef(mcbPtr, offset);
        }

        // Box
        else if (kind === u32(3))
        {
            gcVisitBox(mcbPtr, offset);
        }
    }
}
*/

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

