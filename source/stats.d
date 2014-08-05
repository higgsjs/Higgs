/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2014, Maxime Chevalier-Boisvert. All rights reserved.
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
import std.stdio;
import std.datetime;
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

/// Number of shape lookup instances
ulong numDefShapeInsts = 0;

/// Number of shape lookup instances on the global object
ulong numDefShapeGlobal = 0;

/// Number of shape lookup instances with a known shape
ulong numDefShapeKnown = 0;

/// Number of host version lookups
ulong numDefShapeHost = 0;

/// Number of version dispatch updates
ulong numDefShapeUpd = 0;

/// Number of host property lookups
ulong numSetPropHost = 0;

/// Number of heap allocations
ulong numHeapAllocs = 0;

/// Number of dynamic calls
ulong numCall = 0;

/// Number of primitive calls by primitive name
private ulong* numPrimCalls[string];

/// Number of type tests executed by test kind
private ulong* numTypeTests[string];

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
ulong* getTypeTestCtr(string testOp)
{
    // If there is no counter for this op, allocate one
    if (testOp !in numTypeTests)
        numTypeTests[testOp] = new ulong;

    // Return the counter for this test op
    return numTypeTests[testOp];
}

/// Total compilation time in microseconds
private ulong compTimeUsecs = 0;

/// Total execution time in microseconds
private ulong execTimeUsecs = 0;

/// Compilation timer start
private ulong compStartUsecs = 0;

/// Execution timer start
private ulong execStartUsecs = 0;

/// Get the current process time in microseconds
ulong getTimeUsecs()
{
    return Clock.currAppTick().usecs();
}

/// Start recording compilation time
void compTimeStart()
{
    assert (compStartUsecs is 0, "comp timer already started");
    assert (execStartUsecs is 0, "exec timer ongoing");

    compStartUsecs = getTimeUsecs();
}

/// Stop recording compilation time
void compTimeStop()
{
    assert (compStartUsecs !is 0);

    auto compEndUsecs = getTimeUsecs();
    compTimeUsecs += compEndUsecs - compStartUsecs;

    compStartUsecs = 0;
}

/// Start recording execution time
void execTimeStart()
{
    assert (execStartUsecs is 0, "exec timer already started");
    assert (compStartUsecs is 0, "comp timer ongoing");

    execStartUsecs = getTimeUsecs();
}

/// Stop recording execution time
void execTimeStop()
{
    assert (execStartUsecs !is 0);

    auto execEndUsecs = getTimeUsecs();
    execTimeUsecs += execEndUsecs - execStartUsecs;

    execStartUsecs = 0;
}

/// Check if the execution time is being recorded
bool execTimeStarted()
{
    return execStartUsecs != 0;
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
}

/// Static module destructor, log the accumulated stats
static ~this()
{
    if (opts.stats || opts.perf_stats)
    {
        writeln();
        writefln("comp time (ms): %s", compTimeUsecs / 1000);
        writefln("exec time (ms): %s", execTimeUsecs / 1000);
        writefln("total time (ms): %s", (compTimeUsecs + execTimeUsecs) / 1000);
        writefln("code size (bytes): %s", genCodeSize);
    }

    if (opts.stats)
    {
        writefln("num blocks: %s", numBlocks);
        writefln("num versions: %s", numVersions);
        writefln("max versions: %s", maxVersions);

        //writefln("num moves: %s", numMoves);

        writeln("num def shape insts: ", numDefShapeInsts);
        writeln("num def shape global: ", numDefShapeGlobal);
        writeln("num def shape known: ", numDefShapeKnown);

        writefln("num def shape host: %s", numDefShapeHost);
        writefln("num def shape update: %s", numDefShapeUpd);
        writefln("num set prop host: %s", numSetPropHost);
        writefln("num heap allocs: %s", numHeapAllocs);

        writefln("num call: %s", numCall);

        alias Tuple!(string, "name", ulong, "cnt") PrimCallCnt;
        PrimCallCnt[] primCallCnts;
        foreach (name, pCtr; numPrimCalls)
            primCallCnts ~= PrimCallCnt(name, *pCtr);
        primCallCnts.sort!"a.cnt > b.cnt";

        ulong totalPrimCalls = 0;
        foreach (pair; primCallCnts)
        {
            writefln("%s: %s", pair.name, pair.cnt);
            totalPrimCalls += pair.cnt;
        }
        writefln("total prim calls: %s", totalPrimCalls);

        alias Tuple!(string, "test", ulong, "cnt") TypeTestCnt;
        TypeTestCnt[] typeTestCnts;
        foreach (test, pCtr; numTypeTests)
            typeTestCnts ~= TypeTestCnt(test, *pCtr);
        typeTestCnts.sort!"a.cnt > b.cnt";

        ulong totalTypeTests = 0;
        foreach (pair; typeTestCnts)
        {
            writefln("%s: %s", pair.test, pair.cnt);
            totalTypeTests += pair.cnt;
        }
        writefln("total type tests: %s", totalTypeTests);

        for (size_t numVers = 1; numVers <= min(opts.jit_maxvers, 10); numVers++)
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
            writefln("page reclaims: %d", usage.ru_minflt);
            writefln("page faults: %s", usage.ru_majflt);
            writefln("voluntary context sw: %s", usage.ru_nvcsw);
            writefln("involuntary context sw: %s", usage.ru_nivcsw);
        }
    }
}

