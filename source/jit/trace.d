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
import jit.codeblock;

const TRACE_RECORD_COUNT = 500;

const TRACE_VISIT_COUNT = 100;

const TRACE_MAX_DEPTH = 128;

/// Trace entry function pointer
alias void function() EntryFn;

/**
Compiled code trace
*/
class Trace
{
    // TODO: remove
    /// Outgoing branch counters
    uint64_t[2] counters = [0, 0];

    /// List of basic blocks chained in this trace
    IRBlock[] blockList;

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

    /// Visit count
    uint32_t count = 0;

    /// List of children (blocks this has branched to)
    TraceNode[] children;

    this(IRBlock block)
    {
        this.block = block;
        this.depth = 0;
        this.root = this;
    }

    this(IRBlock block, TraceNode parent)
    {
        this.block = block;
        this.root = parent.root;
        this.depth = parent.depth + 1;
    }

    /// Continue the tracing process at a given target block
    TraceNode traceTo(IRBlock target)
    {
        // Increment the visit count for this node
        count++;

        // If we are at the max trace depth, stop
        if (depth >= TRACE_MAX_DEPTH)
            return null;

        // Get the child node corresponding to the target
        return getChild(target);
    }

    TraceNode getChild(IRBlock block)
    {
        foreach (child; children)
        {
            if (child.block is block)
                return child;
        }

        auto child = new TraceNode(block, this);
        children ~= child;

        return child;
    }
}

