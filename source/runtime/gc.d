/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

module runtime.gc;

import core.memory;
import std.c.string;
import std.stdio;
import std.string;
import std.conv;
import ir.ir;
import ir.ops;
import runtime.vm;
import runtime.layout;
import runtime.string;
import runtime.object;
import util.misc;

/**
GC root object
*/
struct GCRoot
{
    this(VM vm, ValuePair pair)
    {
        this.vm = vm;

        this.prev = null;
        this.next = vm.firstRoot;
        vm.firstRoot = &this;

        this.pair = pair;
    }

    this(VM vm, Word w, Type t)
    {
        this(vm, ValuePair(w, t));
    }

    this(VM vm, refptr p, Type t)
    {
        assert (isHeapPtr(t));
        this(vm, Word.ptrv(p), t);
    }

    @disable this();

    ~this()
    {
        assert (
            vm !is null,
            "vm is null"
        );

        if (prev)
            prev.next = next;
        else
            this.vm.firstRoot = next;

        if (next)
            next.prev = prev;
    }

    GCRoot* opAssign(ValuePair v)
    {
        pair = v;
        return &this;
    }

    GCRoot* opAssign(GCRoot v)
    {
        pair = v.pair;
        return &this;
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

    private VM vm;

    private GCRoot* prev;
    private GCRoot* next;

    ValuePair pair;
}

/**
Check that a pointer points in a VM's from-space heap
*/
bool inFromSpace(VM vm, refptr ptr)
{
    return (ptr >= vm.heapStart && ptr < vm.heapLimit);
}

/**
Check that a pointer points in a VM's to-space heap
*/
bool inToSpace(VM vm, refptr ptr)
{
    return (ptr >= vm.toStart && ptr < vm.toLimit);
}

/**
Check that a pointer points to a valid chunk of memory
*/
bool ptrValid(refptr ptr)
{
    // Query the D GC regarding this pointer
    return GC.query(ptr) != GC.BlkInfo.init;
}

/**
Allocate an object in the heap
*/
refptr heapAlloc(VM vm, size_t size)
{
    // If this allocation exceeds the heap limit
    if (vm.allocPtr + size > vm.heapLimit)
    {
        //writefln("gc on alloc of size %s", size);

        // Perform garbage collection
        gcCollect(vm);

        //writefln("gc done");

        // While this allocation exceeds the heap limit
        while (vm.allocPtr + size > vm.heapLimit)
        {
            auto newHeapSize = 2 * vm.heapSize;

            writeln(
                "heap space exhausted, expanding heap to ",
                newHeapSize / (1024 * 1024),
                "MiB"
            );

            // Double the size of the heap
            gcCollect(vm, newHeapSize);
        }
    }

    // Store the pointer to the new object
    refptr ptr = vm.allocPtr;

    // Update and align the allocation pointer
    vm.allocPtr = alignPtr(vm.allocPtr + size);

    assert (inFromSpace(vm, ptr));

    // Return the object pointer
    return ptr;
}

/**
Perform a garbage collection
*/
void gcCollect(VM vm, size_t heapSize = 0)
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

    if (heapSize != 0)
        vm.heapSize = heapSize;

    //writefln("allocating to-space heap of size: %s", vm.heapSize);

    // Allocate a memory block for the to-space
    vm.toStart = cast(ubyte*)GC.malloc(
        vm.heapSize,
        GC.BlkAttr.NO_SCAN |
        GC.BlkAttr.NO_INTERIOR
    );

    assert (
        vm.toStart != null,
        "failed to allocate to-space heap"
    );

    // Zero-out the to-space
    // Note: the runtime relies on this behavior to
    // avoid initializing all object and array fields
    memset(vm.toStart, 0, vm.heapSize);

    // Compute the to-space heap limit
    vm.toLimit = vm.toStart + vm.heapSize;

    // Initialize the to-space allocation pointer
    vm.toAlloc = vm.toStart;

    //writeln("visiting root objects");

    // Forward the root objects
    vm.objProto.word.ptrVal     = gcForward(vm, vm.objProto.word.ptrVal);
    vm.arrProto.word.ptrVal     = gcForward(vm, vm.arrProto.word.ptrVal);
    vm.funProto.word.ptrVal     = gcForward(vm, vm.funProto.word.ptrVal);
    vm.globalObj.word.ptrVal    = gcForward(vm, vm.globalObj.word.ptrVal);

    //writeln("visiting stack roots");

    // Visit the stack roots
    visitStackRoots(vm);

    //writeln("visiting link table");

    // Visit the link table cells
    for (size_t i = 0; i < vm.linkTblSize; ++i)
    {
        vm.wLinkTable[i] = gcForward(
            vm,
            vm.wLinkTable[i],
            vm.tLinkTable[i]
        );
    }

