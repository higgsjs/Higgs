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

module parser.tests;

import core.exception;
import std.stdio;
import std.file;
import std.algorithm;
import parser.ast;
import parser.parser;

ASTProgram testParseFile(string fileName)
{
    ASTProgram ast;

    try
    {
        ast = parseFile(fileName);
    }
    catch (Throwable e)
    {
        writeln("parse failed on file:\n" ~ fileName);
        throw e;
    }

    string str1;
    string str2;

    try
    {
        str1 = ast.toString();
        auto ast2 = parseString(str1);
        str2 = ast2.toString();

        if (str1 != str2)
            throw new Error("second parse gave different result");
    }
    catch (Throwable e)
    {
        std.file.write("pass1_str.txt", str1);
        std.file.write("pass2_str.txt", str2);

        writeln("second parse failed on file:\n" ~ fileName);
        throw e;
    }

    return ast;
}

ASTProgram testParse(string input, bool valid = true)
{
    ASTProgram ast;

    try
    {
        ast = parseString(input);

        assert (ast.pos !is null, "null source position");
    }

    catch (Throwable e)
    {
        if (valid == true)
        {
            writeln("parse failed on input:\n" ~ input);
            throw e;
        }

        return null;
    }

    if (valid == false)
    {
        assert (
            false,
            "parse succeeded on invalid input:\n" ~
            input
        );
    }

    return ast;
}

ASTProgram testAST(string input, ASTNode inAst)
{
    ASTProgram outAst = testParse(input);

    string outStr = outAst.toString();
    string inStr = inAst.toString();

    if (outStr != inStr)
    {
        assert (
            false,
            "Incorrect parse for:\n" ~
            input ~ "\n" ~
            "expected:\n" ~
            inStr ~ "\n" ~
            "got:\n"~
            outStr
        );
    }

    return outAst;
}

ASTProgram testExprAST(string input, ASTExpr exprAst)
{
    ASTProgram inAst = new ASTProgram([new ReturnStmt(exprAst)]);
    return testAST(input, inAst);
}

/// Parenthesization test (serialization)
unittest
{
    void hasParens(string input, bool needsParens)
    {
        string output = parseString(input).toString();

        bool hasParens = (countUntil(output, "(") != -1);

        if (hasParens != needsParens)
        {
            throw new Error(
                "incorrect parenthesization on input:\n" ~
                input ~ "\n" ~
                "output:\n" ~
                output
            );
        }
    }

    hasParens("a - (b+c)", true);
    hasParens("a - (b-c)", true);
    hasParens("a - b - c", false);
    hasParens("(a - b) - c", false);

    hasParens("a / (b/c)", true);
    hasParens("a / (b%c)", true);
    hasParens("a / b / c", false);
    hasParens("a * b * c", false);

    hasParens("a.b[c]", false);
    hasParens("(a + b)[c]", true);

    hasParens("a && (b? c:d)", true);
}

/// Test parsing of simple expressions
unittest
{
    writefln("simple expression parsing");

    testParse("");

    testParse(";");
    testParse("+", false);
    testParse(":", false);

    testParse("1");
    testParse("1;");
    testParse("3.0;");
    testParse(".5;");
    testParse("2.;");
    testParse("2.E2;");
    testParse("1E15;");
    testParse("1E-15;");
    testParse("0x09ABCD;");
    testParse("01237;");

    testParse("\"foobar\";");
    testParse("'foobar';");
    testParse("\"foobar';", false);
    testParse("'foo\nbar';", false);
    testParse("'foo\\x55bar';");
    testParse("'foo\\uABCDbar';");

    testParse("/foobar/;");
    testParse("/\\//;");
    testParse("/foobar/ig;");

    testParse("[1, 2, 3];");
    testParse("[1, 2, 3,];");
    testParse("true;");
    testParse("false;");
    testParse("null;");
}

