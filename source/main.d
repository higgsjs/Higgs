/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2013, Maxime Chevalier-Boisvert. All rights reserved.
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
import std.algorithm;
import std.conv;
import std.string;
import parser.parser;
import runtime.vm;
import util.string;
import repl;
import options;

void main(string[] args)
{
    // Arguments after "--" are passed to JS code
    auto argLimit = countUntil(args, "--");
    string[] hostArgs;
    string[] jsArgs;

    if (argLimit > 0)
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

    // Create VM instance
    auto vm = new VM(!opts.noruntime, !opts.nostdlib);

    /*
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
    */

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
            writeln("parse error: " ~ e.toString());
        }

        catch (RunError e)
        {
            writefln("run-time error: " ~ e.toString());
        }
    }

    // If a REPL was requested or no code to be executed was specified
    if (opts.repl || (fileNames.length == 0 && opts.execString is null))
    {
        // Start the REPL
        repl.repl(vm);
    }
}

