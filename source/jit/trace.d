/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module jit.trace;

import std.stdio;
import std.stdint;
import options;
import ir.ir;
import interp.interp;
import jit.codeblock;
import jit.jit;

const TRACE_RECORD_COUNT = 500;

const TRACE_VISIT_COUNT = 20;

const TRACE_RECORD_COUNT_SUBS = 500;

const TRACE_VISIT_COUNT_SUBS = 20;

const TRACE_MAX_DEPTH = 512;

/// Trace entry function pointer
alias void function() EntryFn;

/**
Compiled code trace
*/
class Trace
{
    /// Trace start node
    TraceNode startNode;

    /// Trace start node of the trace root
    TraceNode rootNode;

    /// Parent trace
    Trace parent;

    /// Code generation context passed by the parent trace
    CodeGenCtx* subCtx;

    /// Map of jump addresses to sub-traces
    Trace[ubyte*] subTraces;

    /// References to code generation contexts for sub-traces
    CodeGenCtx*[] subCtxs;

    /// Compiled code block
    CodeBlock codeBlock = null;

    /// Trace entry function, used as an entry point by the interpreter
    EntryFn entryFn = null;

    /// Trace join point machine code pointer
    ubyte* joinPoint = null;

    /// Parent trace code patched to jump to this trace
    ubyte* patchPtr = null;

    /// Root trace constructor
    this(IRBlock startBlock)
    {
        this.startNode = new TraceNode(startBlock);
        this.rootNode = this.startNode;

        this.parent = null;
        this.subCtx = null;
        this.patchPtr = null;
    }

    /// Sub-trace constructor
    this(
        IRBlock startBlock, 
        Trace parent,
        TraceNode branchNode, 
        CodeGenCtx* subCtx, 
        ubyte* patchPtr
    )
    {
        this.startNode = branchNode.getSucc(startBlock);
        this.rootNode = parent.rootNode;

        this.parent = parent;
        this.subCtx = subCtx;
        this.patchPtr = patchPtr;
    }
}

/**
Trace node, used for trace construction/profiling
*/
class TraceNode
{
    /// Associated block
    IRBlock block;

    /// Trace root block for this trace tree
    IRBlock rootBlock;

    /// Depth away from the tree root
    uint32_t treeDepth;

    /// Call stack depth
    uint32_t stackDepth;

    /// List of successors (blocks this has branched to)
    TraceNode[] succs;

    /// Visit count (number of times traced)
    uint32_t count = 0;

    /**
    Root node constructor
    */
    this(IRBlock block)
    {
        this.block = block;
        this.rootBlock = block;
        this.treeDepth = 0;
        this.stackDepth = 0;
    }

    /**
    Child node constructor
    */
    this(IRBlock block, TraceNode parent)
    {
        this.block = block;
        this.rootBlock = parent.rootBlock;
        this.treeDepth = parent.treeDepth + 1;

        // Compute the stack depth relative to the parent
        auto branch = parent.block.lastInstr;
        if (branch.opcode.isCall)
            stackDepth = parent.stackDepth + 1;
        else if (branch.opcode == &RET)
            stackDepth = parent.stackDepth - 1;
        else
            stackDepth = parent.stackDepth;
    }

    /// Start recording a trace at this block
    static TraceNode record(Interp interp, IRBlock target)
    {
        //writefln("recording from %s", target.fun.getName());

        // If there is no trace object for this target
        if (target.trace is null)
        {
            target.trace = new Trace(target);
            return target.trace.startNode;
        }

        // If enough trace information was recorded about
        // traces starting from this node
        if (target.trace.startNode.count >= TRACE_VISIT_COUNT &&
            target.trace.entryFn is null)
        {
            // Compile a trace for this block
            compTrace(interp, target.trace);

            // Stop recording traces at this node
            return null;
        }

        return target.trace.startNode;
    }

    /// Continue the tracing process at a given target block
    TraceNode traceTo(Interp interp, IRBlock target)
    {
        // Increment the visit count for this node
        count++;

        // If we are at the max trace depth, stop
        if (treeDepth >= TRACE_MAX_DEPTH)
            return null;

        // If this block returns from stack depth 0, stop
        if (stackDepth == 0 && block.lastInstr.opcode == &RET)
            return null;

        // If we are going back to the trace root block at stack depth 0
        if (target is rootBlock && stackDepth == 0)
        {
            // Add a last successor for the root node
            auto succ = getSucc(target);
            succ.count++;

            // If no trace is compiled for the trace root
            if (rootBlock.trace.codeBlock is null)
            {
                // Record a new trace starting from the root
                return record(interp, rootBlock);
            }
            else
            {
                // Stop the trace recording
                return null;
            }
        }

        // Get the successor for this target
        return getSucc(target);
    }

    /// Get the successor node corresponding to the target
    TraceNode getSucc(IRBlock block)
    {
        foreach (succ; succs)
        {
            if (succ.block is block)
                return succ;
        }

        auto succ = new TraceNode(block, this);
        succs ~= succ;

        return succ;
    }

    /// Get the most visited successor
    TraceNode getMostVisited()
    {
        TraceNode mostVisited = null;

        foreach (succ; succs)
        {
            if (!mostVisited || succ.count > mostVisited.count)
                mostVisited = succ;
        }

        return mostVisited;
    }
}