/// Test expression parsing
unittest
{
    testParse("1 + 1;");
    testParse("1 * 2 + 4 + -b;");
    testParse("++x;");

    testParse("foo !== \"bar\";");

    testParse("x = 1;");
    testParse("$t = 1;");
    testParse("x += 1;");

    testParse("z = f[2] + 3; ++z;");
    testParse("1? 2:3 + 4;");

    testParse("[x + y, 2, \"foo\"];");

    testParse("{ a:1, b:2 };", false);
    testParse("a = { a:1, b:2 };");
    testParse("a = { a:1, \"b\":2 };");
    testParse("a = { a:1, b:2+3*4 };");
    testParse("a = { new:3 };");
    testParse("o = { p:3, }");
    testParse("a = /f+/ig;");

    testParse("new Foo();");
    testParse("new Foo;");
    testParse("new Foo + 2");

    testParse("delete a");
    testParse("typeof a");
    testParse("void a");

    testParse("a.b");
    testParse("a.b()");
    testParse("a.delete + 2");
    testParse("a.delete()");
    testParse("a.new");

    // Comma operator
    testParse("1, 2");
    testParse("x = y, z");
}

/// Test expression ASTs
unittest
{
    testExprAST("1;", new IntExpr(1));
    testExprAST("0xFB;", new IntExpr(0xFB));
    testExprAST("077;", new IntExpr(63));
    testExprAST("087;", new IntExpr(87));
    testExprAST("7.0;", new FloatExpr(7));
    testExprAST(".05;", new FloatExpr(0.05));
    testExprAST("true;", new TrueExpr());
    testExprAST("false;", new FalseExpr());
    testExprAST("null;", new NullExpr());

    // String escape sequences
    testExprAST("'foo\\nbar';", new StringExpr("foo\nbar"));
    testExprAST("'foo\\\nbar';", new StringExpr("foobar"));
    testExprAST("'foo\\x55bar';", new StringExpr("foo\x55bar"));
    testExprAST("'foo\\u0055bar';", new StringExpr("foo\u0055bar"w));
    testExprAST("'foo\\055bar';", new StringExpr("foo-bar"w));

    testExprAST("1 + b;", 
        new BinOpExpr("+", new IntExpr(1), new IdentExpr("b"))
    );

    testExprAST("1 + 2 * 3;", 
        new BinOpExpr(
            "+",
            new IntExpr(1),
            new BinOpExpr(
                "*",
                new IntExpr(2),
                new IntExpr(3)
            )
        )
    );

    testExprAST("foo + 1 + 2;", 
        new BinOpExpr(
            "+",
            new BinOpExpr(
                "+",
                new IdentExpr("foo"),
                new IntExpr(1),
            ),
            new IntExpr(2)
        )
    );

    testExprAST("foo + bar == bif;", 
        new BinOpExpr(
            "==",
            new BinOpExpr(
                "+",
                new IdentExpr("foo"),
                new IdentExpr("bar")
            ),
            new IdentExpr("bif")
        )
    );

    testExprAST("-a.b;", 
        new UnOpExpr(
            "-", 'r', 
            new IndexExpr(
                new IdentExpr("a"),
                new StringExpr("b")
            )
        )
    );

    testExprAST("-a + b;",
        new BinOpExpr(
            "+", 
            new UnOpExpr("-", 'r', new IdentExpr("a")),
            new IdentExpr("b")
        )
    );

    testExprAST("a[b + c];",
        new IndexExpr(
            new IdentExpr("a"),
            new BinOpExpr(
                "+",
                new IdentExpr("b"),
                new IdentExpr("c")
            )
        )
    );

    testExprAST("a.b.c;",
        new IndexExpr(
            new IndexExpr(
                new IdentExpr("a"),
                new StringExpr("b")
            ),
            new StringExpr("c")
        )
    );

    testExprAST("++a.b;", 
        new UnOpExpr(
            "++", 'r', 
            new IndexExpr(
                new IdentExpr("a"),
                new StringExpr("b")
            )
        )
    );

    testExprAST("a.b();",
        new CallExpr(
            new IndexExpr(
                new IdentExpr("a"),
                new StringExpr("b")
            ),
            []
        )
    );

    testExprAST("a++;", 
        new UnOpExpr(
            "++", 'l', 
            new IdentExpr("a"),
        )
    );

    testExprAST("a + b++;",
        new BinOpExpr(
            "+",
            new IdentExpr("a"),
            new UnOpExpr(
                "++", 'l', 
                new IdentExpr("b"),
            )
        )
    );

    testExprAST("++a.b();",
        new UnOpExpr(
            "++", 'r', 
            new CallExpr(
                new IndexExpr(
                    new IdentExpr("a"),
                    new StringExpr("b")
                ),
                []
            )
        )
    );

    testExprAST("new a.b();",
        new NewExpr(
            new IndexExpr(
                new IdentExpr("a"),
                new StringExpr("b")
            ),
            []
        )
    );

    testExprAST("-a++;",
        new UnOpExpr(
            "-", 'r',
            new UnOpExpr(
                "++", 'l',
                new IdentExpr("a")
            )
        )
    );

    testExprAST("a = b? 1:2;",
        new BinOpExpr(
            "=", 
            new IdentExpr("a"),
            new CondExpr(
                new IdentExpr("b"),
                new IntExpr(1),
                new IntExpr(2)
            )
        )
    );

    testExprAST("x += y;",
        new BinOpExpr(
            "=", 
            new IdentExpr("x"),
            new BinOpExpr(
                "+",
                new IdentExpr("x"),
                new IdentExpr("y")
            )
        )
    );

    testExprAST("a? b=1:b=2;",
        new CondExpr(
            new IdentExpr("a"),
            new BinOpExpr(
                "=",
                new IdentExpr("b"),
                new IntExpr(1),
            ),
            new BinOpExpr(
                "=",
                new IdentExpr("b"),
                new IntExpr(2),
            )
        )
    );
}

