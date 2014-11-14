/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

module runtime.tests;

import std.stdio;
import std.string;
import std.math;
import std.conv;
import parser.parser;
import ir.ast;
import runtime.layout;
import runtime.vm;
import runtime.string;
import repl;

/**
VM which doesn't load the standard library
*/
class VMNoStdLib : VM
{
    this()
    {
        super(true, false);
    }
}

void assertInt(VM vm, string input, int32 intVal)
{
    //writeln(input);

    assert (
        vm !is null,
        "VM object is null"
    );

    auto ret = vm.evalString(input);

    assert (
        ret.tag == Tag.INT32,
        "non-integer value: " ~ ret.toString ~ "\n" ~
        "for input:\n" ~
        input
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

void assertFloat(VM vm, string input, double floatVal, double eps = 1E-4)
{
    auto ret = vm.evalString(input);

    assert (
        ret.tag == Tag.INT32 ||
        ret.tag == Tag.FLOAT64,
        "non-numeric value: " ~ ret.toString
    );

    auto fRet = (ret.tag == Tag.FLOAT64)? ret.word.floatVal:ret.word.int32Val;

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

void assertBool(VM vm, string input, bool boolVal)
{
    auto ret = vm.evalString(input);

    assert (
        ret.tag == Tag.CONST,
        "non-const value: " ~ ret.toString
    );

    assert (
        ret == (boolVal? TRUE:FALSE),
        format(
            "Test failed:\n" ~
            "%s" ~ "\n" ~
            "incorrect boolean value: %s, expected: %s",
            input,
            ret.toString,
            boolVal
        )
    );
}

void assertTrue(VM vm, string input)
{
    assertBool(vm, input, true);
}

void assertStr(VM vm, string input, string strVal)
{
    auto ret = vm.evalString(input);

    assert (
        ret.tag is Tag.STRING,
        "non-string value: " ~ ret.toString ~ "\n" ~
        "for eval string \"" ~ input ~ "\""
    );

    assert (
        extractStr(ret.word.ptrVal) == strVal,
        format(
            "Test failed:\n" ~
            input ~ "\n" ~
            "incorrect string value: %s, expected: %s",
            ret.toString,
            strVal
        )
    );
}

void assertThrows(VM vm, string input)
{
    try
    {
        vm.evalString(input);
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

unittest
{
    Word w0 = Word.int32v(0);
    Word w1 = Word.int32v(1);
    assert (w0.int32Val != w1.int32Val);
}

unittest
{
    writefln("JIT core");

    // Create an VM without a runtime or stdlib
    auto vm = new VM(false, false);

    // Do nothing
    vm.evalString("");

    // Constant integer 1
    auto v = vm.evalString("1");
    assert (v.word.int32Val == 1);
    assert (v.tag is Tag.INT32);

    // 32-bit integer add
    vm.assertInt("$ir_add_i32(1, 2)", 3);

    // Integer arithmetic
    vm.assertInt("return $ir_sub_i32(3, 1)", 2);
    vm.assertInt("return $ir_mul_i32(3, 2)", 6);

    // Comparison and conditional branching
    vm.assertInt("if ($ir_eq_i32(7, 7)) return 1; else return 0;", 1);
    vm.assertInt("if ($ir_eq_i32(3, 2)) false; return 3;", 3);
    vm.assertInt("if ($ir_is_int32(5)) return 1; else return 2;", 1);

    // Add with overflow test
    vm.assertInt("if ($ir_add_i32_ovf(3, 1)) return 3; else return -1;", 3);
}

/// Global expression tests
unittest
{
    writefln("global expressions");

    auto vm = new VMNoStdLib();

    vm.evalString("x = 7");
    vm.assertInt("x = 7; return x;", 7);

    writeln("unary ops");

    vm.assertInt("return 7", 7);
    vm.assertInt("return 1 + 2", 3);
    vm.assertInt("return 5 - 1", 4);
    vm.assertInt("return 8 % 5", 3);
    vm.assertInt("return 5 % 3", 2);
    vm.assertInt("return -3", -3);
    vm.assertInt("return +7", 7);

    writeln("binary arith ops");

    vm.assertInt("return 2 + 3 * 4", 14);
    vm.assertInt("return 1 - (2+3)", -4);
    vm.assertInt("return 6 - (3-3)", 6);
    vm.assertInt("return 3 - 3 - 3", -3);

    writeln("bitwise");

    vm.assertInt("return 5 | 3", 7);
    vm.assertInt("return 5 & 3", 1);
    vm.assertInt("return 5 ^ 3", 6);
    vm.assertInt("return 5 << 2", 20);
    vm.assertInt("return 7 >> 1", 3);
    vm.assertInt("return 7 >>> 1", 3);
    vm.assertInt("return ~2", -3);

    writeln("undef");

    vm.assertInt("return ~undefined", -1);
    vm.assertInt("return undefined | 1", 1);
    vm.assertInt("return undefined & 1", 0);
    vm.assertInt("return undefined ^ 1", 1);
    vm.assertInt("return 1 << undefined", 1);
    vm.assertInt("return 1 >> undefined", 1);

    writeln("fp");

    vm.assertFloat("return 3.5", 3.5);
    vm.assertFloat("return 2.5 + 2", 4.5);
    vm.assertFloat("return 2.5 + 2.5", 5);
    vm.assertFloat("return 2.5 - 1", 1.5);
    vm.assertFloat("return 2 * 1.5", 3);
    vm.assertFloat("return 6 / 2.5", 2.4);
    vm.assertFloat("return 0.5 % 0.2", 0.1);
    vm.assertFloat("return 6/2/2", 1.5);
    vm.assertFloat("return 6/2*2", 6);

    vm.assertInt("~1.6", -2);
    vm.assertInt("3.5 | 0", 3);
    vm.assertInt("-3.5 | 0", -3);
    vm.assertInt("1 << 1.5", 2);

    vm.assertFloat("return 100 * '5'", 500);
    vm.assertFloat("return 100 / '5'", 20);

    vm.assertBool("!true", false);
    vm.assertBool("!false", true);
    vm.assertBool("!0", true);
}

/// Global function calls
unittest
{
    writefln("global functions");

    auto vm = new VMNoStdLib();

    vm.assertInt("return function () { return 9; } ()", 9);
    vm.assertInt("return function () { return 2 * 3; } ()", 6);

    // Calling a non-function
    vm.assertThrows("null()");
    vm.assertThrows("undefined()");
}

/// Argument passing test
unittest
{
    writefln("argument passing");

    auto vm = new VMNoStdLib();

    vm.assertInt("return function (x) { return x; } (7)", 7);
    vm.assertInt("return function (x) { return x + 3; } (5)", 8);
    vm.assertInt("return function (x, y) { return x - y; } (5, 2)", 3);

    // Too many arguments
    vm.assertInt("return function () { return 7; } (5)", 7);
    vm.assertInt("return function (x) { return x + 1; } (5, 9)", 6);

    // Too few arguments
    vm.assertInt("return function (x) { return 9; } ()", 9);
    vm.assertInt("return function (x, y) { return x - 1; } (4)", 3);
    vm.assertInt("return function (x,y,z,w) { return 0; } (1,2,3)", 0);
    vm.assertBool("return function (x) { return x === undefined; } ()", true);
    vm.assertBool("return function (x,y) { return y === undefined; } ()", true);
}

/// Local variable assignment
unittest
{
    writefln("local variables");

    auto vm = new VMNoStdLib();

    vm.assertInt("return function () { var x = 4; return x; } ()", 4);
    vm.assertInt("return function () { var x = 0; return x++; } ()", 0);
    vm.assertInt("return function () { var x = 0; return ++x; } ()", 1);
    vm.assertInt("return function () { var x = 0; return x--; } ()", 0);
    vm.assertInt("return function () { var x = 0; return --x; } ()", -1);
    vm.assertInt("return function () { var x = 0; ++x; return ++x; } ()", 2);
    vm.assertInt("return function () { var x = 0; return x++ + 1; } ()", 1);
    vm.assertInt("return function () { var x = 1; return x = x++ % 2; } ()", 1);
    vm.assertBool("return function () { var x; return (x === undefined); } ()", true);
}

/// Comparison and branching
unittest
{
    writefln("comparison and branching");

    auto vm = new VMNoStdLib();

    vm.assertInt("if (true) return 1; else return 0;", 1);
    vm.assertInt("if (false) return 1; else return 0;", 0);
    vm.assertInt("if (3 < 7) return 1; else return 0;", 1);
    vm.assertInt("if (5 < 2) return 1; else return 0;", 0);
    vm.assertInt("if (1 < 1.5) return 1; else return 0;", 1);

    vm.assertBool("3 <= 5", true);
    vm.assertBool("5 <= 5", true);
    vm.assertBool("7 <= 5", false);
    vm.assertBool("7 > 5", true);
    vm.assertBool("true == false", false);
    vm.assertBool("true === true", true);
    vm.assertBool("true !== false", true);
    vm.assertBool("3 === 3.0", true);
    vm.assertBool("3 !== 3.5", true);

    vm.assertBool("return 1 < undefined", false);
    vm.assertBool("return 1 > undefined", false);
    vm.assertBool("return 0.5 == null", false);
    vm.assertBool("return 'Foo' != null", true);
    vm.assertBool("return null != null", false);
    vm.assertBool("return 'Foo' == null", false);
    vm.assertBool("return undefined == undefined", true);
    vm.assertBool("return undefined == null", true);
    vm.assertBool("o = {}; return o == o", true);
    vm.assertBool("oa = {}; ob = {}; return oa == ob", false);

    vm.assertInt("return true? 1:0", 1);
    vm.assertInt("return false? 1:0", 0);
    vm.assertInt("true? a=3:a=4", 3);
    vm.assertInt("true? 1:0||0", 1);
    vm.assertInt("true? 0:2,3", 3);

    vm.assertInt("return 0 || 2", 2);
    vm.assertInt("return 1 || 2", 1);
    vm.assertInt("1 || 2; return 3", 3);
    vm.assertInt("return 0 || 0 || 3", 3);
    vm.assertInt("return 0 || 2 || 3", 2);
    vm.assertInt("if (0 || 2) return 1; else return 0;", 1);
    vm.assertInt("if (1 || 2) return 1; else return 0;", 1);
    vm.assertInt("if (0 || 0) return 1; else return 0;", 0);

    vm.assertInt("return 0 && 2", 0);
    vm.assertInt("return 1 && 2", 2);
    vm.assertInt("return 1 && 2 && 3", 3);
    vm.assertInt("return 1 && 0 && 3", 0);
    vm.assertInt("if (0 && 2) return 1; else return 0;", 0);
    vm.assertInt("if (1 && 2) return 1; else return 0;", 1);
}

/// Recursion
unittest
{
    writefln("recursion");

    auto vm = new VMNoStdLib();

    vm.assertInt(
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

    vm.assertInt(
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

    // Recursive Fibonacci computation
    writeln("fib");
    vm.load("tests/core/fib/fib.js");
    vm.assertInt("fib(8);", 21);
}

/// Loops
unittest
{
    writefln("loops");

    auto vm = new VMNoStdLib();

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
        "
        return function ()
        {
            for (var i = 0; i < 10; ++i);
            return i;
        } ();
        ",
        10
    );

    vm.assertInt(
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

    vm.load("tests/core/nested_loops/nested_loops.js");
    vm.assertInt("foo(10);", 510);
}

/// Switch statement
unittest
{
    writefln("switch");

    auto vm = new VMNoStdLib();

    vm.assertInt(
        "
        switch (0)
        {
        }
        return 0;
        ",
        0
    );

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    auto vm = new VMNoStdLib();

    vm.assertStr("'foo'", "foo");
    vm.assertInt("'foo'? 1:0", 1);
    vm.assertInt("''? 1:0", 0);
    vm.assertStr("'foo' + 1", "foo1");
    vm.assertStr("'foo' + true", "footrue");
    vm.assertTrue("'foo' + 'bar' == 'foobar'");
    vm.assertTrue("'foo' === 'foo'");
    vm.assertTrue("'foo' === 'f' + 'oo'");
    vm.assertTrue("'foo' !== 'f' + 'o'");
    vm.assertTrue("'f' + 'oo' !== null");
    vm.assertTrue("'bar' == 'bar'");
    vm.assertTrue("'bar' != 'b'");
    vm.assertBool("'bar' != 'bar'", false);

    vm.assertStr(
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

    auto vm = new VMNoStdLib();

    vm.assertStr("typeof 'foo'", "string");
    vm.assertStr("typeof 1", "number");
    vm.assertStr("typeof true", "boolean");
    vm.assertStr("typeof false", "boolean");
    vm.assertStr("typeof null", "object");
    vm.assertStr("typeof ('f' + 'oo')", "string");
    vm.assertTrue("typeof 'foo' === 'string'");
    vm.assertStr("x = 3; return typeof x;", "number");
    vm.assertStr("x = 3; return typeof void x;", "undefined");
    vm.assertStr("delete x; return typeof x;", "undefined");
}

/// Global scope, global object
unittest
{
    writefln("global object");

    auto vm = new VMNoStdLib();

    writeln("exprs");

    vm.assertBool("var x; return !x", true);
    vm.assertInt("a = 1; return a;", 1);
    vm.assertInt("var a; a = 1; return a;", 1);
    vm.assertInt("var a = 1; return a;", 1);
    vm.assertInt("a = 1; b = 2; return a+b;", 3);
    vm.assertInt("var x=3,y=5; return x;", 3);

    vm.assertInt("return a = 1,2;", 2);
    vm.assertInt("a = 1,2; return a;", 1);
    vm.assertInt("a = (1,2); return a;", 2);

    writeln("calls");

    vm.assertInt("f = function() { return 7; }; return f();", 7);
    vm.assertInt("function f() { return 9; }; return f();", 9);
    vm.assertInt("(function () {}); return 0;", 0);
    vm.assertInt("a = 7; function f() { return this.a; }; return f();", 7);

    vm.assertInt(
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

    writeln("unresolved");

    // Unresolved global
    vm.assertThrows("foo5783");

    writeln("delete");

    // Accessing a property from Object.prototype
    vm.assertInt("delete x; ($ir_get_obj_proto()).x = 777; return x;", 777);

    writeln("many globals");

    // Many global variables
    vm = new VMNoStdLib();
    vm.load("tests/core/many_globals/many_globals.js");
    vm = new VMNoStdLib();
    vm.load("tests/core/many_globals/many_globals2.js");
    vm = new VMNoStdLib();
    vm.load("tests/core/many_globals/many_globals3.js");
}

/// In-place operators
unittest
{
    writefln("in-place operators");

    auto vm = new VMNoStdLib();

    vm.assertInt("a = 1; a += 2; return a;", 3);
    vm.assertInt("a = 1; a += 4; a -= 3; return a;", 2);
    vm.assertInt("a = 1; b = 3; a += b; return a;", 4);
    vm.assertInt("a = 1; b = 3; return a += b;", 4);
    vm.assertInt("a = 3; a -= 2; return a", 1);
    vm.assertInt("a = 5; a %= 3; return a", 2);
    vm.assertInt("function f() { var a = 0; a += 1; a += 1; return a; }; return f();", 2);
    vm.assertInt("function f() { var a = 0; a += 2; a *= 3; return a; }; return f();", 6);
}

/// Object literals, property access, method calls
unittest
{
    writefln("objects and properties");

    auto vm = new VMNoStdLib();

    writeln("obj basic");

    vm.assertInt("{}; return 1;", 1);
    vm.assertInt("{x: 7}; return 1;", 1);
    vm.assertInt("o = {}; o.x = 7; return 1;", 1);
    vm.assertInt("o = {}; o.x = 7; return o.x;", 7);
    vm.assertInt("o = {x: 9}; return o.x;", 9);
    vm.assertInt("o = {x: 9}; o.y = 1; return o.x + o.y;", 10);
    vm.assertInt("o = {x: 5}; o.x += 1; return o.x;", 6);
    vm.assertInt("o = {x: 5}; return o.y? 1:0;", 0);

    writeln("in operator");

    // In operator
    vm.assertBool("o = {x: 5}; return 'x' in o;", true);
    vm.assertBool("o = {x: 5}; return 'k' in o;", false);

    writeln("delete operator");

    // Delete operator
    vm.assertBool("o = {x: 5}; delete o.x; return 'x' in o;", false);
    vm.assertBool("o = {x: 5}; delete o.x; return !o.x;", true);
    vm.assertThrows("a = 5; delete a; a;");

    writeln("function objects");

    // Function object property
    vm.assertInt("function f() { return 1; }; f.x = 3; return f() + f.x;", 4);

    writeln("method call");

    // Method call
    vm.assertInt("o = {x:7, m:function() {return this.x;}}; return o.m();", 7);

    writeln("object extension");

    // Object extension and equality
    vm.assertBool("o = {x: 5}; ob = o; o.y = 3; o.z = 6; return (o === ob);", true);
}

/// New operator, prototype chain
unittest
{
    writefln("new operator");

    auto vm = new VMNoStdLib();

    vm.assertInt("function f() {}; o = new f(); return 0", 0);
    vm.assertInt("function f() {}; o = new f(); return (o? 1:0)", 1);
    vm.assertInt("function f() { g = this; }; o = new f(); return g? 1:0", 1);
    vm.assertInt("function f() { this.x = 3 }; o = new f(); return o.x", 3);
    vm.assertInt("function f() { return {y:7}; }; o = new f(); return o.y", 7);

    vm.assertBool("function f(x,y) { return y === undefined; }; return new f;", true);

    vm.assertInt("function f() {}; return f.prototype? 1:0", 1);
    vm.assertInt("function f() {}; f.prototype.x = 9; return f.prototype.x", 9);

    vm.assertBool(
        "
        function f() {}
        a = new f();
        a.x = 3;
        b = new f();
        return (b.x === undefined);
        ",
        true
    );

    vm.assertInt(
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

    vm.assertBool(
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

    vm.assertBool(
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

    vm.assertInt(
        "
        function f() {}
        f.prototype.x = 9;
        o = new f();
        return o.x;
        ",
        9
    );

    vm.assertInt(
        "
        function f() {}
        f.prototype.x = 9;
        f.prototype.y = 1;
        o = new f();
        return o.x;
        ",
        9
    );

    vm.assertInt(
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

    // New on non-function
    vm.assertThrows("new null()");
    vm.assertThrows("new undefined()");
}

/// Array literals, array operations
unittest
{
    writefln("arrays");

    auto vm = new VMNoStdLib();
 
    vm.assertInt("a = []; return 0", 0);
    vm.assertInt("a = [1]; return 0", 0);
    vm.assertInt("a = [1,2]; return 0", 0);
    vm.assertInt("a = [1,2]; return a[0]", 1);
    vm.assertInt("a = [1,2]; a[0] = 3; return a[0]", 3);
    vm.assertInt("a = [1,2]; a[3] = 4; return a[1]", 2);
    vm.assertInt("a = [1,2]; a[3] = 4; return a[3]", 4);
    vm.assertInt("a = [1,2]; return a[3]? 1:0;", 0);
    vm.assertInt("a = [1337]; return a['0'];", 1337);
    vm.assertInt("a = []; a['0'] = 55; return a[0];", 55);
}

/// Inline IR and JS extensions
unittest
{
    writefln("inline IR");

    auto vm = new VMNoStdLib();

    vm.assertStr("typeof $undef", "undefined");
    vm.assertStr("typeof $nullptr", "rawptr");
    vm.assertStr("typeof $argc", "number");

    vm.assertInt("return $ir_add_i32(5,3);", 8);
    vm.assertInt("return $ir_sub_i32(5,3);", 2);
    vm.assertInt("return $ir_mul_i32(5,3);", 15);
    vm.assertInt("return $ir_div_i32(5,3);", 1);
    vm.assertInt("return $ir_mod_i32(5,3);", 2);
    vm.assertInt("return $ir_eq_i32(3,3)? 1:0;", 1);
    vm.assertInt("return $ir_eq_i32(3,2)? 1:0;", 0);
    vm.assertInt("return $ir_ne_i32(3,5)? 1:0;", 1);
    vm.assertInt("return $ir_ne_i32(3,3)? 1:0;", 0);
    vm.assertInt("return $ir_lt_i32(3,5)? 1:0;", 1);
    vm.assertInt("return $ir_ge_i32(5,5)? 1:0;", 1);

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
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

    vm.assertInt(
        "
        var ptr = $ir_alloc_refptr(16);
        $ir_store_u8(ptr, 0, 77);
        return $ir_load_u8(ptr, 0);
        ",
        77
    );

    vm.assertInt(
        "
        var ptr = $ir_alloc_refptr(16);
        $ir_store_u8(ptr, 0, 0xFF);
        return $ir_load_i8(ptr, 0);
        ",
        -1
    );

    // Link and integer value
    vm.assertInt(
        "
        var link = $ir_make_link(0);
        $ir_set_link(link, 133);
        return $ir_get_link(link);
        ",
        133
    );

    // Link and string value
    vm.assertBool(
        "
        var link = $ir_make_link(0);
        $ir_set_link(link, 'abc');
        return ($ir_get_link(link) === 'abc');
        ",
        true
    );

    vm.assertInt(
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
}

/// Basic test programs
unittest
{
    writefln("basic");

    auto vm = new VMNoStdLib();

    // Basic suite
    vm.load("tests/core/basic_arith/basic_arith.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/basic_shift/basic_shift.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/basic_bitops/basic_bitops.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/basic_assign/basic_assign.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/basic_cmp/basic_cmp.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/basic_bool_eval/basic_bool_eval.js");
    vm.assertInt("test();", 0);
}

/// Runtime functions
unittest
{
    writefln("runtime");

    auto vm = new VMNoStdLib();

    vm.assertInt("$rt_toBool(0)? 1:0", 0);
    vm.assertInt("$rt_toBool(5)? 1:0", 1);
    vm.assertInt("$rt_toBool(true)? 1:0", 1);
    vm.assertInt("$rt_toBool(false)? 1:0", 0);
    vm.assertInt("$rt_toBool(null)? 1:0", 0);
    vm.assertInt("$rt_toBool('')? 1:0", 0);
    vm.assertInt("$rt_toBool('foo')? 1:0", 1);

    vm.assertStr("$rt_toString(5)", "5");
    vm.assertStr("$rt_toString('foo')", "foo");
    vm.assertStr("$rt_toString(null)", "null");
    vm.assertStr("$rt_toString({toString: function(){return 's';}})", "s");

    vm.assertInt("$rt_add(5, 3)", 8);
    vm.assertFloat("$rt_add(5, 3.5)", 8.5);
    vm.assertStr("$rt_add(5, 'bar')", "5bar");
    vm.assertBool("$rt_add('foo', 'bar') == 'foobar'", true);

    vm.assertInt("$rt_sub(5, 3)", 2);
    vm.assertFloat("$rt_sub(5, 3.5)", 1.5);

    vm.assertInt("$rt_mul(3, 5)", 15);
    vm.assertFloat("$rt_mul(5, 1.5)", 7.5);
    vm.assertFloat("$rt_mul(0xFFFF, 0xFFFF)", 4294836225);

    vm.assertFloat("$rt_div(15, 3)", 5);
    vm.assertFloat("$rt_div(15, 1.5)", 10);

    vm.assertBool("$rt_eq(3,3)", true);
    vm.assertBool("$rt_eq(3,5)", false);
    vm.assertBool("$rt_eq('foo','foo')", true);

    vm.assertBool("isNaN(3)", false);
    vm.assertBool("isNaN(3.5)", false);
    vm.assertBool("isNaN(NaN)", true);
    vm.assertBool("isNaN(0 / 0)", true);
    vm.assertBool("isNaN(0 % 0)", true);

    vm.assertStr("$rt_toString(NaN);", "NaN");

    vm.assertInt("$rt_getProp('foo', 'length')", 3);
    vm.assertStr("$rt_getProp('foo', 0)", "f");
    vm.assertInt("$rt_getProp([0,1], 'length')", 2);
    vm.assertInt("$rt_getProp([3,4,5], 1)", 4);
    vm.assertInt("$rt_getProp({v:7}, 'v')", 7);
    vm.assertInt("a = [0,0,0]; $rt_setProp(a,1,5); return $rt_getProp(a,1);", 5);
    vm.assertInt("a = [0,0,0]; $rt_setProp(a,9,7); return $rt_getProp(a,9);", 7);
    vm.assertInt("a = []; $rt_setProp(a,'length',5); return $rt_getProp(a,'length');", 5);

    vm.assertInt(
        "
        o = {};
        $rt_setProp(o,'a',1);
        $rt_setProp(o,'b',2);
        $rt_setProp(o,'c',3);
        return $rt_getProp(o,'c');
        ",
        3
    );

    vm.assertBool("'foo' in {}", false);
    vm.assertThrows("2 in null");
    vm.assertThrows("false instanceof false");
}

/// Closures, captured and escaping variables
unittest
{
    writefln("closures");

    auto vm = new VMNoStdLib();

    vm.assertInt(
        "
        function foo(x) { return function() { return x; } }
        f = foo(5);
        return f();
        ",
        5
    );

    vm.assertInt(
        "
        function foo(x) { var y = x + 1; return function() { return y; } }
        f = foo(5);
        return f();
        ",
        6
    );

    vm.assertInt(
        "
        function foo(x) { return function() { return x++; } }
        f = foo(5);
        f();
        return f();
        ",
        6
    );

    vm.assertInt(
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

    vm.load("tests/core/clos_capt/clos_capt.js");
    vm.assertInt("foo(5);", 8);
    vm.load("tests/core/clos_access/clos_access.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/clos_globals/clos_globals.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/clos_xcall/clos_xcall.js");
    vm.assertInt("test(5);", 5);
}

/// Stdlib Math library
unittest
{
    writefln("stdlib/math");

    auto vm = new VM();

    //import options;
    //opts.jit_trace_instrs = true;

    vm.assertInt("Math.max(1,2);", 2);
    vm.assertInt("Math.max(5,1,2);", 5);
    vm.assertInt("Math.min(5,-1,2);", -1);

    vm.assertFloat("Math.cos(0)", 1);
    vm.assertFloat("Math.cos(Math.PI)", -1);
    vm.assertInt("isNaN(Math.cos('f'))? 1:0", 1);

    vm.assertFloat("Math.sin(0)", 0);
    vm.assertFloat("Math.sin(Math.PI)", 0);

    vm.assertFloat("Math.sqrt(4)", 2);

    vm.assertInt("Math.pow(2, 0)", 1);
    vm.assertInt("Math.pow(2, 4)", 16);
    vm.assertInt("Math.pow(2, 8)", 256);

    vm.assertFloat("Math.log(Math.E)", 1);
    vm.assertFloat("Math.log(1)", 0);

    vm.assertFloat("Math.exp(0)", 1);

    vm.assertFloat("Math.ceil(1.5)", 2);
    vm.assertInt("Math.ceil(2)", 2);

    vm.assertFloat("Math.floor(1.5)", 1);
    vm.assertInt("Math.floor(2)", 2);

    vm.assertBool("r = Math.random(); return r >= 0 && r < 1;", true);
    vm.assertBool("r0 = Math.random(); r1 = Math.random(); return r0 !== r1;", true);

    //opts.jit_trace_instrs = false;
}

/// Stdlib Object library
unittest
{
    writefln("stdlib/object");

    auto vm = new VM();

    vm.assertBool("o = {k:3}; return o.hasOwnProperty('k');", true);
    vm.assertBool("o = {k:3}; p = Object.create(o); return p.hasOwnProperty('k')", false);
    vm.assertBool("o = {k:3}; p = Object.create(o); return 'k' in p;", true);
}

/// Stdlib Number library
unittest
{
    writefln("stdlib/number");

    auto vm = new VM();

    vm.assertInt("Number(10)", 10);
    vm.assertInt("Number(true)", 1);
    vm.assertInt("Number(null)", 0);

    vm.assertStr("(10).toString()", "10");
}

/// Stdlib Array library
unittest
{
    writefln("stdlib/array");

    auto vm = new VM();

    vm.assertInt("a = Array(10); return a.length;", 10);
    vm.assertInt("a = Array(1,2,3); return a.length;", 3);
    vm.assertTrue("[0,1,2].toString() == '0,1,2'");

    vm.assertInt("Array.prototype['0'] = 7; a = [3]; a['0'];", 3);
    vm.assertInt("a = [function () { return 9; }]; a[0]();", 9);
}

/// Stdlib String library
unittest
{
    writefln("stdlib/string");

    auto vm = new VM();

    vm.assertStr("String(10)", "10");
    vm.assertStr("String(1.5)", "1.5");
    vm.assertStr("String([0,1,2])", "0,1,2");

    vm.assertStr("'foobar'.substring(0,3)", "foo");
    vm.assertInt("'f,o,o'.split(',').length", 3);
}

/// Stdlib global functions
unittest
{
    writefln("stdlib/global");

    auto vm = new VM();

    vm.assertInt("parseInt(10)", 10);
    vm.assertInt("parseInt(-1)", -1);
    vm.assertBool("isNaN(parseInt('zux'))", true);
}

/// Exceptions
unittest
{
    writefln("exceptions (intra)");

    auto vm = new VM();

    // Intraprocedural tests
    vm.load("tests/core/exceptions/throw_intra.js");
    vm.assertTrue("str == 'abc'");
    vm.load("tests/core/exceptions/finally_ret.js");
    vm.assertTrue("test() == 'abcd'");
    vm.assertTrue("str == 'abcdef'");
    vm.load("tests/core/exceptions/finally_break.js");
    vm.assertTrue("test(); return str == 'abcdefg'");
    vm.load("tests/core/exceptions/finally_cont.js");
    vm.assertTrue("test(); return str == 'abcdefbcdefg'");
    vm.load("tests/core/exceptions/finally_throw.js");
    vm.assertTrue("test(); return str == 'abcdefghijk'");
    vm.load("tests/core/exceptions/throw_in_finally.js");
    vm.assertTrue("str == 'abcdef'");
    vm.load("tests/core/exceptions/throw_in_catch.js");
    vm.assertTrue("str == 'abcdefg'");

    writefln("exceptions (inter)");

    // Interprocedural tests
    vm.load("tests/core/exceptions/throw_inter.js");
    vm.assertInt("test();", 0);
    vm.load("tests/core/exceptions/throw_inter_fnl.js");
    vm.assertTrue("str == 'abcdef'");
    vm.load("tests/core/exceptions/try_call.js");
    vm.assertTrue("str == 'abc'");
    vm.load("tests/core/exceptions/try_loop_getprop.js");
    vm.assertTrue("str == 'abcd'");
}

/// Dynamic code loading and eval
unittest
{
    auto vm = new VM();

    writefln("load");

    // Dynamic code loading
    vm.load("tests/core/load/loader.js");

    // Loading a missing file
    vm.assertThrows("load('_filethatdoesntexist123_')");

    writefln("eval");

    // Eval
    vm.load("tests/core/eval/eval.js");

    // Eval throwing an exception
    vm.assertThrows("eval('throw 1')");
}

/// High-level features
unittest
{
    auto vm = new VM();

    // Call with apply
    writefln("apply");
    vm.load("tests/core/apply/apply.js");
    vm.assertInt("test();", 0);

    // Arguments object
    writefln("arguments");
    vm.load("tests/core/arg_obj/arg_obj.js");
    vm.assertInt("test();", 0);

    // For-in loop
    writeln("for-in");
    vm.load("tests/core/for_in/for_in.js");
    vm.assertInt("test();", 0);
}

/// Regression tests
unittest
{
    writefln("regression");

    VM vm;

    vm = new VM();

    vm.assertBool("4294967295.0 === 0xFFFFFFFF", true);

    vm.assertInt("return ~[]", -1);
    vm.assertInt("return ~{}", -1);
    vm.assertInt("+[]", 0);
    vm.assertStr("String(+{})", "NaN");

    vm.assertStr("typeof ([] + [])", "string");
    vm.assertStr("typeof ([] + {})", "string");
    vm.assertStr("typeof ({} + {})", "string");
    vm.assertStr("typeof ({} + [])", "string");

    vm.load("tests/core/regress/post_incr.js");
    vm.load("tests/core/regress/in_operator.js");
    vm.load("tests/core/regress/tostring.js");
    vm.load("tests/core/regress/new_array.js");
    vm.load("tests/core/regress/loop_cst_branch.js");
    vm.load("tests/core/regress/loop_labels.js");
    vm.load("tests/core/regress/loop_swap.js");
    vm.load("tests/core/regress/loop_lt.js");
    vm.load("tests/core/regress/loop_lessargs.js");
    vm.load("tests/core/regress/loop_new.js");
    vm.load("tests/core/regress/loop_argc.js");
    vm.load("tests/core/regress/loop_bool.js");
    vm.load("tests/core/regress/loop_decr_sum.js");
    vm.load("tests/core/regress/loop_decr_test.js");
    vm.load("tests/core/regress/dowhile_cont.js");
    vm.load("tests/core/regress/vers_pathos.js");

    vm.load("tests/core/regress/ir-string.js");
    vm.load("tests/core/regress/ir-inf-loop.js");
    vm.load("tests/core/regress/ir-dead-getprop.js");

    vm.load("tests/core/regress/jit_se_cmp.js");
    vm.load("tests/core/regress/jit_float_cmp.js");
    vm.load("tests/core/regress/jit_getprop_arr.js");
    vm.load("tests/core/regress/jit_call_exc.js");
    vm.load("tests/core/regress/jit_ctor.js");
    vm.load("tests/core/regress/jit_set_global.js");
    vm.load("tests/core/regress/jit_inlining.js");
    vm.load("tests/core/regress/jit_inlining2.js");
    vm.load("tests/core/regress/jit_spill_load.js");

    vm.load("tests/core/regress/delta.js");
    vm.load("tests/core/regress/raytrace.js");
    vm.load("tests/core/regress/boyer.js");
}

/// Garbage collector tests
unittest
{
    writefln("garbage collector");

    VM vm;

    vm = new VM();
    vm.assertInt("v = 3; $ir_gc_collect(0); return v;", 3);

    vm = new VM();
    vm.assertInt("
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
    vm = new VM();
    vm.load("tests/core/gc/collect.js");
    vm.assertInt("test();", 0);

    writefln("gc/objects");
    vm = new VM();
    vm.load("tests/core/gc/objects.js");

    writefln("gc/new");
    vm = new VM();
    vm.load("tests/core/gc/new.js");

    writefln("gc/arrays");
    vm = new VM();
    vm.load("tests/core/gc/arrays.js");

    writefln("gc/closures");
    vm = new VM();
    vm.load("tests/core/gc/closures.js");
    vm.assertInt("test();", 0);

    writefln("gc/objext");
    vm = new VM();
    vm.load("tests/core/gc/objext.js");

    writefln("gc/deepstack");
    vm = new VM();
    vm.load("tests/core/gc/deepstack.js");
    vm.assertInt("test();", 0);

    writefln("gc/bigloop");
    vm = new VM();
    vm.load("tests/core/gc/bigloop.js");

    writefln("gc/apply");
    vm = new VM();
    vm.load("tests/core/gc/apply.js");
    vm.assertInt("test();", 0);

    writefln("gc/extraargs");
    vm = new VM();
    vm.load("tests/core/gc/extraargs.js");

    writefln("gc/arguments");
    vm = new VM();
    vm.load("tests/core/gc/arguments.js");
    vm.assertInt("test();", 0);

    writefln("gc/strcat");
    vm = new VM();
    vm.load("tests/core/gc/strcat.js");
    vm.assertInt("test();", 0);

    writefln("gc/globalexc");
    vm = new VM();
    vm.load("tests/core/gc/globalexc.js");

    writefln("gc/for-in");
    vm = new VM();
    vm.load("tests/core/gc/for-in.js");

    writefln("gc/graph");
    vm = new VM();
    vm.load("tests/core/gc/graph.js");
    vm.assertInt("test();", 0);

    writefln("gc/stackvm");
    vm = new VM();
    vm.load("tests/core/gc/stackvm.js");
    vm.assertInt("test();", 0);

    writefln("gc/load");
    vm = new VM();
    vm.load("tests/core/gc/load.js");
    vm.assertInt("theFlag;", 1337);
}