    //writeln("visiting GC root objects");

    // Visit the root objects
    for (GCRoot* pRoot = vm.firstRoot; pRoot !is null; pRoot = pRoot.next)
        pRoot.pair.word = gcForward(vm, pRoot.pair.word, pRoot.pair.type);    

    //writeln("scanning to-space");

    // Scan Pointer: All objects behind it (i.e. to its left) have been fully
    // processed; objects in front of it have been copied but not processed.
    // Free Pointer: All copied objects are behind it; Space to its right is free

    // Initialize the scan pointer at the to-space heap start
    auto scanPtr = vm.toStart;

    // Until the to-space scan is complete
    size_t numObjs;
    for (numObjs = 0;; ++numObjs)
    {
        // If we are past the free pointer, scanning done
        if (scanPtr >= vm.toAlloc)
            break;

        assert (
            vm.inToSpace(scanPtr),
            "scan pointer past to-space limit"
        );

        // Get the object size
        auto objSize = layout_sizeof(scanPtr);

        assert (
            scanPtr + objSize <= vm.toLimit,
            "object extends past to-space limit"
        );

        //writefln("scanning object of size %s", objSize);
        //writefln("scanning %s (%s)", scanPtr, numObjs);
        //writefln("obj header: %s", obj_get_header(scanPtr));

        // Visit the object layout, forward its references
        layout_visit_gc(vm, scanPtr);

        //writeln("visited layout");

        // Move to the next object
        scanPtr = alignPtr(scanPtr + objSize);
    }

    //writefln("objects copied/scanned: %s", numObjs);

    // Store a pointer to the from-space heap
    auto fromStart = vm.heapStart;

    // Make the to-space the new from-space
    vm.heapStart = vm.toStart;
    vm.heapLimit = vm.toLimit;
    vm.allocPtr = vm.toAlloc;

    // Clear the to-space information
    vm.toStart = null;
    vm.toLimit = null;
    vm.toAlloc = null;

    //writefln("rebuilding string table");

    // Store a pointer to the old string table
    auto oldStrTbl = vm.strTbl;
    auto strTblCap = strtbl_get_cap(oldStrTbl);

    // Allocate a new string table
    vm.strTbl = strtbl_alloc(vm, strTblCap);

    // Add only the forwarded strings to the new string table
    for (uint32 i = 0; i < strTblCap; ++i)
    {
        auto ptr = strtbl_get_str(oldStrTbl, i);
        if (ptr is null)
            continue;

        auto next = obj_get_next(ptr);
        if (next is null)
            continue;

        getTableStr(vm, next);
    }

    // Free the from-space heap block
    GC.free(fromStart);

    //writefln("old live funs count: %s", vm.funRefs.length);

    // Collect the dead functions
    foreach (ptr, fun; vm.funRefs)
        if (ptr !in vm.liveFuns)
            collectFun(vm, fun);

    // Swap the function reference sets
    vm.funRefs = vm.liveFuns;
    vm.liveFuns.clear();

    // Collect the dead maps
    foreach (ptr, map; vm.mapRefs)
        if (ptr !in vm.liveMaps)
            collectMap(vm, map);

    // Swap the map reference sets
    vm.mapRefs = vm.liveMaps;
    vm.liveMaps.clear();

    //writefln("new live funs count: %s", vm.funRefs.length);

    // Increment the garbage collection count
    vm.gcCount++;

    //writeln("leaving gcCollect");
    //writefln("free space: %s", (vm.heapLimit - vm.allocPtr));
}