/// Test statement parsing
unittest
{
    testParse("{}");
    testParse("{ 1; }");
    testParse("{ 1; 2; }");
    testParse("{} {}");

    testParse("var x;");
    testParse("var x; var y; var z = 1 + 1;");
    testParse("var x += 2;", false);
    testParse("var x, y, z;");
    testParse("var x = 1, y, z;");
    testParse("var x = \"foobar\";");
    testParse("var x = \"foo\\\nbar\";");

    testParse("if (x) f();");
    testParse("if (x) f(); else g();");
    testParse("if (x) { f(); }");
    testParse("if (x);");
    testParse("if () {}", false);

    testParse("while (true) 1;");
    testParse("while (false);");

    testParse("do {} while (x)");
    testParse("do; while(true)");
    testParse("do while (x)", false);
    testParse("do; while ()", false);

    testParse("for (var i = 0; i < 10; i += 1) println(\"foobar\");");
    testParse("for (var a = 0, b = 0; a < 10; a += 1);");
    testParse("for (;;) {}");
    testParse("for (;;);");
    testParse("for (;);", false);
    testParse("FOO: for (;;);");
    testParse("FOO: BAR: for (;;);");

    // For-in loop statement
    testParse("for (var a in b) {}");
    testParse("for (var a in 0,[0,1,2]) print(a);");
    testParse("for (a in [0,1,2]) {}");
    testParse("for (a.b in [0, 1, 2]) print(a.b);");
    testParse("for (a.b in c);");
    testParse("for (var a.b in c);", false);

    // Break and continue
    testParse("for (;;) break;");
    testParse("for (;;) continue;");
    testParse("FOO: for (;;) break FOO;");
    testParse("FOO: for (;;) continue FOO;");

    testParse("throw 1;");
    testParse("throw;", false);

    testParse("try foo(); catch (e) e;");
    testParse("try foo(); catch (e) e; finally bar();");
    testParse("try foo(); finally bar();");
    testParse("try foo();", false);

    // Automatic semicolon insertion
    testParse("{ 1; 2 }");
    testParse("1\n2");
    testParse("if (x) y");
    testParse("if (x) y\nelse\nz");
    testParse("var x\n2");
    testParse("return x");
    testParse("return");
    testParse("(function () { return })");
    testParse("throw x");
    testParse("var a = [1,,2,]");
}

