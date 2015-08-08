/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2015, Maxime Chevalier-Boisvert. All rights reserved.
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

module ir.analysis;

import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.conv;
import ir.ir;
import ir.ops;
import ir.livevars;
import runtime.vm;
import jit.jit;
import options;

/// Type test info struct
struct TestInfo
{
    StackIdx outSlot;

    string mnem;

    TestResult result;
}

/// Type test result
enum TestResult
{
    TRUE,
    FALSE,
    UNKNOWN
}

/// Block versions registered as containing a type test, indexed by block id
private BlockVersion[uint64_t] versions;

/// Loaded test results, indexed by block id
private TestInfo[uint64_t] testResults;

/// Register a block version containing a tag test
void regTagTest(BlockVersion ver)
{
    //writeln(ver.block.lastInstr.opcode.mnem);

    // Assert type test present
    assert (ver.block.lastInstr.opcode is &IF_TRUE);
    auto testInstr = cast(IRInstr)ver.block.lastInstr.getArg(0);
    assert (testInstr);
    assert (testInstr.opcode.mnem.startsWith("is_"));

    assert (ver.block.id !in versions);
    versions[ver.block.id] = ver;
}

/// Get the type test result for a given tag test
TestResult getTestResult(BlockVersion ver)
{
    assert (ver.block.id in testResults);

    auto testInfo = ver.block.id in testResults;

    assert (ver.block.lastInstr.opcode is &IF_TRUE);
    auto testInstr = cast(IRInstr)ver.block.lastInstr.getArg(0);
    assert (testInstr);
    assert (testInstr.outSlot is testInfo.outSlot);
    assert (testInstr.opcode.mnem is testInfo.mnem);

    return testInfo.result;
}

void saveTagTests(string fileName)
{
    writefln("saving tag tests");
    writefln("%s tests registered", versions.length);

    assert (versions.length > 0);

    import std.stdio;
    auto f = File(fileName, "w");

    size_t numUnknown = 0;

    foreach (ver; versions)
    {
        auto targets = ver.targets;
        auto branch0 = cast(BranchCode)targets[0];
        auto branch1 = cast(BranchCode)targets[1];

        //writeln();
        //writeln(ver.block);

        assert (!(targets[0] && !branch0));
        assert (!(targets[1] && !branch1));

        auto exec0 = branch0 && branch0.ended;
        auto exec1 = branch1 && branch1.ended;

        if (exec0 && exec1)
            numUnknown++;

        TestResult testResult;
        if (exec0 && !exec1)
            testResult = TestResult.TRUE;
        else if (!exec0 && exec1)
            testResult = TestResult.FALSE;
        else
            testResult = TestResult.UNKNOWN;

        auto testInstr = cast(IRInstr)ver.block.lastInstr.getArg(0);
        assert (testInstr);

        f.writefln(
            "%s,%s,%s,%s",
            ver.block.id,
            testInstr.outSlot,
            testInstr.opcode.mnem,
            testResult
        );
    }

    writefln(
        "%s tests unknown (%.1f %%)",
        numUnknown,
        100.0 * numUnknown / versions.length
    );
}

void loadTagTests(string fileName)
{
    import std.stdio;
    auto f = File(fileName, "r");

    for (;;)
    {
        auto line = f.readln();
        if (line is null)
            break;

        auto cols = line.strip().split(",");
        assert (cols.length == 4);

        TestInfo info;
        ulong blockId = to!ulong(cols[0]);
        info.outSlot = to!StackIdx(cols[1]);
        info.mnem = cols[2];
        info.result = to!TestResult(cols[3]);

        testResults[blockId] = info;
    }
}

