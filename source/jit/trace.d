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

const TRACE_VISIT_COUNT = 100;

const TRACE_MAX_DEPTH = 512;

/// Trace entry function pointer
alias void function() EntryFn;

/**
Compiled code trace
*/
class Trace
{
    /// Trace code block
    CodeBlock codeBlock = null;

    /// Trace entry function, used as an entry point by the interpreter
    EntryFn entryFn = null;

    // Trace join point code pointer
    ubyte* joinPoint = null;

    // TODO: list of sub-traces?
    //Trace[] subTraces;
}

/**
Trace node, used for trace construction/profiling
*/
class TraceNode
{
    /// Associated block
    IRBlock block;

    /// Tree root node
    TraceNode root;

    /// Depth away from the tree root
    uint32_t depth;

    /// Call stack depth
    uint32_t stackDepth;

    /// List of successors (blocks this has branched to)
    TraceNode[] succs;

    /// Visit count
    uint32_t count = 0;

    /**
    Root node constructor
    */
    this(IRBlock block)
    {
        this.block = block;
        this.root = this;
        this.depth = 0;
        this.stackDepth = 0;
    }

    /**
    Child node constructor
    */
    this(IRBlock block, TraceNode parent)
    {
        this.block = block;
        this.root = parent.root;
        this.depth = parent.depth + 1;

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

        // If there is no trace node for this target
        if (target.traceNode is null)
        {
            target.traceNode = new TraceNode(target);
            return target.traceNode;
        }

        // If enough trace information was recorded about
        // traces starting from this node
        if (target.traceNode && target.traceNode.count >= TRACE_VISIT_COUNT)
        {
            // Compile a trace for this block
            compTrace(interp, target.traceNode);

            // Stop recording traces at this node
            target.traceNode = null;
            return null;
        }

        return target.traceNode;
    }

    /// Continue the tracing process at a given target block
    TraceNode traceTo(Interp interp, IRBlock target)
    {
        // Increment the visit count for this node
        count++;

        // If we are at the max trace depth, stop
        if (depth >= TRACE_MAX_DEPTH)
            return null;

        // If this block returns from stack depth 0, stop
        if (stackDepth == 0 && block.lastInstr.opcode == &RET)
            return null;

        // If we are going back to the root block
        if (target is root.block)
        {
            // Add a last successor for the root node
            auto succ = getSucc(target);
            succ.count++;

            // Record a new trace starting from the root
            return record(interp, root.block);
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

