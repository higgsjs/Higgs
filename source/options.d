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

import std.stdio;
import std.getopt;

struct Options
{
    /// String of code to execute (--e str)
    string execString = null;

    /// Force a repl, even after loading files or executing a string
    bool repl = false;

    /// Set stdout to be unbuffered
    bool unbuffered = false;

    /* VM options */

    /// Gather and report various statistics about program execution
    bool stats = false;

    /// Gather performance statistics (without slowing down execution)
    bool perf_stats = false;

    /// Disable loading of the runtime library
    bool noruntime = false;

    /// Disable loading of the standard library
    bool nostdlib = false;

    /* Compiler options */

    /// Enable IR-level type propagation analysis
    bool typeprop = false;

    /// Maximum number of specialized versions to compile per basic block
    uint maxvers = 20;

    /// Disable shape versioning and dispatch
    bool shape_novers = false;

    /// Disable type tag specialization in shapes
    bool shape_notagspec = false;

    /// Disable function pointer specialization in shapes
    bool shape_nofptrspec = false;

    /// Disable overflow check elimination
    bool noovfelim = false;

    /// Disable function entry point specialication (interprocedural)
    bool noentryspec = false;

    /// Disable return/continuation specialication (interprocedural)
    bool noretspec = false;

    /// Disable peephole optimizations
    bool nopeephole = false;

    /// Disable inlining in the JIT
    bool noinline = false;

    /// Dump information about JIT compilation
    bool dumpinfo = false;

    /// Dump the IR of functions compiled by the JIT
    bool dumpir = false;

    /// Store disassembly for the generated machine code
    bool genasm = false;

    /// Dump disassembly for all the generated machine code
    bool dumpasm = false;

    /// Log a trace of the instructions executed
    bool trace_instrs = false;
}

/// Global options structure
Options opts;

/**
Parse the command-line arguments
*/
void parseCmdArgs(ref string[] args)
{
    getopt(
        args,
        config.stopOnFirstNonOption,
        config.passThrough,

        "e"                 , &opts.execString,
        "repl"              , &opts.repl,
        "unbuffered"        , &opts.unbuffered,
        "stats"             , &opts.stats,
        "perf_stats"        , &opts.perf_stats,

        "noruntime"         , &opts.noruntime,
        "nostdlib"          , &opts.nostdlib,

        "typeprop"          , &opts.typeprop,
        "maxvers"           , &opts.maxvers,
        "shape_novers"      , &opts.shape_novers,
        "shape_notagspec"   , &opts.shape_notagspec,
        "shape_nofptrspec"  , &opts.shape_nofptrspec,
        "noovfelim"         , &opts.noovfelim,
        "noentryspec"       , &opts.noentryspec,
        "noretspec"         , &opts.noretspec,
        "nopeephole"        , &opts.nopeephole,
        "noinline"          , &opts.noinline,
        "dumpinfo"          , &opts.dumpinfo,
        "dumpir"            , &opts.dumpir,
        "genasm"            , &opts.genasm,
        "dumpasm"           , &opts.dumpasm,
        "trace_instrs"      , &opts.trace_instrs
    );

    // If we don't load the runtime, we can't load the standard library
    if (opts.noruntime)
        opts.nostdlib = true;

    // If dumping the ASM, we must first generate the ASM strings
    if (opts.dumpasm)
        opts.genasm = true;

    // If shape versioning is disabled, disable shape specialization
    if (opts.shape_novers)
    {
        opts.shape_notagspec = true;
        opts.shape_nofptrspec = true;
    }
}

