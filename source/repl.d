/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011, Maxime Chevalier-Boisvert. All rights reserved.
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
import std.string;
import parser.ast;
import parser.parser;
import ir.ast;
import interp.interp;

/**
Evaluate a string of source code
*/
ValuePair evalString(Interp interp, string input)
{
    auto ast = parseString(input, "repl");

    // If the AST contains only an expression statement,
    // turn it into a return statement
    if (auto blockStmt = cast(BlockStmt)ast.bodyStmt)
    {
        if (blockStmt.stmts.length == 1)
        {
            if (auto exprStmt = cast(ExprStmt)blockStmt.stmts[$-1])
            {
                blockStmt.stmts[$-1] = new ReturnStmt(
                    exprStmt.expr,
                    exprStmt.pos
                );
            }
        }
    }

    //writeln(ast);

    auto ir = astToIR(ast);
    
    writeln(ir);

    interp.exec(ir);

    // Get the final output
    auto output = interp.getRet();

    return output;
}

void repl()
{
    auto interp = new Interp();

    writeln("Entering read-eval-print loop");
    writeln("To exit, press ctrl+D (end-of-file) or type \"exit\" at the prompt");

    for (;;)
    {
        write("w> ");
        string input = readln().stripRight();
        
        if (input.length == 0 || input.toLower() == "exit\n")
        {
            if (input.length == 0)
                writeln();

            break;
        }

        try 
        {
            // Evaluate the input
            auto output = evalString(interp, input);

            // Print the output
            writeln(ValueToString(output));
        }

        catch (ParseError e)
        {
            writeln("parse error: " ~ e.toString());
        }
    }
}

unittest
{
    evalString(new Interp(), "1");
}

