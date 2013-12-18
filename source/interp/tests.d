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

module interp.tests;

import std.stdio;
import std.string;
import std.math;
import std.conv;
import parser.parser;
import ir.ast;
import interp.layout;
import interp.interp;
import repl;

/**
Interpreter which doesn't load the standard library
*/
class InterpNoStdLib : Interp
{
    this()
    {
        super(true, false);
    }
}

void assertInt(Interp interp, string input, int32 intVal)
{
    //writeln(input);

    assert (
        interp !is null,
        "interp object is null"
    );

    auto ret = interp.evalString(input);

    assert (
        ret.type == Type.INT32,
        "non-integer value: " ~ valToString(ret)
    );

    assert (
        ret.word.int32Val == intVal,
        format(
            "Test failed:\n" ~
            "%s" ~ "\n" ~
            "incorrect integer value: %s, expected: %s",
            input,
            ret.word.int32Val, 
            intVal
        )
    );
}

void assertFloat(Interp interp, string input, double floatVal, double eps = 1E-4)
{
    auto ret = interp.evalString(input);

    assert (
        ret.type == Type.INT32 ||
        ret.type == Type.FLOAT64,
        "non-numeric value: " ~ valToString(ret)
    );

    auto fRet = (ret.type == Type.FLOAT64)? ret.word.floatVal:ret.word.int32Val;

    assert (
        abs(fRet - floatVal) <= eps,
        format(
            "Test failed:\n" ~
            "%s" ~ "\n" ~
            "incorrect float value: %s, expected: %s",
            input,
            fRet, 
            floatVal
        )
    );
}

void assertBool(Interp interp, string input, bool boolVal)
{
    auto ret = interp.evalString(input);

    assert (
        ret.type == Type.CONST,
        "non-const value: " ~ valToString(ret)
    );

    assert (
        ret.word == (boolVal? TRUE:FALSE),
        format(
            "Test failed:\n" ~
            "%s" ~ "\n" ~
            "incorrect boolean value: %s, expected: %s",
            input,
            valToString(ret), 
            boolVal
        )
    );
}

void assertThrows(Interp interp, string input)
{
    try
    {
        interp.evalString(input);
    }

    catch (RunError e)
    {
        return;
    }

    throw new Error(
        format(
            "Test failed:\n" ~
            "%s" ~ "\n" ~
            "no exception thrown",
            input
        )
    );
}

void assertStr(Interp interp, string input, string strVal)
{
    auto ret = interp.evalString(input);

    assert (
        valIsString(ret.word, ret.type),
        "non-string value: " ~ valToString(ret)
    );

    auto outStr = valToString(ret);

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
    Word w0 = Word.int32v(0);
    Word w1 = Word.int32v(1);
    assert (w0.int32Val != w1.int32Val);
}

unittest
{
    writefln("interpreter core");

    // Create an interpreter without a runtime or stdlib
    auto interp = new Interp(false, false);

    // Do nothing
    interp.evalString("");

    // Constant integer 1
    auto v = interp.evalString("1");
    assert (v.word.int32Val == 1);
    assert (v.type is Type.INT32);

    // 32-bit integer add
    interp.assertInt("$ir_add_i32(1, 2)", 3);

    // Global property access (needed by runtime lib)
    interp.evalString("x = 7");
    interp.assertInt("x = 7; return x;", 7);

    // Integer arithmetic
    interp.assertInt("x = 3; return $ir_add_i32(x, 2)", 5);
    interp.assertInt("x = 3; return $ir_sub_i32(x, 1)", 2);
    interp.assertInt("x = 3; return $ir_mul_i32(x, 2)", 6);

    // Comparison and conditional branching
    interp.assertInt("x = 7; if ($ir_eq_i32(x, 7)) return 1; else return 0;", 1);
    interp.assertInt("x = 3; if ($ir_eq_i32(x, 2)) x = 1; return x;", 3);
    interp.assertInt("x = 5; if ($ir_is_i32(x)) x = 1; else x = 0; return x;", 1);

    // Add with overflow test
    interp.assertInt("x = 3; if ($ir_add_i32_ovf(x, 1)) return x; else return -1;", 3);
}

/// Global expression tests
unittest
{
    writefln("global expressions");

    auto interp = new InterpNoStdLib();

    interp.assertInt("return 7", 7);
    interp.assertInt("return 1 + 2", 3);
    interp.assertInt("return 5 - 1", 4);
    interp.assertInt("return 8 % 5", 3);
    interp.assertInt("return 5 % 3", 2);
    interp.assertInt("return -3", -3);
    interp.assertInt("return +7", 7);

    interp.assertInt("return 2 + 3 * 4", 14);
    interp.assertInt("return 1 - (2+3)", -4);
    interp.assertInt("return 6 - (3-3)", 6);
    interp.assertInt("return 3 - 3 - 3", -3);

    interp.assertInt("return 5 | 3", 7);
    interp.assertInt("return 5 & 3", 1);
    interp.assertInt("return 5 ^ 3", 6);
    interp.assertInt("return 5 << 2", 20);
    interp.assertInt("return 7 >> 1", 3);
    interp.assertInt("return 7 >>> 1", 3);
    interp.assertInt("return ~2", -3);
    interp.assertInt("return undefined | 1", 1);

    interp.assertFloat("return 3.5", 3.5);
    interp.assertFloat("return 2.5 + 2", 4.5);
    interp.assertFloat("return 2.5 + 2.5", 5);
    interp.assertFloat("return 2.5 - 1", 1.5);
    interp.assertFloat("return 2 * 1.5", 3);
    interp.assertFloat("return 6 / 2.5", 2.4);
    interp.assertFloat("return 0.5 % 0.2", 0.1);
    interp.assertFloat("return 6/2/2", 1.5);
    interp.assertFloat("return 6/2*2", 6);

    interp.assertFloat("return 100 * '5'", 500);
    interp.assertFloat("return 100 / '5'", 20);

    interp.assertBool("!true", false);
    interp.assertBool("!false", true);
    interp.assertBool("!0", true);
}

