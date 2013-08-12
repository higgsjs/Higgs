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

module jit.stats;

import std.stdio;
import std.datetime;
import std.string;
import std.array;
import std.stdint;
import std.conv;
import options;

/// Total compilation time in microseconds
package ulong compTimeUsecs = 0;

/// Number of type tests executed (dynamic)
package ulong numTypeTests = 0;

/// Number of unjitted instructions executed (dynamic)
package ulong numUnjitInstrs = 0;

/// Program start time in milliseconds
private ulong startTimeMsecs = 0;

/// Static module constructor
static this()
{
    // Record the starting time
    startTimeMsecs = Clock.currAppTick().msecs();
}

/// Static module destructor, log the accumulated stats
static ~this()
{
    // If JIT stats are disabled, stop
    if (opts.jit_stats is false)
        return;

    auto endTimeMsecs = Clock.currAppTick().msecs();
    auto execTimeMsecs = endTimeMsecs - startTimeMsecs;

    writeln();
    writefln("total execution time (ms): %s", execTimeMsecs);
    writefln("total compilation time (ms): %s", compTimeUsecs / 1000);
    writefln("type tests executed: %s", numTypeTests);
    writefln("unjitted instructions executed: %s", numUnjitInstrs);
}

