/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

import core.sys.posix.signal;
import core.stdc.signal;
import core.memory;
import core.stdc.string;
import core.stdc.stdlib;
import std.stdio;
import std.file;
import std.algorithm;
import std.conv;
import std.string;
import parser.parser;
import ir.analysis;
import runtime.vm;
import util.string;
import util.os;
import repl;
import options;

/**
Program entry point
*/
void main(string[] args)
{
    // Reserve memory for the D GC, improves allocation performance
    GC.reserve(1024 * 1024 * 1024);

    // Arguments after "--" are passed to JS code
    auto argLimit = countUntil(args, "--");
    string[] hostArgs;
    string[] jsArgs;

    if (args.length > 1 && args[1] == "--shellscript")
    {
        // Shell script invocation (i.e.: called from a shebang line)
        hostArgs = args[0..1] ~ args[2..3];
        jsArgs = args[3..$];
    }
    else if (argLimit > 0)
    {
        hostArgs = args[0..argLimit];
        jsArgs = args[++argLimit..$];
    }
    else
    {
        hostArgs = args[0..$];
        jsArgs = [];
    }

    // Parse the command-line arguments
    parseCmdArgs(hostArgs);

    // Get the names of files to execute
    auto fileNames = hostArgs[1..$];

    auto tagFileName = (fileNames.length > 0)? (fileNames[$-1]~"_"):"";
    tagFileName = tagFileName.replace(".js", "") ~ "tags.csv";

    // Register the segmentation fault handler
    sigaction_t sa;
    memset(&sa, 0, sa.sizeof);
    sigemptyset(&sa.sa_mask);
    sa.sa_sigaction = &segfaultHandler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, null);

    // Load the tag tests, if requested
    if (opts.load_tag_tests)
    {
        loadTagTests(tagFileName);
    }

    // Initialize the VM instance
    VM.init(!opts.noruntime, !opts.nostdlib);

    // Construct the JS arguments array
    if (!opts.noruntime)
    {
        wstring jsArgsStr = "arguments = [";
        foreach(string arg; jsArgs)
            jsArgsStr ~= "'" ~ escapeJSString(to!wstring(arg)) ~ "',";
        jsArgsStr ~= "];";

        // Evaluate the arguments array string
        vm.evalString(to!string(jsArgsStr));
    }

    // Check if we need to set stdout to unbuffered
    if (opts.unbuffered)
        stdout.setvbuf(0, _IONBF);

    // If file arguments were passed or there is
    // a string of code to be executed
    if (fileNames.length != 0 || opts.execString !is null)
    {
        try
        {
            foreach (fileName; fileNames)
                vm.load(fileName);

            if (opts.execString)
                vm.evalString(opts.execString);
        }

        catch (ParseError e)
        {
            writeln("parse error: ", e);
            exit(-1);
        }

        catch (RunError e)
        {
            writeln(e);
            exit(-1);
        }

        catch (FileException e)
        {
            writeln(e.msg);
            exit(-1);
        }

        catch (Error e)
        {
            writeln(e);
            exit(-1);
        }
    }

    // If a REPL was requested or no code to be executed was specified
    if (opts.repl || (fileNames.length == 0 && opts.execString is null))
    {
        // Start the REPL
        repl.repl(vm);
    }

    // Save the type tag test results
    if (opts.save_tag_tests)
    {
        saveTagTests(tagFileName);
    }

    // Free resources used by the VM instance
    VM.free();
}

import ir.ir;
IRInstr instrPtr = null;

/**
Segmentation fault signal handler (SIGSEGV)
*/
extern (C) void segfaultHandler(int signal, siginfo_t* si, void* arg)
{
    import jit.codeblock;

    // si->si_addr is the instruction pointer
    auto ip = cast(CodePtr)si.si_addr;

    writeln();
    writeln("Caught segmentation fault");
    writeln("IP=", ip);

    auto cb = vm.execHeap;
    auto startAddr = cb.getAddress(0);
    auto endAddr = startAddr + cb.getWritePos();

    if (ip >= startAddr && ip < endAddr)
    {
        auto offset = ip - startAddr;
        writeln("IP in jitted code, offset=", offset);
    }

    if (vm.curInstr !is null)
    {
        writeln("vm.curInstr: ", vm.curInstr);
    }

    if (instrPtr !is null)
    {
        writeln("instrPtr: ", instrPtr);
        writeln("curFun: ", instrPtr.block.fun.getName);
    }

    writeln("exiting");
    exit(139);
}

