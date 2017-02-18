/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2015, Maxime Chevalier-Boisvert. All rights reserved.
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

import core.sys.posix.sys.resource;
import core.time;
import std.stdio;
import std.string;
import std.array;
import std.stdint;
import std.conv;
import std.typecons;
import std.algorithm;
import options;

/// Total size of the machine code generated (in bytes)
ulong genCodeSize = 0;

/// Number of blocks for which there are compiled versions
ulong numBlocks = 0;

/// Number of block versions compiled
ulong numVersions = 0;

/// Maximum number of versions compiled for a block
ulong maxVersions = 0;

/// Number of blocks with specific version counts
ulong[ulong] numVerBlocks;

/// Number of shape objects allocated
ulong numShapes = 0;

/// Number of shape lookups with a known shape
ulong numShapeKnown = 0;

/// Number of shape tests
ulong numShapeTests = 0;

/// Number of capture_tag test executions
ulong numTagTests = 0;

/// Number of property writes
ulong numSetProp = 0;

/// Number of global property writes
ulong numSetGlobal = 0;

/// Number of host property writes
ulong numSetPropHost = 0;

/// Number of property reads
ulong numGetProp = 0;

/// Number of global property reads
ulong numGetGlobal = 0;

/// Number of host property reads
ulong numGetPropHost = 0;

/// Number of shape changes due to a type mismatch
ulong numShapeFlips = 0;

/// Number of global object shape changes due to a type mismatch
ulong numShapeFlipsGlobal = 0;

/// Number of overflow checks
ulong numOvfChecks = 0;

/// Number of heap allocations
ulong numHeapAllocs = 0;

/// Number of optimized dynamic calls
ulong numCallFast = 0;

/// Number of unoptimized dynamic calls
ulong numCallSlow = 0;

/// Number of calls performed using apply
ulong numCallApply = 0;

/// Number of functions (not closures) compiled
ulong numFunsComp = 0;

/// Number of call continuation invalidations
ulong numContInvs = 0;

/// Dynamic count of returns
ulong numRet = 0;

/// Dynamic count of known return type tags
ulong numRetTagKnown = 0;

/// Number of non-primitive calls by function name
private ulong*[string] numCalls;

/// Number of primitive calls by primitive name
private ulong*[string] numPrimCalls;

/// Number of type tests executed by test kind
private ulong*[string] numTypeTests;

/// Get a pointer to the counter variable associated with a function
ulong* getCallCtr(string funName)
{
    // If there is no counter for this primitive, allocate one
    if (funName !in numCalls)
        numCalls[funName] = new ulong;

    // Return the counter for this function
    return numCalls[funName];
}

/// Get a pointer to the counter variable associated with a primitive
ulong* getPrimCallCtr(string primName)
{
    // If there is no counter for this primitive, allocate one
    if (primName !in numPrimCalls)
        numPrimCalls[primName] = new ulong;

    // Return the counter for this primitive
    return numPrimCalls[primName];
}

/// Get a pointer to the counter variable associated with a type test
ulong* getTagTestCtr(string testOp)
{
    // If there is no counter for this op, allocate one
    if (testOp !in numTypeTests)
        numTypeTests[testOp] = new ulong;

    // Return the counter for this test op
    return numTypeTests[testOp];
}

/// Total compilation time
private Duration compTime;

/// Total execution time
private Duration execTime;

/// Total garbage collection time
private Duration gcTime;

/// Compilation timer start
private MonoTime compStart;

/// Execution timer start
private MonoTime execStart;

/// Garbage collection timer start
private MonoTime gcStart;

/// Start recording compilation time
void compTimeStart()
{
    assert (compStart == MonoTime.init, "comp timer already started");
    assert (execStart == MonoTime.init, "exec timer ongoing");

    compStart = MonoTime.currTime();
}

/// Stop recording compilation time
void compTimeStop()
{
    assert (compStart != MonoTime.init);

    auto compEnd = MonoTime.currTime();
    compTime += compEnd - compStart;

    compStart = MonoTime.init;
}

/// Start recording execution time
void execTimeStart()
{
    assert (execStart == MonoTime.init, "exec timer already started");
    assert (compStart == MonoTime.init, "comp timer ongoing");

    execStart = MonoTime.currTime();
}

/// Stop recording execution time
void execTimeStop()
{
    assert (execStart != MonoTime.init);

    auto execEnd = MonoTime.currTime();
    execTime += execEnd - execStart;

    execStart = MonoTime.init;
}