/**
Function to forward a memory object. The argument is an unboxed reference.
*/
refptr gcForward(VM vm, refptr ptr)
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

    //writefln("forwarding object %s (%s)", ptr, vm.inFromSpace(ptr));

    assert (
        vm.inFromSpace(ptr),
        format(
            "gcForward: object not in from-space heap\n" ~
            "ptr   : %s\n" ~
            "start : %s\n" ~
            "limit : %s\n" ~
            "header: %s",
            ptr,
            vm.heapStart,
            vm.heapLimit,
            (ptrValid(ptr)? to!string(obj_get_header(ptr)):"???")
        )
    );

    // If this is a closure
    auto header = obj_get_header(ptr);
    if (header == LAYOUT_CLOS)
    {
        auto fun = getFunPtr(ptr);
        assert (fun !is null);
        visitFun(vm, fun);

        auto map = cast(ObjMap)clos_get_ctor_map(ptr);
        if (map !is null)
            visitMap(vm, map);
    }

    // If this is an object of some kind
    if (header == LAYOUT_OBJ || header == LAYOUT_ARR || header == LAYOUT_CLOS)
    {
        auto map = cast(ObjMap)obj_get_map(ptr);
        assert (map !is null);
        visitMap(vm, map);
    }

    // Follow the next pointer chain as long as it points in the from-space
    refptr nextPtr = ptr;
    for (;;)
    {
        // Get the next pointer
        nextPtr = obj_get_next(nextPtr);

        // If the next pointer is outside of the from-space
        if (vm.inFromSpace(nextPtr) is false)
            break;

        // Follow the next pointer chain
        ptr = nextPtr;

        assert (
            ptr !is null, 
            "object pointer is null"
        );
    } 

    // If the object is not already forwarded to the to-space
    if (nextPtr is null)
    {
        //writefln("copying");

        // Copy the object into the to-space
        nextPtr = gcCopy(vm, ptr, layout_sizeof(ptr));

        assert (
            obj_get_next(ptr) == nextPtr, 
            "next pointer not set"
        );
    }

    assert (
        vm.inToSpace(nextPtr),
        format(
            "gcForward: next pointer is outside of to-space\n" ~
            "objPtr  : %s\n" ~
            "nextPtr : %s\n" ~
            "to-start: %s\n" ~
            "to-limit: %s\n",
            ptr,
            nextPtr,
            vm.toStart,
            vm.toLimit,
        )
    );

    //writefln("object forwarded");

    // Return the forwarded pointer
    return nextPtr;
}

/**
Forward a word/value pair
*/
Word gcForward(VM vm, Word word, Type type)
{
    // Switch on the type tag
    switch (type)
    {
        // Heap reference pointer
        // Forward the pointer
        case Type.REFPTR:
        case Type.OBJECT:
        case Type.ARRAY:
        case Type.CLOSURE:
        case Type.STRING:
        return Word.ptrv(gcForward(vm, word.ptrVal));

        // Function pointer (IRFunction)
        // Return the pointer unchanged
        case Type.FUNPTR:
        auto fun = word.funVal;
        assert (fun !is null, "null IRFunction pointer");
        visitFun(vm, fun);
        return word;

        // Map pointer (ClassMap)
        // Return the pointer unchanged
        case Type.MAPPTR:
        auto map = word.mapVal;
        assert (map !is null);
        visitMap(vm, map);
        return word;

        // Return address
        case Type.RETADDR:
        assert (
            word.ptrVal in vm.retAddrMap,
            format("ret addr not found: %s", word.ptrVal)
        );
        auto retEntry = vm.retAddrMap[word.ptrVal];
        auto fun = retEntry.callCtx.fun;
        visitFun(vm, fun);
        return word;

        // Return the word unchanged
        default:
        return word;
    }
}

/**
Forward a word/value pair
*/
uint64 gcForward(VM vm, uint64 word, uint8 type)
{
    // Forward the pointer
    return gcForward(vm, Word.uint64v(word), cast(Type)type).uint64Val;
}