/// Global function calls
unittest
{
    writefln("global functions");

    auto interp = new InterpNoStdLib();

    interp.assertInt("return function () { return 9; } ()", 9);
    interp.assertInt("return function () { return 2 * 3; } ()", 6);

    // TODO
    // Calling null as a function
    //interp.assertThrows("null()");
}

/// Argument passing test
unittest
{
    writefln("argument passing");

    auto interp = new InterpNoStdLib();

    interp.assertInt("return function (x) { return x; } (7)", 7);
    interp.assertInt("return function (x) { return x + 3; } (5)", 8);
    interp.assertInt("return function (x, y) { return x - y; } (5, 2)", 3);

    // Too many arguments
    interp.assertInt("return function () { return 7; } (5)", 7);
    interp.assertInt("return function (x) { return x + 1; } (5, 9)", 6);

    // Too few arguments
    interp.assertInt("return function (x) { return 9; } ()", 9);
    interp.assertInt("return function (x, y) { return x - 1; } (4)", 3);
    interp.assertInt("return function (x,y,z,w) { return 0; } (1,2,3)", 0);
}

/// Local variable assignment
unittest
{
    writefln("local variables");

    auto interp = new InterpNoStdLib();

    interp.assertInt("return function () { var x = 4; return x; } ()", 4);
    interp.assertInt("return function () { var x = 0; return x++; } ()", 0);
    interp.assertInt("return function () { var x = 0; return ++x; } ()", 1);
    interp.assertInt("return function () { var x = 0; return x--; } ()", 0);
    interp.assertInt("return function () { var x = 0; return --x; } ()", -1);
    interp.assertInt("return function () { var x = 0; ++x; return ++x; } ()", 2);
    interp.assertInt("return function () { var x = 0; return x++ + 1; } ()", 1);
    interp.assertInt("return function () { var x = 1; return x = x++ % 2; } ()", 1);
    interp.assertBool("return function () { var x; return (x === undefined); } ()", true);
}

/// Comparison and branching
unittest
{
    writefln("comparison and branching");

    auto interp = new InterpNoStdLib();

    interp.assertInt("if (true) return 1; else return 0;", 1);
    interp.assertInt("if (false) return 1; else return 0;", 0);
    interp.assertInt("if (3 < 7) return 1; else return 0;", 1);
    interp.assertInt("if (5 < 2) return 1; else return 0;", 0);
    interp.assertInt("if (1 < 1.5) return 1; else return 0;", 1);

    interp.assertBool("3 <= 5", true);
    interp.assertBool("5 <= 5", true);
    interp.assertBool("7 <= 5", false);
    interp.assertBool("7 > 5", true);
    interp.assertBool("true == false", false);
    interp.assertBool("true === true", true);
    interp.assertBool("true !== false", true);
    interp.assertBool("3 === 3.0", true);
    interp.assertBool("3 !== 3.5", true);

    interp.assertBool("return 1 < undefined", false);
    interp.assertBool("return 1 > undefined", false);
    interp.assertBool("return 0.5 == null", false);
    interp.assertBool("return 'Foo' != null", true);
    interp.assertBool("return null != null", false);
    interp.assertBool("return 'Foo' == null", false);
    interp.assertBool("return undefined == undefined", true);
    interp.assertBool("return undefined == null", true);
    interp.assertBool("o = {}; return o == o", true);
    interp.assertBool("oa = {}; ob = {}; return oa == ob", false);

    interp.assertInt("return true? 1:0", 1);
    interp.assertInt("return false? 1:0", 0);

    interp.assertInt("return 0 || 2", 2);
    interp.assertInt("return 1 || 2", 1);
    interp.assertInt("1 || 2; return 3", 3);
    interp.assertInt("return 0 || 0 || 3", 3);
    interp.assertInt("return 0 || 2 || 3", 2);
    interp.assertInt("if (0 || 2) return 1; else return 0;", 1);
    interp.assertInt("if (1 || 2) return 1; else return 0;", 1);
    interp.assertInt("if (0 || 0) return 1; else return 0;", 0);

    interp.assertInt("return 0 && 2", 0);
    interp.assertInt("return 1 && 2", 2);
    interp.assertInt("return 1 && 2 && 3", 3);
    interp.assertInt("return 1 && 0 && 3", 0);
    interp.assertInt("if (0 && 2) return 1; else return 0;", 0);
    interp.assertInt("if (1 && 2) return 1; else return 0;", 1);
}