/// Test program-level ASTs
unittest
{
    testAST(
        "",
        new ASTProgram([])
    );

    testAST(
        "var x = 1;",
        new ASTProgram([
            new VarStmt([new IdentExpr("x")], [new IntExpr(1)])
        ])
    );

    testAST(
        "var x = 1, y = 2;",
        new ASTProgram([
            new VarStmt(
                [new IdentExpr("x"), new IdentExpr("y")],
                [new IntExpr(1), new IntExpr(2)]
            )
        ])
    );
}

/// Test function parsing and ASTs
unittest
{
    testParse("function () { return 1; };");
    testParse("function () { return; };");
    testParse("function (x) {};");
    testParse("function (x,y) {};");
    testParse("function (x,) {};", false);
    testParse("function (x) { if (x) return 1; else return 2; };",);
    testParse("function () {} x = 0");

    testExprAST("function () { return 1; };",
        new FunExpr(
            null,
            [], 
            new BlockStmt([new ReturnStmt(new IntExpr(1))])
        )
    );

    testAST("function foo() {};",
        new ASTProgram([
            new ExprStmt(
                new FunExpr(
                    new IdentExpr("foo"),
                    [],
                    new BlockStmt([])
                )
            )
        ])
    );
}

/// Test parsing of source files
unittest
{
    writefln("source file parsing");

    // Sunspider benchmarks
    testParseFile("benchmarks/sunspider/controlflow-recursive.js");
    testParseFile("benchmarks/sunspider/bitops-bits-in-byte.js");
    testParseFile("benchmarks/sunspider/bitops-nsieve-bits.js");
    testParseFile("benchmarks/sunspider/3d-cube.js");    
    testParseFile("benchmarks/sunspider/3d-morph.js");
    testParseFile("benchmarks/sunspider/3d-raytrace.js");
    testParseFile("benchmarks/sunspider/access-nsieve.js");
    testParseFile("benchmarks/sunspider/access-fannkuch.js");
    testParseFile("benchmarks/sunspider/access-binary-trees.js");
    testParseFile("benchmarks/sunspider/access-nbody.js");
    testParseFile("benchmarks/sunspider/math-cordic.js");
    testParseFile("benchmarks/sunspider/string-fasta.js");
    testParseFile("benchmarks/sunspider/string-base64.js");
    testParseFile("benchmarks/sunspider/crypto-sha1.js");
    testParseFile("benchmarks/sunspider/3d-cube.js");
    testParseFile("benchmarks/sunspider/crypto-md5.js");

    // V8 benchmarks
    testParseFile("benchmarks/v8bench/navier-stokes.js");
    testParseFile("benchmarks/v8bench/splay.js");
    testParseFile("benchmarks/v8bench/richards.js");
    testParseFile("benchmarks/v8bench/crypto.js");
    testParseFile("benchmarks/v8bench/deltablue.js");
    testParseFile("benchmarks/v8bench/raytrace.js");
    testParseFile("benchmarks/v8bench/earley-boyer.js");

    // Kraken 1.1 benchmarks
    testParseFile("benchmarks/kraken-1.1/ai-astar.js");
    testParseFile("benchmarks/kraken-1.1/ai-astar-data.js");

    // Web frameworks
    testParseFile("benchmarks/frameworks/jquery-1.3.2.js");
    testParseFile("benchmarks/frameworks/jquery-2.1.4.js");
    testParseFile("benchmarks/frameworks/prototype-1.7.1.js");

    // Bones benchmark
    testParseFile("benchmarks/bones/bones.js");

    // Standard library
    testParseFile("stdlib/math.js");
    testParseFile("stdlib/array.js");
    testParseFile("stdlib/string.js");
    testParseFile("stdlib/number.js");
    testParseFile("stdlib/object.js");
    testParseFile("stdlib/json.js");
}