/**
Copy a live object into the to-space.
*/
refptr gcCopy(VM vm, refptr ptr, size_t size)
{
    assert (
        vm.inFromSpace(ptr),
        format(
            "gcCopy: object not in from-space heap\n" ~
            "ptr   : %s\n" ~
            "start : %s\n" ~
            "limit : %s\n" ~
            "header: %s",
            ptr,
            vm.heapStart,
            vm.heapLimit,
            obj_get_header(ptr)
        )
    );

    assert (
        obj_get_next(ptr) == null,
        "next pointer in object to forward is not null"
    );

    // The object will be copied at the to-space allocation pointer
    auto nextPtr = vm.toAlloc;

    assert (
        nextPtr + size <= vm.toLimit,
        format(
            "cannot copy in to-space, heap limit exceeded\n" ~
            "ptr     : %s\n" ~
            "size    : %s\n" ~
            "fr-limit: %s\n" ~
            "to-alloc: %s\n" ~
            "to-limit: %s\n" ~
            "header  : %s",
            ptr,
            size,
            vm.heapLimit,
            vm.toAlloc,
            vm.toLimit,
            obj_get_header(ptr)
        )
    );

    // Update the allocation pointer
    vm.toAlloc += size;
    vm.toAlloc = alignPtr(vm.toAlloc);

    // Copy the object to the to-space
    for (size_t i = 0; i < size; ++i)
        nextPtr[i] = ptr[i];

    assert (
        vm.inToSpace(nextPtr),
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
void visitStackRoots(VM vm)
{
    auto visitFrame = delegate void(
        IRFunction fun,
        Word* wsp,
        Type* tsp,
        size_t depth,
        size_t frameSize,
        IRInstr curInstr
    )
    {
        /// Forward a value at a given index in the current frame
        void forward(StackIdx idx)
        {
            assert (idx < frameSize);

            //writefln("ref %s/%s", idx, frameSize);

            Word word = wsp[idx];
            Type type = tsp[idx];

            //writefln("type: %s", type);

            // If this is a pointer, forward it
            wsp[idx] = gcForward(vm, word, type);

            auto fwdPtr = wsp[idx].ptrVal;

            assert (
                !isHeapPtr(type) ||
                fwdPtr == null ||
                vm.inToSpace(fwdPtr),
                format(
                    "invalid forwarded stack pointer\n" ~
                    "ptr     : %s\n" ~
                    "to-alloc: %s\n" ~
                    "to-limit: %s",
                    fwdPtr,
                    vm.toStart,
                    vm.toLimit
                )
            );
        }

        //writeln("visiting frame for: ", fun.getName());
        //writeln("frame size: ", frameSize);
        //writeln("\n", fun, "\n");

        // Visit the function this stack frame belongs to
        visitFun(vm, fun);

        // Get the values live at the current instruction
        IRDstValue[] liveVals;
        if (depth is 0)
            liveVals = fun.liveInfo.valsLiveBefore(curInstr);
        else
            liveVals = fun.liveInfo.valsLiveAfter(curInstr);

        // For each live value
        foreach (val; liveVals)
        {
            // The current instruction hasn't completed, skip it
            if (val is curInstr)
                continue;

            // Hidden argument values will be forwarded later
            if (val is fun.closVal || 
                val is fun.thisVal ||
                val is fun.raVal   ||
                val is fun.argcVal)
                continue;

            // Forward the value
            //writeln(val);
            forward(val.outSlot);
        }

        // If this is not a primitive
        if (fun.isPrim is false)
        {
            // Forward the closure pointer
            // Note: the closure pointer is not type tagged
            auto closIdx = fun.closVal.outSlot;
            wsp[closIdx] = gcForward(vm, wsp[closIdx], Type.CLOSURE);

            // Forward the "this" pointer
            forward(fun.thisVal.outSlot);
        }

        // Forward the return address
        // Note: the return address is not type tagged
        auto raIdx = fun.raVal.outSlot;
        wsp[raIdx] = gcForward(vm, wsp[raIdx], Type.RETADDR);

        //writeln("done visiting frame");
    };

    vm.visitStack(visitFrame);

    //writefln("done scanning stack");
}

/**
Visit a function and its sub-functions
*/
void visitFun(VM vm, IRFunction fun)
{
    // If this function was already visited, stop
    if (cast(void*)fun in vm.liveFuns)
        return;

    // Add the function to the set of live functions
    vm.liveFuns[cast(void*)fun] = fun;

    // Transitively find live function references inside the function
    for (IRBlock block = fun.firstBlock; block !is null; block = block.next)
    {
        for (IRInstr instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            for (size_t argIdx = 0; argIdx < instr.numArgs; ++argIdx)
            {
                auto arg = instr.getArg(argIdx);

                if (auto funArg = cast(IRFunPtr)arg)
                {
                    if (funArg.fun !is null)
                        visitFun(vm, funArg.fun);
                }

                else if (auto mapArg = cast(IRMapPtr)arg)
                {
                    if (mapArg.map !is null)
                        visitMap(vm, mapArg.map);
                }
            }
        }
    }
}

/**
Collect resources held by a dead function
*/
void collectFun(VM vm, IRFunction fun)
{
    //writefln("freeing dead function: \"%s\"", fun.name);

    // For each basic block
    for (IRBlock block = fun.firstBlock; block !is null; block = block.next)
    {
        // For each instruction
        for (IRInstr instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // For each instruction argument
            for (size_t argIdx = 0; argIdx < instr.numArgs; ++argIdx)
            {
                auto arg = instr.getArg(argIdx);

                // If this is a link table entry, free it
                if (auto linkArg = cast(IRLinkIdx)arg)
                {
                    if (linkArg.hasOneUse && linkArg.linkIdx != NULL_LINK)
                    {
                        //writefln("freeing link table entry %s", arg.linkIdx);
                        vm.freeLink(linkArg.linkIdx);
                    }
                }

                // Remove this argument reference
                instr.remArg(argIdx);
            }
        }
    }

    //writefln("destroying function: \"%s\" (%s)", fun.getName, cast(void*)fun);

    // Destroy the function
    destroy(fun);
}

/**
Visit a map
*/
void visitMap(VM vm, ObjMap map)
{
    // Add the map to the live set
    vm.liveMaps[cast(void*)map] = map;
}

/**
Collect resources held by a dead map
*/
void collectMap(VM vm, ObjMap map)
{
    destroy(map);
}