/// Recursion
unittest
{
    writefln("recursion");

    auto interp = new InterpNoStdLib();

    interp.assertInt(
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

    interp.assertInt(
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
    writefln("loops");

    auto interp = new InterpNoStdLib();

    interp.assertInt(
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

    interp.assertInt(
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

    interp.assertInt(
        "
        return function ()
        {
            var sum = 0;
            var i = 0;
            while (i < 10)
            {
                if ((i++ % 2) === 0)
                    continue;

                sum = sum + i;
            }

            return sum;
        } ();
        ",
        30
    );

    interp.assertInt(
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

    interp.assertInt(
        "
        return function ()
        {
            for (var i = 0; i < 10; ++i);
            return i;
        } ();
        ",
        10
    );

    interp.assertInt(
        "
        return function ()
        {
            for (var i = 0; i < 10; ++i)
            {
                if (i % 2 === 0)
                    continue;
                if (i === 5)
                    break;
            }
            return i;
        } ();
        ",
        5
    );
}

/// Switch statement
unittest
{
    writefln("switch");

    auto interp = new InterpNoStdLib();

    interp.assertInt(
        "
        switch (0)
        {
        }
        return 0;
        ",
        0
    );

    interp.assertInt(
        "
        switch (0)
        {
            case 0:
            return 1;
        }
        return 0;
        ",
        1
    );

    interp.assertInt(
        "
        switch (3)
        {
            case 0:
            return 1;
        }
        return 0;
        ",
        0
    );

    interp.assertInt(
        "
        var v;
        switch (0)
        {
            case 0: v = 5;
            case 1: v += 1; break;
            case 2: v = 7; break;
            default: v = 9;
        }
        return v;
        ",
        6
    );

    interp.assertInt(
        "
        var v;
        switch (3)
        {
            case 0: v = 5;
            case 1: v += 1; break;
            case 2: v = 7; break;
            default: v = 9;
        }
        return v;
        ",
        9
    );

    interp.assertInt(
        "
        var v;
        switch (2)
        {
            case 2: v = 7;
            default: v += 1;
        }
        return v;
        ",
        8
    );

    interp.assertInt(
        "
        var v;
        switch (2)
        {
            case 2: v = 7;
            default: v += 1; break;
        }
        return v;
        ",
        8
    );
}

/// Strings
unittest
{
    writefln("strings");

    auto interp = new InterpNoStdLib();

    interp.assertStr("return 'foo'", "foo");
    interp.assertStr("return 'foo' + 'bar'", "foobar");
    interp.assertStr("return 'foo' + 1", "foo1");
    interp.assertStr("return 'foo' + true", "footrue");
    interp.assertInt("return 'foo'? 1:0", 1);
    interp.assertInt("return ''? 1:0", 0);
    interp.assertBool("return ('foo' === 'foo')", true);
    interp.assertBool("return ('foo' === 'f' + 'oo')", true);
    interp.assertBool("return ('bar' == 'bar')", true);
    interp.assertBool("return ('bar' != 'b')", true);
    interp.assertBool("return ('bar' != 'bar')", false);

    interp.assertStr(
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

// Typeof operator
unittest
{
    writefln("typeof");

    auto interp = new InterpNoStdLib();

    interp.assertStr("return typeof 'foo'", "string");
    interp.assertStr("return typeof 1", "number");
    interp.assertStr("return typeof true", "boolean");
    interp.assertStr("return typeof false", "boolean");
    interp.assertStr("return typeof null", "object");
    interp.assertInt("return (typeof 'foo' === 'string')? 1:0", 1);
    interp.assertStr("x = 3; return typeof x;", "number");
    interp.assertStr("delete x; return typeof x;", "undefined");
}

/// Global scope, global object
unittest
{
    writefln("global object");

    auto interp = new InterpNoStdLib();

    interp.assertBool("var x; return !x", true);
    interp.assertInt("a = 1; return a;", 1);
    interp.assertInt("var a; a = 1; return a;", 1);
    interp.assertInt("var a = 1; return a;", 1);
    interp.assertInt("a = 1; b = 2; return a+b;", 3);
    interp.assertInt("var x=3,y=5; return x;", 3);

    interp.assertInt("return a = 1,2;", 2);
    interp.assertInt("a = 1,2; return a;", 1);
    interp.assertInt("a = (1,2); return a;", 2);

    interp.assertInt("f = function() { return 7; }; return f();", 7);
    interp.assertInt("function f() { return 9; }; return f();", 9);
    interp.assertInt("(function () {}); return 0;", 0);
    interp.assertInt("a = 7; function f() { return this.a; }; return f();", 7);

    interp.assertInt(
        "
        function fib(n)
        {
            if (n < 2)
                return n;
            else   
                return fib(n-1) + fib(n-2);
        }

        return fib(6);
        ",
        8
    );

    // Unresolved global
    //interp.assertThrows("foo5783");

    // Many global variables
    interp = new InterpNoStdLib();
    interp.load("programs/many_globals/many_globals.js");
    interp = new InterpNoStdLib();
    interp.load("programs/many_globals/many_globals2.js");
    // TODO: requires gc_collect
    //interp = new InterpNoStdLib();
    //interp.load("programs/many_globals/many_globals3.js");
}

/// In-place operators
unittest
{
    writefln("in-place operators");

    auto interp = new InterpNoStdLib();

    interp.assertInt("a = 1; a += 2; return a;", 3);
    interp.assertInt("a = 1; a += 4; a -= 3; return a;", 2);
    interp.assertInt("a = 1; b = 3; a += b; return a;", 4);
    interp.assertInt("a = 1; b = 3; return a += b;", 4);
    interp.assertInt("a = 3; a -= 2; return a", 1);
    interp.assertInt("a = 5; a %= 3; return a", 2);
    interp.assertInt("function f() { var a = 0; a += 1; a += 1; return a; }; return f();", 2);
    interp.assertInt("function f() { var a = 0; a += 2; a *= 3; return a; }; return f();", 6);
}

/// Object literals, property access, method calls
unittest
{
    writefln("objects and properties");

    auto interp = new InterpNoStdLib();

    interp.assertInt("{}; return 1;", 1);
    interp.assertInt("{x: 7}; return 1;", 1);
    interp.assertInt("o = {}; o.x = 7; return 1;", 1);
    interp.assertInt("o = {}; o.x = 7; return o.x;", 7);
    interp.assertInt("o = {x: 9}; return o.x;", 9);
    interp.assertInt("o = {x: 9}; o.y = 1; return o.x + o.y;", 10);
    interp.assertInt("o = {x: 5}; o.x += 1; return o.x;", 6);
    interp.assertInt("o = {x: 5}; return o.y? 1:0;", 0);

    // In operator
    interp.assertBool("o = {x: 5}; return 'x' in o;", true);
    interp.assertBool("o = {x: 5}; return 'k' in o;", false);

    // Delete operator
    interp.assertBool("o = {x: 5}; delete o.x; return 'x' in o;", false);
    interp.assertBool("o = {x: 5}; delete o.x; return !o.x;", true);
    // TODO
    //interp.assertThrows("a = 5; delete a; a;");

    // Function object property
    interp.assertInt("function f() { return 1; }; f.x = 3; return f() + f.x;", 4);

    // Method call
    interp.assertInt("o = {x:7, m:function() {return this.x;}}; return o.m();", 7);

    // Object extension and equality
    interp.assertBool("o = {x: 5}; ob = o; o.y = 3; o.z = 6; return (o === ob);", true);  
}

/// New operator, prototype chain
unittest
{
    writefln("new operator");

    auto interp = new InterpNoStdLib();

    interp.assertInt("function f() {}; o = new f(); return 0", 0);
    interp.assertInt("function f() {}; o = new f(); return (o? 1:0)", 1);
    interp.assertInt("function f() { g = this; }; o = new f(); return g? 1:0", 1);
    interp.assertInt("function f() { this.x = 3 }; o = new f(); return o.x", 3);
    interp.assertInt("function f() { return {y:7}; }; o = new f(); return o.y", 7);

    interp.assertInt("function f() {}; return f.prototype? 1:0", 1);
    interp.assertInt("function f() {}; f.prototype.x = 9; return f.prototype.x", 9);

    interp.assertBool(
        "
        function f() {}
        a = new f();
        a.x = 3;
        b = new f();
        return (b.x === undefined);
        ",
        true
    );

    interp.assertInt(
        "
        function f() {}
        a = new f();
        b = new f();
        a.p0 = 0; a.p1 = 1; a.p2 = 2; a.p3 = 3;
        b.p3 = 4;
        return b.p3;
        ",
        4
    );

    interp.assertBool(
        "
        function f() {}
        f.prototype.y = 3;
        a = new f();
        a.x = 3;
        b = new f();
        return ('x' in a) && !('x' in b) && ('y' in b);
        ",
        true
    );

    interp.assertBool(
        "
        function f() {}
        f.x = 1;
        f.y = 2;
        o = new f();
        o.y = 3;
        return ('x' in f) && !('x' in o);
        ",
        true
    );

    interp.assertInt(
        "
        function f() {}
        f.prototype.x = 9;
        o = new f();
        return o.x;
        ",
        9
    );

    interp.assertInt(
        "
        function f() {}
        f.prototype.x = 9;
        f.prototype.y = 1;
        o = new f();
        return o.x;
        ",
        9
    );

    interp.assertInt(
        "
        function f() {}
        f.prototype.x = 9;
        f.prototype.y = 1;
        f.prototype.z = 2;
        o = new f();
        return o.x + o.y + o.z;
        ",
        12
    );
}

/// Array literals, array operations
unittest
{
    writefln("arrays");

    auto interp = new InterpNoStdLib();
 
    interp.assertInt("a = []; return 0", 0);
    interp.assertInt("a = [1]; return 0", 0);
    interp.assertInt("a = [1,2]; return 0", 0);
    interp.assertInt("a = [1,2]; return a[0]", 1);
    interp.assertInt("a = [1,2]; a[0] = 3; return a[0]", 3);
    interp.assertInt("a = [1,2]; a[3] = 4; return a[1]", 2);
    interp.assertInt("a = [1,2]; a[3] = 4; return a[3]", 4);
    interp.assertInt("a = [1,2]; return a[3]? 1:0;", 0);
    interp.assertInt("a = [1337]; return a['0'];", 1337);
    interp.assertInt("a = []; a['0'] = 55; return a[0];", 55);
}

/// Inline IR and JS extensions
unittest
{
    writefln("inline IR");

    auto interp = new InterpNoStdLib();

    interp.assertStr("typeof $undef", "undefined");
    interp.assertStr("typeof $nullptr", "rawptr");
    interp.assertStr("typeof $argc", "number");

    interp.assertInt("return $ir_add_i32(5,3);", 8);
    interp.assertInt("return $ir_sub_i32(5,3);", 2);
    interp.assertInt("return $ir_mul_i32(5,3);", 15);
    interp.assertInt("return $ir_div_i32(5,3);", 1);
    interp.assertInt("return $ir_mod_i32(5,3);", 2);
    interp.assertInt("return $ir_eq_i32(3,3)? 1:0;", 1);
    interp.assertInt("return $ir_eq_i32(3,2)? 1:0;", 0);
    interp.assertInt("return $ir_ne_i32(3,5)? 1:0;", 1);
    interp.assertInt("return $ir_ne_i32(3,3)? 1:0;", 0);
    interp.assertInt("return $ir_lt_i32(3,5)? 1:0;", 1);
    interp.assertInt("return $ir_ge_i32(5,5)? 1:0;", 1);

    interp.assertInt(
        "
        function foo()
        {
            var o;
            if (o = $ir_add_i32_ovf(1, 2))
                return o;
            else
                return -1;
        }
        return foo();
        ",
        3
    );

    interp.assertInt(
        "
        function foo()
        {
            var o;
            if (o = $ir_add_i32_ovf(0x7FFFFFFF, 1))
                return o;
            else
                return -1;
        }
        return foo();
        ",
        -1
    );

    interp.assertInt(
        "
        function foo()
        {
            var o;
            if (o = $ir_add_i32_ovf(1 << 31, 1 << 31))
                return o;
            else
                return -1;
        }
        return foo();
        ",
        -1
    );

    interp.assertInt(
        "
        function foo()
        {
            var o;
            if (o = $ir_mul_i32_ovf(4, 4))
                return o;
            else
                return -1;
        }
        return foo();
        ",
        16
    );

    interp.assertInt(
        "
        var ptr = $ir_heap_alloc(16);
        $ir_store_u8(ptr, 0, 77);
        return $ir_load_u8(ptr, 0);
        ",
        77
    );

    /*
    interp.assertInt(
        "
        var link = $ir_make_link(0);
        $ir_set_link(link, 133);
        return $ir_get_link(link);
        ",
        133
    );

    interp.assertInt(
        "
        var sum = 0;
        for (var i = 0; i < 10; ++i)
        {
            var link = $ir_make_link(0);
            if (i === 0)
                $ir_set_link(link, 1);
            sum += $ir_get_link(link);
        }
        return sum;
        ",
        10
    );
    */
}

/// Runtime functions
unittest
{
    writefln("runtime");

    auto interp = new InterpNoStdLib();

    interp.assertInt("$rt_toBool(0)? 1:0", 0);
    interp.assertInt("$rt_toBool(5)? 1:0", 1);
    interp.assertInt("$rt_toBool(true)? 1:0", 1);
    interp.assertInt("$rt_toBool(false)? 1:0", 0);
    interp.assertInt("$rt_toBool(null)? 1:0", 0);
    interp.assertInt("$rt_toBool('')? 1:0", 0);
    interp.assertInt("$rt_toBool('foo')? 1:0", 1);

    interp.assertStr("$rt_toString(5)", "5");
    interp.assertStr("$rt_toString('foo')", "foo");
    interp.assertStr("$rt_toString(null)", "null");
    interp.assertStr("$rt_toString({toString: function(){return 's';}})", "s");

    interp.assertInt("$rt_add(5, 3)", 8);
    interp.assertFloat("$rt_add(5, 3.5)", 8.5);
    interp.assertStr("$rt_add(5, 'bar')", "5bar");
    interp.assertStr("$rt_add('foo', 'bar')", "foobar");

    interp.assertInt("$rt_sub(5, 3)", 2);
    interp.assertFloat("$rt_sub(5, 3.5)", 1.5);

    interp.assertInt("$rt_mul(3, 5)", 15);
    interp.assertFloat("$rt_mul(5, 1.5)", 7.5);
    interp.assertFloat("$rt_mul(0xFFFF, 0xFFFF)", 4294836225);

    interp.assertFloat("$rt_div(15, 3)", 5);
    interp.assertFloat("$rt_div(15, 1.5)", 10);

    interp.assertBool("$rt_eq(3,3)", true);
    interp.assertBool("$rt_eq(3,5)", false);
    interp.assertBool("$rt_eq('foo','foo')", true);

    interp.assertInt("isNaN(3)? 1:0", 0);
    interp.assertInt("isNaN(3.5)? 1:0", 0);
    interp.assertInt("isNaN(NaN)? 1:0", 1);
    interp.assertStr("$rt_toString(NaN);", "NaN");

    interp.assertInt("$rt_getProp('foo', 'length')", 3);
    interp.assertStr("$rt_getProp('foo', 0)", "f");
    interp.assertInt("$rt_getProp([0,1], 'length')", 2);
    interp.assertInt("$rt_getProp([3,4,5], 1)", 4);
    interp.assertInt("$rt_getProp({v:7}, 'v')", 7);
    interp.assertInt("a = [0,0,0]; $rt_setProp(a,1,5); return $rt_getProp(a,1);", 5);
    interp.assertInt("a = [0,0,0]; $rt_setProp(a,9,7); return $rt_getProp(a,9);", 7);
    interp.assertInt("a = []; $rt_setProp(a,'length',5); return $rt_getProp(a,'length');", 5);

    interp.assertInt(
        "
        o = {};
        $rt_setProp(o,'a',1);
        $rt_setProp(o,'b',2);
        $rt_setProp(o,'c',3);
        return $rt_getProp(o,'c');
        ",
        3
    );

    // TODO: exception support
    //interp.assertThrows("false instanceof false");
    //interp.assertThrows("2 in null");
    interp.assertBool("'foo' in {}", false);
}

/// Closures, captured and escaping variables
unittest
{
    writefln("closures");

    auto interp = new InterpNoStdLib();

    interp.assertInt(
        "
        function foo(x) { return function() { return x; } }
        f = foo(5);
        return f();
        ",
        5
    );

    interp.assertInt(
        "
        function foo(x) { var y = x + 1; return function() { return y; } }
        f = foo(5);
        return f();
        ",
        6
    );

    interp.assertInt(
        "
        function foo(x) { return function() { return x++; } }
        f = foo(5);
        f();
        return f();
        ",
        6
    );

    interp.assertInt(
        "
        function foo(x)
        {
            function bar()
            {
                function bif()
                {
                    x += 1;
                }
                bif();
            }
            bar();
            return x;
        }
        return foo(5);
        ",
        6
    );
}

/// Stdlib Math library
unittest
{
    writefln("stdlib/math");

    auto interp = new Interp();

    interp.assertInt("Math.max(1,2);", 2);
    interp.assertInt("Math.max(5,1,2);", 5);
    interp.assertInt("Math.min(5,-1,2);", -1);

    interp.assertFloat("Math.cos(0)", 1);
    interp.assertFloat("Math.cos(Math.PI)", -1);
    interp.assertInt("isNaN(Math.cos('f'))? 1:0", 1);

    interp.assertFloat("Math.sin(0)", 0);
    interp.assertFloat("Math.sin(Math.PI)", 0);

    interp.assertFloat("Math.sqrt(4)", 2);

    interp.assertInt("Math.pow(2, 0)", 1);
    interp.assertInt("Math.pow(2, 4)", 16);
    interp.assertInt("Math.pow(2, 8)", 256);

    interp.assertFloat("Math.log(Math.E)", 1);
    interp.assertFloat("Math.log(1)", 0);

    interp.assertFloat("Math.exp(0)", 1);

    interp.assertFloat("Math.ceil(1.5)", 2);
    interp.assertInt("Math.ceil(2)", 2);

    interp.assertFloat("Math.floor(1.5)", 1);
    interp.assertInt("Math.floor(2)", 2);

    interp.assertBool("r = Math.random(); return r >= 0 && r < 1;", true);
    interp.assertBool("r0 = Math.random(); r1 = Math.random(); return r0 !== r1;", true);
}

/// Stdlib Object library
unittest
{
    writefln("stdlib/object");

    auto interp = new Interp();

    interp.assertBool("o = {k:3}; return o.hasOwnProperty('k');", true);
    interp.assertBool("o = {k:3}; p = Object.create(o); return p.hasOwnProperty('k')", false);
    interp.assertBool("o = {k:3}; p = Object.create(o); return 'k' in p;", true);
}

/// Stdlib Number library
unittest
{
    writefln("stdlib/number");

    auto interp = new Interp();

    interp.assertInt("Number(10)", 10);
    interp.assertInt("Number(true)", 1);
    interp.assertInt("Number(null)", 0);

    interp.assertStr("(10).toString()", "10");
}

/// Stdlib Array library
unittest
{
    writefln("stdlib/array");

    auto interp = new Interp();

    interp.assertInt("a = Array(10); return a.length;", 10);
    interp.assertInt("a = Array(1,2,3); return a.length;", 3);
    interp.assertStr("([0,1,2]).toString()", "0,1,2");
}

/// Stdlib String library
unittest
{
    writefln("stdlib/string");

    auto interp = new Interp();

    interp.assertStr("String(10)", "10");
    interp.assertStr("String(1.5)", "1.5");
    interp.assertStr("String([0,1,2])", "0,1,2");

    interp.assertStr("'foobar'.substring(0,3)", "foo");
    interp.assertInt("'f,o,o'.split(',').length", 3);
}

/// Stdlib global functions
unittest
{
    writefln("stdlib/global");

    auto interp = new Interp();

    interp.assertInt("parseInt(10)", 10);
    interp.assertInt("parseInt(-1)", -1);
    interp.assertBool("isNaN(parseInt('zux'))", true);
}

/*
/// Exceptions
unittest
{
    writefln("exceptions");

    auto interp = new Interp();

    // Intraprocedural tests
    interp.load("programs/exceptions/throw_intra.js");
    interp.assertStr("str;", "abc");
    interp.load("programs/exceptions/finally_ret.js");
    interp.assertStr("test();", "abcd");
    interp.assertStr("str;", "abcdef");
    interp.load("programs/exceptions/finally_break.js");
    interp.assertStr("test(); return str;", "abcdefg");
    interp.load("programs/exceptions/finally_cont.js");
    interp.assertStr("test(); return str;", "abcdefbcdefg");
    interp.load("programs/exceptions/finally_throw.js");
    interp.assertStr("test(); return str;", "abcdefghijk");
    interp.load("programs/exceptions/throw_in_finally.js");
    interp.assertStr("str;", "abcdef");
    interp.load("programs/exceptions/throw_in_catch.js");
    interp.assertStr("str;", "abcdefg");

    // Interprocedural tests
    interp.load("programs/exceptions/throw_inter.js");
    interp.assertInt("test();", 0);
    interp.load("programs/exceptions/throw_inter_fnl.js");
    interp.assertStr("str;", "abcdef");
    interp.load("programs/exceptions/try_call.js");
    interp.assertStr("str;", "abc");
}
*/

/// Basic test programs
unittest
{
    writefln("basic");

    auto interp = new Interp();

    // Basic suite
    interp.load("programs/basic_arith/basic_arith.js");
    interp.assertInt("test();", 0);
    interp.load("programs/basic_shift/basic_shift.js");
    interp.assertInt("test();", 0);
    interp.load("programs/basic_bitops/basic_bitops.js");
    interp.assertInt("test();", 0);
    interp.load("programs/basic_assign/basic_assign.js");
    interp.assertInt("test();", 0);
    interp.load("programs/basic_cmp/basic_cmp.js");
    interp.assertInt("test();", 0);
    interp.load("programs/basic_bool_eval/basic_bool_eval.js");
    interp.assertInt("test();", 0);
}

/// Regression tests
unittest
{
    writefln("regression");

    Interp interp;

    interp = new Interp();

    interp.assertBool("4294967295.0 === 0xFFFFFFFF", true);

    interp.load("programs/regress/post_incr.js");
    interp.load("programs/regress/in_operator.js");
    interp.load("programs/regress/tostring.js");
    // TODO: needs throw
    //interp.load("programs/regress/new_array.js");
    interp.load("programs/regress/loop_labels.js");
    interp.load("programs/regress/loop_swap.js");
    interp.load("programs/regress/loop_lt.js");
    interp.load("programs/regress/loop_lessargs.js");
    interp.load("programs/regress/loop_new.js");
    interp.load("programs/regress/loop_argc.js");
    interp.load("programs/regress/loop_bool.js");
    interp.load("programs/regress/loop_decr_sum.js");
    interp.load("programs/regress/dowhile_cont.js");
    interp.load("programs/regress/vers_pathos.js");

    interp.load("programs/regress/jit_se_cmp.js");
    interp.load("programs/regress/jit_float_cmp.js");
    interp.load("programs/regress/jit_getprop_arr.js");
    // TODO: needs exceptions
    //interp.load("programs/regress/jit_call_exc.js");
    interp.load("programs/regress/jit_ctor.js");
    // TODO: needs gc_collect
    //interp.load("programs/regress/jit_set_global.js");
    interp.load("programs/regress/jit_inlining.js");
    interp.load("programs/regress/jit_inlining2.js");

    interp.load("programs/regress/delta.js");
    interp.load("programs/regress/raytrace.js");

    // TODO: needs gc_collect
    //interp = new Interp();
    //interp.load("programs/regress/boyer.js");
}

/// Tachyon tests
unittest
{
    writefln("tachyon");

    auto interp = new Interp();

    // ES5 comparison operator test
    writeln("es5 comparisons");
    interp.load("programs/es5_cmp/es5_cmp.js");
    interp.assertInt("test();", 0);

    // Recursive Fibonacci computation
    writeln("fib");
    interp.load("programs/fib/fib.js");
    interp.assertInt("fib(8);", 21);

    writeln("nested loops");
    interp.load("programs/nested_loops/nested_loops.js");
    interp.assertInt("foo(10);", 510);

    writeln("bubble sort");
    interp.load("programs/bubble_sort/bubble_sort.js");
    interp.assertInt("test();", 0);

    // N-queens solver
    writeln("n-queens");
    interp.load("programs/nqueens/nqueens.js");
    interp.assertInt("test();", 0);

    writeln("merge sort");
    interp.load("programs/merge_sort/merge_sort.js");
    interp.assertInt("test();", 0);

    writeln("matrix comp");
    interp.load("programs/matrix_comp/matrix_comp.js");
    interp.assertInt("test();", 10);

    writefln("closures");

    // Closures
    interp.load("programs/clos_capt/clos_capt.js");
    interp.assertInt("foo(5);", 8);
    interp.load("programs/clos_access/clos_access.js");
    interp.assertInt("test();", 0);
    interp.load("programs/clos_globals/clos_globals.js");
    interp.assertInt("test();", 0);
    interp.load("programs/clos_xcall/clos_xcall.js");
    interp.assertInt("test(5);", 5);

    /*
    writefln("apply");

    // Call with apply
    interp.load("programs/apply/apply.js");
    interp.assertInt("test();", 0);
    */

    writefln("arguments");

    // Arguments object
    interp.load("programs/arg_obj/arg_obj.js");
    interp.assertInt("test();", 0);

    /*
    writefln("for-in");

    // For-in loop
    interp.load("programs/for_in/for_in.js");
    interp.assertInt("test();", 0);
    */

    writefln("stdlib");

    // Standard library
    interp.load("programs/stdlib_math/stdlib_math.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_boolean/stdlib_boolean.js");
    interp.assertInt("test();", 0);
    // TODO: needs apply
    //interp.load("programs/stdlib_number/stdlib_number.js");
    //interp.assertInt("test();", 0);
    // TODO: needs apply
    //interp.load("programs/stdlib_function/stdlib_function.js");
    //interp.assertInt("test();", 0);
    // TODO: need map_prop_name
    //interp.load("programs/stdlib_object/stdlib_object.js");
    //interp.assertInt("test();", 0);
    // TODO: needs apply
    //interp.load("programs/stdlib_array/stdlib_array.js");
    //interp.assertInt("test();", 0);
    // TODO: needs apply
    //interp.load("programs/stdlib_string/stdlib_string.js");
    //interp.assertInt("test();", 0);
    // TODO: need map_prop_name
    //interp.load("programs/stdlib_json/stdlib_json.js");
    //interp.assertInt("test();", 0);
    // TODO: throw
    //interp.load("programs/stdlib_regexp/stdlib_regexp.js");
    //interp.assertInt("test();", 0);
    // FIXME: segmentation fault
    //interp.load("programs/stdlib_map/stdlib_map.js");
    //interp.assertInt("test();", 0);
}

/*
/// Dynamic code loading and eval
unittest
{
    auto interp = new Interp();

    writefln("load");

    // Dynamic code loading
    interp.load("programs/load/loader.js");

    // Loading a missing file
    interp.assertThrows("load('_filethatdoesntexist123_')");

    // Eval
    interp.load("programs/eval/eval.js");
}

/// Garbage collector tests
unittest
{
    writefln("garbage collector");

    Interp interp;

    interp = new Interp();
    interp.assertInt("v = 3; $ir_gc_collect(0); return v;", 3);

    interp = new Interp();
    interp.assertInt("
        function f() 
        { 
            a = []; 
            a.length = 1000; 
            $ir_gc_collect(0); 
            return a.length; 
        }
        return f();",
        1000
    );

    writefln("gc/collect");

    interp = new Interp();
    interp.load("programs/gc/collect.js");
    interp.assertInt("test();", 0);

    writefln("gc/objects");

    interp = new Interp();
    interp.load("programs/gc/objects.js");

    writefln("gc/arrays");

    interp = new Interp();
    interp.load("programs/gc/arrays.js");

    writefln("gc/closures");

    interp = new Interp();
    interp.load("programs/gc/closures.js");
    interp.assertInt("test();", 0);

    writefln("gc/objext");

    interp = new Interp();
    interp.load("programs/gc/objext.js");

    writefln("gc/deepstack");
  
    interp = new Interp();
    interp.load("programs/gc/deepstack.js");
    interp.assertInt("test();", 0);

    writefln("gc/bigloop");

    interp = new Interp();
    interp.load("programs/gc/bigloop.js");

    writefln("gc/apply");

    interp = new Interp();
    interp.load("programs/gc/apply.js");
    interp.assertInt("test();", 0);

    writefln("gc/arguments");

    interp = new Interp();
    interp.load("programs/gc/arguments.js");
    interp.assertInt("test();", 0);

    writefln("gc/strcat");

    interp = new Interp();
    interp.load("programs/gc/strcat.js");
    interp.assertInt("test();", 0);

    writefln("gc/graph");

    interp = new Interp();
    interp.load("programs/gc/graph.js");
    interp.assertInt("test();", 0);

    writefln("gc/stackvm");

    interp = new Interp();
    interp.load("programs/gc/stackvm.js");
    interp.assertInt("test();", 0);

    writefln("gc/load");

    interp = new Interp();
    interp.load("programs/gc/load.js");
    interp.assertInt("theFlag;", 1337);
}

/// Misc benchmarks
unittest
{
    auto interp = new Interp();

    writefln("misc/bones");
    interp.load("programs/bones/bones.js");
}
*/

/// Computer Language Shootout benchmarks
unittest
{
    writefln("shootout");

    auto interp = new Interp();

    // Silence the print function
    interp.evalString("print = function (s) {}");

    void run(string name, size_t n)
    {
        writefln("shootout/%s", name);
        interp.evalString("arguments = [" ~ to!string(n) ~ "];");
        interp.load("programs/shootout/" ~ name ~ ".js");
    }

    run("hash", 10);
    interp.assertInt("c", 10);

    run("hash2", 1);

    // TODO: need apply
    //run("heapsort", 4);
    //interp.assertFloat("ary[n]", 0.79348136);

    // TODO: too slow for now
    //run(lists, 1);

    // TODO: need call_apply
    //run("mandelbrot", 10);

    run("matrix", 4);
    interp.assertInt("mm[0][0]", 270165);
    interp.assertInt("mm[4][4]", 1856025);

    // TODO: need call_apply
    //run("methcall", 10);

    run("nestedloop", 10);
    interp.assertInt("x", 1000000);

    // TODO: need call_apply
    //run("objinst", 10);

    // TODO: need call_apply
    //run("random", 10);
    //interp.assertInt("last", 75056);
}

/// SunSpider benchmarks
unittest
{
    writefln("sunspider");

    auto interp = new Interp();

    void run(string name)
    {
        writefln("sunspider/%s", name);
        interp.load("programs/sunspider/" ~ name ~ ".js");
    }

    run("3d-cube");
    run("3d-morph");
    // TODO: need get_time_ms
    //run("3d-raytrace");

    run("access-binary-trees");
    run("access-fannkuch");
    // TODO: need get_time_ms
    //run("access-nbody");
    run("access-nsieve");

    run("bitops-bitwise-and");
    run("bitops-bits-in-byte");
    run("bitops-3bit-bits-in-byte");
    run("bitops-nsieve-bits");

    run("controlflow-recursive");
    interp.assertInt("ack(3,2);", 29);
    interp.assertInt("tak(9,5,3);", 4);

    // FIXME: bug in regexp lib?
    //run("crypto-aes");
    //interp.assertInt("decryptedText.length;", 1311);
    //run("crypto-md5");
    //run("crypto-sha1");

    // TODO: need get_time_ms
    //run("math-cordic");
    run("math-partial-sums");
    run("math-spectral-norm");

    // TODO: enable once faster
    //run("string-base64");

    // TODO: enable once faster, now ~9s
    //run("string-fasta");
}

/// V8 benchmarks
unittest
{
    writefln("v8bench");

    auto interp = new Interp();
    interp.load("programs/v8bench/base.js");

    void run(string name)
    {
        writefln("v8bench/%s", name);
        interp.load("programs/v8bench/" ~ name ~ ".js");
        interp.load("programs/v8bench/drv-" ~ name ~ ".js");
    }

    //run("crypto");

    // TODO: need apply
    //run("deltablue");

    //run("earley-boyer");

    run("navier-stokes");

    // TODO: need apply
    //run("raytrace");

    run("richards");

    // TODO: enable once faster
    //run("splay");
}

