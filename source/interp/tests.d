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

module interp.tests;

import std.stdio;
import std.string;
import parser.parser;
import ir.ast;
import interp.interp;

Interp evalString(string input)
{
    auto ast = parseString(input);
    auto ir = astToIR(ast);

    Interp interp = new Interp();

    //writeln(ir.toString());
    //writeln("executing");

    interp.exec(ir);

    return interp;
}

void assertInt(string input, long intVal)
{
    auto interp = evalString(input);

    //writeln("getting ret val");

    auto ret = interp.getRet();

    assert (
        ret.type == Type.INT,
        "non-integer type"
    );

    assert (
        ret.word.intVal == intVal,
        format(
            "Test failed:\n" ~
            input ~ "\n" ~
            "incorrect integer value: %s, expected: %s",
            ret.word.intVal, 
            intVal
        )
    );
}

void assertStr(string input, string strVal)
{
    auto interp = evalString(input);

    //writeln("getting ret val");

    auto ret = interp.getRet();

    assert (
        ret.type == Type.STRING,
        "non-string type"
    );

    auto outStr = ValueToString(ret);

    assert (
        outStr == strVal,
        format(
            "Test failed:\n" ~
            input ~ "\n" ~
            "incorrect string value: %s, expected: %s",
            outStr, 
            strVal
        )
    );
}

unittest
{
    Word w0 = Word.intv(0);
    Word w1 = Word.intv(1);

    assert (w0.intVal != w1.intVal);
}

/// Global expression tests
unittest
{
    assertInt("return 7", 7);
    assertInt("return 1 + 2", 3);
    assertInt("return 5 - 1", 4);
    assertInt("return 8 % 5", 3);
    assertInt("return -3", -3);
    assertInt("return 2 + 3 * 4", 14);
}

/// Global function calls
unittest
{
    assertInt("return function () { return 9; } ()", 9);
    assertInt("return function () { return 2 * 3; } ()", 6);
}

/// Argument passing test
unittest
{
    assertInt("return function (x) { return x + 3; } (5)", 8);
    assertInt("return function (x, y) { return x - y; } (5, 2)", 3);

    // Too many arguments
    assertInt("return function (x) { return x + 1; } (5, 9)", 6);

    // Too few arguments
    assertInt("return function (x, y) { return x - 1; } (4)", 3);
}

/// Local variable assignment
unittest
{
    assertInt("return function () { var x = 4; return x; } ()", 4);
    assertInt("return function () { var x = 0; return x++; } ()", 0);
    assertInt("return function () { var x = 0; return ++x; } ()", 1);
    assertInt("return function () { var x = 0; return x--; } ()", 0);
    assertInt("return function () { var x = 0; return --x; } ()", -1);
    assertInt("return function () { var x = 0; return x++ + 1; } ()", 1);
}

/// Comparison and branching
unittest
{
    assertInt("if (true) return 1; else return 0;", 1);
    assertInt("if (false) return 1; else return 0;", 0);
    assertInt("if (3 < 7) return 1; else return 0;", 1);
    assertInt("if (5 < 2) return 1; else return 0;", 0);

    assertInt("return true? 1:0", 1);
    assertInt("return false? 1:0", 0);

    assertInt("return 0 || 2", 2);
    assertInt("return 1 || 2", 1);
    assertInt("return 0 || 0 || 3", 3);
    assertInt("return 0 || 2 || 3", 2);
    assertInt("if (0 || 2) return 1; else return 0;", 1);
    assertInt("if (1 || 2) return 1; else return 0;", 1);
    assertInt("if (0 || 0) return 1; else return 0;", 0);

    assertInt("return 0 && 2", 0);
    assertInt("return 1 && 2", 2);
    assertInt("return 1 && 2 && 3", 3);
    assertInt("return 1 && 0 && 3", 0);
    assertInt("if (0 && 2) return 1; else return 0;", 0);
    assertInt("if (1 && 2) return 1; else return 0;", 1);
}

/// Recursion
unittest
{
    assertInt(
        "
        return function (n)
        {
            var fact = function (fact, n)
            {
                if (n < 1)
                    return 1;
                else   
                    return n * fact(fact, n-1);
            };
                              
            return fact(fact, n);
        } (4);
        ",
        24
    );

    assertInt(
        "
        return function (n)
        {
            var fib = function (fib, n)
            {
                if (n < 2)
                    return n;
                else   
                    return fib(fib, n-1) + fib(fib, n-2);
            };
                              
            return fib(fib, n);
        } (6);
        ",
        8
    );
}

/// Loops
unittest
{
    assertInt(
        "
        return function ()
        {
            var i = 0;
            while (i < 10) ++i;
            return i;
        } ();
        ",
        10
    );

    assertInt(
        "
        return function ()
        {
            var i = 0;
            while (true)
            {
                if (i === 5)
                    break;
                ++i;
            }

            return i;
        } ();
        ",
        5
    );

    assertInt(
        "
        return function ()
        {
            var sum = 0;
            var i = 0;
            while (i < 10)
            {
                if ((i++ % 2) === 0)
                    continue;

                sum += i;
            }

            return sum;
        } ();
        ",
        30
    );

    assertInt(
        "
        return function ()
        {
            var i = 0;
            do { i++; } while (i < 9)
            return i;
        } ();
        ",
        9
    );

    assertInt(
        "
        return function ()
        {
            for (var i = 0; i < 10; ++i);
            return i;
        } ();
        ",
        10
    );
}

/// Strings
unittest
{
    assertStr("return 'foo'", "foo");
    assertStr("return 'foo' + 'bar'", "foobar");
    assertStr("return 'foo' + 1", "foo1");
    assertStr("return 'foo' + true", "footrue");
    assertInt("return 'foo'? 1:0", 1);
    assertInt("return ''? 1:0", 0);

    assertStr(
        "
        return function ()
        {
            var s = '';

            for (var i = 0; i < 5; ++i)
                s += i;

            return s;
        } ();
        ",
        "01234"
    );
}

/// Global scope, global object
unittest
{
    assertInt("a = 1; return a;", 1);
    assertInt("a = 1; b = 2; return a+b;", 3);
    assertInt("f = function() { return 7; }; return f();", 7);
}

