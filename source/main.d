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
import parser.parser;
import interp.interp;
import repl;
import options;

void main(string[] args)
{
    // Parse the command-line arguments
    parseCmdArgs(args);

    // If in (unit) test mode
    if (opts.test == true)
        return;

    // Get the names of files to execute
    auto fileNames = args[1..$];

    // Interpreter instance
    auto interp = new Interp(true, !opts.nostdlib);

    // If file arguments were passed or there is 
    // a string of code to be executed
    if (fileNames.length != 0 || opts.execString !is null)
    {
        try
        {
            foreach (fileName; fileNames)
                interp.load(fileName);

            if (opts.execString)
                interp.evalString(opts.execString);
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
        repl.repl(interp);
    }

    /*
    // If JIT stats are enabled
    if (opts.jit_stats)
    {
        writefln("");
        writefln("JIT stats:");
        writefln("root trace entry count: %s", traceRootCnt);
        writefln("sub-trace entry count : %s", traceSubCnt);
        writefln("trace loop count: %s", traceLoopCnt);
        writefln("trace exit count: %s", traceExitCnt);
    }
    */
}