/// Check if the execution time is being recorded
bool execTimeStarted()
{
    return execStart != MonoTime.init;
}

/// Start recording garbage collection time
void gcTimeStart()
{
    assert (gcStart == MonoTime.init, "gc timer already started");

    gcStart = MonoTime.currTime();
}

/// Stop recording garbage collection time
void gcTimeStop()
{
    assert (gcStart != MonoTime.init);

    auto gcEnd = MonoTime.currTime();
    gcTime += gcEnd - gcStart;

    gcStart = MonoTime.init;
}

/// Static module constructor
static this()
{
    // Pre-register type test counters
    getTagTestCtr("is_undef");
    getTagTestCtr("is_null");
    getTagTestCtr("is_bool");
    getTagTestCtr("is_int32");
    getTagTestCtr("is_int64");
    getTagTestCtr("is_float64");
    getTagTestCtr("is_refptr");
    getTagTestCtr("is_rawptr");
}

/// Static module destructor, log the accumulated stats
static ~this()
{
    /// Print named counts sorted in decreasing order
    void sortedCounts(ulong*[string] counts, string countKind)
    {
        alias CountPair = Tuple!(string, "name", ulong, "cnt");
        CountPair[] countPairs;

        foreach (name, pCtr; counts)
            countPairs ~= CountPair(name, *pCtr);
        countPairs.sort!"a.cnt > b.cnt";

        ulong total = 0;
        foreach (pair; countPairs)
        {
            writefln("%s: %s", pair.name, pair.cnt);
            total += pair.cnt;
        }

        writefln("total %s: %s", countKind, total);
    }

    if (opts.stats || opts.perf_stats)
    {
        writeln();
        writefln("comp time (ms): %s", compTime.total!"msecs");
        writefln("exec time (ms): %s", execTime.total!"msecs");
        writefln("gc time (ms): %s", gcTime.total!"msecs");
        writefln("total time (ms): %s", compTime.total!"msecs" + execTime.total!"msecs");
        writefln("code size (bytes): %s", genCodeSize);
    }

    if (opts.stats)
    {
        writefln("num blocks: %s", numBlocks);
        writefln("num versions: %s", numVersions);
        writefln("max versions: %s", maxVersions);
        writefln("num shapes: %s", numShapes);

        writefln("num shape known: %s", numShapeKnown);
        writefln("num shape tests: %s", numShapeTests);
        writefln("num tag tests: %s", numTagTests);
        writefln("num set prop: %s", numSetProp);
        writefln("num set global: %s", numSetGlobal);
        writefln("num set prop host: %s", numSetPropHost);
        writefln("num get prop: %s", numGetProp);
        writefln("num get global: %s", numGetGlobal);
        writefln("num get prop host: %s", numGetPropHost);
        writefln("num shape flips: %s", numShapeFlips);
        writefln("num shape flips global: %s", numShapeFlipsGlobal);
        writefln("num ovf checks: %s", numOvfChecks);
        writefln("num heap allocs: %s", numHeapAllocs);

        writefln("num call fast: %s", numCallFast);
        writefln("num call slow: %s", numCallSlow);
        writefln("num call apply: %s", numCallApply);

        writefln("num funs comp: %s", numFunsComp);
        writefln("num cont invs: %s", numContInvs);
        writefln("num ret: %s", numRet);
        writefln("num ret tag known: %s", numRetTagKnown);

        //sortedCounts(numCalls, "calls");

        sortedCounts(numPrimCalls, "prim calls");

        sortedCounts(numTypeTests, "type tests");

        for (size_t numVers = 1; numVers <= min(opts.maxvers, 10); numVers++)
        {
            auto blockCount = numVerBlocks.get(numVers, 0);
            writefln("%s versions: %s", numVers, blockCount);
        }
    }

    if (opts.stats || opts.perf_stats)
    {
        version (linux)
        {
            rusage usage;
            getrusage(RUSAGE_SELF, &usage);
            writefln("peak mem usage (KB): %d", usage.ru_maxrss);
            writefln("page reclaims: %d", usage.ru_minflt);
            writefln("page faults: %s", usage.ru_majflt);
            writefln("voluntary context sw: %s", usage.ru_nvcsw);
            writefln("involuntary context sw: %s", usage.ru_nivcsw);
        }
    }
}

