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

module stats;

import std.stdio;
import std.datetime;
import std.string;
import std.array;
import std.stdint;
import std.conv;
import options;

/// Program start time in milliseconds
private ulong startTimeMsecs = 0;

/// Total compilation time in microseconds
ulong compTimeUsecs = 0;

/// Total size of the machine code generated in bytes
ulong machineCodeBytes = 0;

/// Total number of blocks compiled
ulong numBlocks = 0;

/// Total number of versions compiled
ulong numVersions = 0;

/// Number of unjitted instructions executed (dynamic)
ulong numUnjitInstrs = 0;

/// Number of call instruction bailouts (dynamic)
ulong numCallBailouts = 0;

/// Number of return instruction bailouts (dynamic)
ulong numRetBailouts = 0;

/// Number of instructions executed by the interpreter (dynamic)
ulong numInterpCycles = 0;

/// Number of type tests executed by test kind (dynamic)
ulong* numTypeTests[string];

/// Get a pointer to the counter variable associated with a type test
ulong* getTypeTestCtr(string testOp)
{
    // If there is no counter for this op, allocate one
    if (testOp !in numTypeTests)
        numTypeTests[testOp] = new ulong;

    // Return the counter for this test op
    return numTypeTests[testOp];
}

/// Static module constructor
static this()
{
    // Pre-register type test counters
    getTypeTestCtr("is_i32");
    getTypeTestCtr("is_i64");
    getTypeTestCtr("is_f64");
    getTypeTestCtr("is_const");
    getTypeTestCtr("is_refptr");
    getTypeTestCtr("is_rawptr");

    // Record the starting time
    startTimeMsecs = Clock.currAppTick().msecs();
}

/// Static module destructor, log the accumulated stats
static ~this()
{
    // If stats not enabled, stop
    if (opts.stats is false)
        return;

    auto endTimeMsecs = Clock.currAppTick().msecs();
    auto execTimeMsecs = endTimeMsecs - startTimeMsecs;

    auto versToBlocks = cast(double)numVersions / cast(double)numBlocks;

    writeln();
    writefln("exec time (ms): %s", execTimeMsecs);
    writefln("comp time (ms): %s", compTimeUsecs / 1000);
    writefln("code size (bytes): %s", machineCodeBytes);
    writefln("vers / block: %s", versToBlocks);
    writefln("unjit instrs: %s", numUnjitInstrs);
    writefln("call bailouts: %s", numCallBailouts);
    writefln("ret bailouts: %s", numRetBailouts);
    writefln("interp cycles: %s", numInterpCycles);

    auto totalTypeTests = 0;
    foreach (testOp, pCtr; numTypeTests)
    {
        auto ctr = *pCtr;
        writefln("%s: %s", testOp, ctr);
        totalTypeTests += ctr;
    }
    writefln("type tests: %s", totalTypeTests);
}

