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

void assertFloat(VM vm, string input, double floatVal, double eps = 1E-4)
{
    auto ret = vm.evalString(input);

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

void assertBool(VM vm, string input, bool boolVal)
{
    auto ret = vm.evalString(input);

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

void assertStr(VM vm, string input, string strVal)
{
    auto ret = vm.evalString(input);

    assert (
        valIsString(ret),
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
    writefln("JIT core");

    // Create an VM without a runtime or stdlib
    auto vm = new VM(false, false);

    // Do nothing
    vm.evalString("");

    // Constant integer 1
    auto v = vm.evalString("1");
    assert (v.word.int32Val == 1);
    assert (v.type is Type.INT32);

    // 32-bit integer add
    vm.assertInt("$ir_add_i32(1, 2)", 3);

    // Global property access (needed by runtime lib)
    vm.evalString("x = 7");
    vm.assertInt("x = 7; return x;", 7);

    // Integer arithmetic
    vm.assertInt("x = 3; return $ir_add_i32(x, 2)", 5);
    vm.assertInt("x = 3; return $ir_sub_i32(x, 1)", 2);
    vm.assertInt("x = 3; return $ir_mul_i32(x, 2)", 6);

    // Comparison and conditional branching
    vm.assertInt("x = 7; if ($ir_eq_i32(x, 7)) return 1; else return 0;", 1);
    vm.assertInt("x = 3; if ($ir_eq_i32(x, 2)) x = 1; return x;", 3);
    vm.assertInt("x = 5; if ($ir_is_i32(x)) x = 1; else x = 0; return x;", 1);

    // Add with overflow test
    vm.assertInt("x = 3; if ($ir_add_i32_ovf(x, 1)) return x; else return -1;", 3);
}

/// Global expression tests
unittest
{
    writefln("global expressions");

    auto vm = new VMNoStdLib();

    vm.assertInt("return 7", 7);
    vm.assertInt("return 1 + 2", 3);
    vm.assertInt("return 5 - 1", 4);
    vm.assertInt("return 8 % 5", 3);
    vm.assertInt("return 5 % 3", 2);
    vm.assertInt("return -3", -3);
    vm.assertInt("return +7", 7);

    vm.assertInt("return 2 + 3 * 4", 14);
    vm.assertInt("return 1 - (2+3)", -4);
    vm.assertInt("return 6 - (3-3)", 6);
    vm.assertInt("return 3 - 3 - 3", -3);

    vm.assertInt("return 5 | 3", 7);
    vm.assertInt("return 5 & 3", 1);
    vm.assertInt("return 5 ^ 3", 6);
    vm.assertInt("return 5 << 2", 20);
    vm.assertInt("return 7 >> 1", 3);
    vm.assertInt("return 7 >>> 1", 3);
    vm.assertInt("return ~2", -3);
    vm.assertInt("return ~undefined", -1);
    vm.assertInt("return undefined | 1", 1);
    vm.assertInt("return undefined & 1", 0);
    vm.assertInt("return undefined ^ 1", 1);
    vm.assertInt("return 1 << undefined", 1);
    vm.assertInt("return 1 >> undefined", 1);

    vm.assertFloat("return 3.5", 3.5);
    vm.assertFloat("return 2.5 + 2", 4.5);
    vm.assertFloat("return 2.5 + 2.5", 5);
    vm.assertFloat("return 2.5 - 1", 1.5);
    vm.assertFloat("return 2 * 1.5", 3);
    vm.assertFloat("return 6 / 2.5", 2.4);
    vm.assertFloat("return 0.5 % 0.2", 0.1);
    vm.assertFloat("return 6/2/2", 1.5);
    vm.assertFloat("return 6/2*2", 6);

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

    vm.assertStr("return 'foo'", "foo");
    vm.assertStr("return 'foo' + 'bar'", "foobar");
    vm.assertStr("return 'foo' + 1", "foo1");
    vm.assertStr("return 'foo' + true", "footrue");
    vm.assertInt("return 'foo'? 1:0", 1);
    vm.assertInt("return ''? 1:0", 0);
    vm.assertBool("return ('foo' === 'foo')", true);
    vm.assertBool("return ('foo' === 'f' + 'oo')", true);
    vm.assertBool("return ('bar' == 'bar')", true);
    vm.assertBool("return ('bar' != 'b')", true);
    vm.assertBool("return ('bar' != 'bar')", false);

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

    vm.assertStr("return typeof 'foo'", "string");
    vm.assertStr("return typeof 1", "number");
    vm.assertStr("return typeof true", "boolean");
    vm.assertStr("return typeof false", "boolean");
    vm.assertStr("return typeof null", "object");
    vm.assertInt("return (typeof 'foo' === 'string')? 1:0", 1);
    vm.assertStr("x = 3; return typeof x;", "number");
    vm.assertStr("delete x; return typeof x;", "undefined");
}

/// Global scope, global object
unittest
{
    writefln("global object");

    auto vm = new VMNoStdLib();

    vm.assertBool("var x; return !x", true);
    vm.assertInt("a = 1; return a;", 1);
    vm.assertInt("var a; a = 1; return a;", 1);
    vm.assertInt("var a = 1; return a;", 1);
    vm.assertInt("a = 1; b = 2; return a+b;", 3);
    vm.assertInt("var x=3,y=5; return x;", 3);

    vm.assertInt("return a = 1,2;", 2);
    vm.assertInt("a = 1,2; return a;", 1);
    vm.assertInt("a = (1,2); return a;", 2);

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

    // Unresolved global
    vm.assertThrows("foo5783");

    // Accessing a property from Object.prototype
    vm.assertInt("delete x; ($ir_get_obj_proto()).x = 777; return x;", 777);

    // Many global variables
    vm = new VMNoStdLib();
    vm.load("tests/many_globals/many_globals.js");
    vm = new VMNoStdLib();
    vm.load("tests/many_globals/many_globals2.js");
    vm = new VMNoStdLib();
    vm.load("tests/many_globals/many_globals3.js");
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

    vm.assertInt("{}; return 1;", 1);
    vm.assertInt("{x: 7}; return 1;", 1);
    vm.assertInt("o = {}; o.x = 7; return 1;", 1);
    vm.assertInt("o = {}; o.x = 7; return o.x;", 7);
    vm.assertInt("o = {x: 9}; return o.x;", 9);
    vm.assertInt("o = {x: 9}; o.y = 1; return o.x + o.y;", 10);
    vm.assertInt("o = {x: 5}; o.x += 1; return o.x;", 6);
    vm.assertInt("o = {x: 5}; return o.y? 1:0;", 0);

    // In operator
    vm.assertBool("o = {x: 5}; return 'x' in o;", true);
    vm.assertBool("o = {x: 5}; return 'k' in o;", false);

    // Delete operator
    vm.assertBool("o = {x: 5}; delete o.x; return 'x' in o;", false);
    vm.assertBool("o = {x: 5}; delete o.x; return !o.x;", true);
    vm.assertThrows("a = 5; delete a; a;");

    // Function object property
    vm.assertInt("function f() { return 1; }; f.x = 3; return f() + f.x;", 4);

    // Method call
    vm.assertInt("o = {x:7, m:function() {return this.x;}}; return o.m();", 7);

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
        var ptr = $ir_heap_alloc(16);
        $ir_store_u8(ptr, 0, 77);
        return $ir_load_u8(ptr, 0);
        ",
        77
    );

    vm.assertInt(
        "
        var link = $ir_make_link(0);
        $ir_set_link(link, 133);
        return $ir_get_link(link);
        ",
        133
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
    vm.assertStr("$rt_add('foo', 'bar')", "foobar");

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

    vm.assertInt("isNaN(3)? 1:0", 0);
    vm.assertInt("isNaN(3.5)? 1:0", 0);
    vm.assertInt("isNaN(NaN)? 1:0", 1);
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
}

/// Stdlib Math library
unittest
{
    writefln("stdlib/math");

    auto vm = new VM();

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
    vm.assertStr("([0,1,2]).toString()", "0,1,2");
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
    writefln("exceptions");

    auto vm = new VM();

    // Intraprocedural tests
    vm.load("tests/exceptions/throw_intra.js");
    vm.assertStr("str;", "abc");
    vm.load("tests/exceptions/finally_ret.js");
    vm.assertStr("test();", "abcd");
    vm.assertStr("str;", "abcdef");
    vm.load("tests/exceptions/finally_break.js");
    vm.assertStr("test(); return str;", "abcdefg");
    vm.load("tests/exceptions/finally_cont.js");
    vm.assertStr("test(); return str;", "abcdefbcdefg");
    vm.load("tests/exceptions/finally_throw.js");
    vm.assertStr("test(); return str;", "abcdefghijk");
    vm.load("tests/exceptions/throw_in_finally.js");
    vm.assertStr("str;", "abcdef");
    vm.load("tests/exceptions/throw_in_catch.js");
    vm.assertStr("str;", "abcdefg");

    // Interprocedural tests
    vm.load("tests/exceptions/throw_inter.js");
    vm.assertInt("test();", 0);
    vm.load("tests/exceptions/throw_inter_fnl.js");
    vm.assertStr("str;", "abcdef");
    vm.load("tests/exceptions/try_call.js");
    vm.assertStr("str;", "abc");
}

/// Basic test programs
unittest
{
    writefln("basic");

    auto vm = new VM();

    // Basic suite
    vm.load("tests/basic_arith/basic_arith.js");
    vm.assertInt("test();", 0);
    vm.load("tests/basic_shift/basic_shift.js");
    vm.assertInt("test();", 0);
    vm.load("tests/basic_bitops/basic_bitops.js");
    vm.assertInt("test();", 0);
    vm.load("tests/basic_assign/basic_assign.js");
    vm.assertInt("test();", 0);
    vm.load("tests/basic_cmp/basic_cmp.js");
    vm.assertInt("test();", 0);
    vm.load("tests/basic_bool_eval/basic_bool_eval.js");
    vm.assertInt("test();", 0);
}

/// Regression tests
unittest
{
    writefln("regression");

    VM vm;

    vm = new VM();

    vm.assertBool("4294967295.0 === 0xFFFFFFFF", true);

    vm.assertStr("typeof ([] + [])", "string");

    vm.load("tests/regress/post_incr.js");
    vm.load("tests/regress/in_operator.js");
    vm.load("tests/regress/tostring.js");
    vm.load("tests/regress/new_array.js");
    vm.load("tests/regress/loop_labels.js");
    vm.load("tests/regress/loop_swap.js");
    vm.load("tests/regress/loop_lt.js");
    vm.load("tests/regress/loop_lessargs.js");
    vm.load("tests/regress/loop_new.js");
    vm.load("tests/regress/loop_argc.js");
    vm.load("tests/regress/loop_bool.js");
    vm.load("tests/regress/loop_decr_sum.js");
    vm.load("tests/regress/dowhile_cont.js");
    vm.load("tests/regress/vers_pathos.js");

    vm.load("tests/regress/jit_se_cmp.js");
    vm.load("tests/regress/jit_float_cmp.js");
    vm.load("tests/regress/jit_getprop_arr.js");
    vm.load("tests/regress/jit_call_exc.js");
    vm.load("tests/regress/jit_ctor.js");
    vm.load("tests/regress/jit_set_global.js");
    vm.load("tests/regress/jit_inlining.js");
    vm.load("tests/regress/jit_inlining2.js");

    vm.load("tests/regress/delta.js");
    vm.load("tests/regress/raytrace.js");

    vm = new VM();
    vm.load("tests/regress/boyer.js");
}

/// Tachyon tests
unittest
{
    writefln("tachyon");

    auto vm = new VM();

    // ES5 comparison operator test
    writeln("es5 comparisons");
    vm.load("tests/es5_cmp/es5_cmp.js");
    vm.assertInt("test();", 0);

    // Recursive Fibonacci computation
    writeln("fib");
    vm.load("tests/fib/fib.js");
    vm.assertInt("fib(8);", 21);

    writeln("nested loops");
    vm.load("tests/nested_loops/nested_loops.js");
    vm.assertInt("foo(10);", 510);

    writeln("bubble sort");
    vm.load("tests/bubble_sort/bubble_sort.js");
    vm.assertInt("test();", 0);

    // N-queens solver
    writeln("n-queens");
    vm.load("tests/nqueens/nqueens.js");
    vm.assertInt("test();", 0);

    writeln("merge sort");
    vm.load("tests/merge_sort/merge_sort.js");
    vm.assertInt("test();", 0);

    writeln("matrix comp");
    vm.load("tests/matrix_comp/matrix_comp.js");
    vm.assertInt("test();", 10);

    writefln("closures");

    // Closures
    vm.load("tests/clos_capt/clos_capt.js");
    vm.assertInt("foo(5);", 8);
    vm.load("tests/clos_access/clos_access.js");
    vm.assertInt("test();", 0);
    vm.load("tests/clos_globals/clos_globals.js");
    vm.assertInt("test();", 0);
    vm.load("tests/clos_xcall/clos_xcall.js");
    vm.assertInt("test(5);", 5);

    writefln("apply");

    // Call with apply
    vm.load("tests/apply/apply.js");
    vm.assertInt("test();", 0);

    writefln("arguments");

    // Arguments object
    vm.load("tests/arg_obj/arg_obj.js");
    vm.assertInt("test();", 0);

    writefln("for-in");

    // For-in loop
    vm.load("tests/for_in/for_in.js");
    vm.assertInt("test();", 0);

    writefln("stdlib");

    // Standard library
    vm.load("tests/stdlib_math/stdlib_math.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_boolean/stdlib_boolean.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_number/stdlib_number.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_function/stdlib_function.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_object/stdlib_object.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_array/stdlib_array.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_string/stdlib_string.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_json/stdlib_json.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_regexp/stdlib_regexp.js");
    vm.assertInt("test();", 0);
    vm.load("tests/stdlib_map/stdlib_map.js");
    vm.assertInt("test();", 0);
}

/// Dynamic code loading and eval
unittest
{
    auto vm = new VM();

    writefln("load");

    // Dynamic code loading
    vm.load("tests/load/loader.js");

    // Loading a missing file
    vm.assertThrows("load('_filethatdoesntexist123_')");

    // Eval
    vm.load("tests/eval/eval.js");

    // Eval throwing an exception
    vm.assertThrows("eval('throw 1')");
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
    vm.load("tests/gc/collect.js");
    vm.assertInt("test();", 0);

    writefln("gc/objects");

    vm = new VM();
    vm.load("tests/gc/objects.js");

    writefln("gc/arrays");

    vm = new VM();
    vm.load("tests/gc/arrays.js");

    writefln("gc/closures");

    vm = new VM();
    vm.load("tests/gc/closures.js");
    vm.assertInt("test();", 0);

    writefln("gc/objext");

    vm = new VM();
    vm.load("tests/gc/objext.js");

    writefln("gc/deepstack");
  
    vm = new VM();
    vm.load("tests/gc/deepstack.js");
    vm.assertInt("test();", 0);

    writefln("gc/bigloop");

    vm = new VM();
    vm.load("tests/gc/bigloop.js");

    writefln("gc/apply");

    vm = new VM();
    vm.load("tests/gc/apply.js");
    vm.assertInt("test();", 0);

    writefln("gc/arguments");

    vm = new VM();
    vm.load("tests/gc/arguments.js");
    vm.assertInt("test();", 0);

    writefln("gc/strcat");

    vm = new VM();
    vm.load("tests/gc/strcat.js");
    vm.assertInt("test();", 0);

    writefln("gc/graph");

    vm = new VM();
    vm.load("tests/gc/graph.js");
    vm.assertInt("test();", 0);

    writefln("gc/stackvm");

    vm = new VM();
    vm.load("tests/gc/stackvm.js");
    vm.assertInt("test();", 0);

    writefln("gc/load");

    vm = new VM();
    vm.load("tests/gc/load.js");
    vm.assertInt("theFlag;", 1337);
}

// Dummy functions used for FFI tests
extern (C) 
{
    void testVoidFun()
    {
        return;
    }

    int testIntFun()
    {
        return 5;
    }

    double testDoubleFun()
    {
        return 5.5;
    }

    int testIntAddFun(int a, int b)
    {
        return a + b;
    }

    double testDoubleAddFun(double a, double b)
    {
        return a + b;
    }

    int testIntArgsFun(int a, int b, int c, int d, int e, int f, int g)
    {
        return a + b + c + d + e + (f - g);
    }

    double testDoubleArgsFun(double a, double b, double c, double d, double e, double f, double g)
    {
        return a + b + c + d + e + (f - g);
    }

    void* testPtrFun()
    {
        return &testIntAddFun;
    }

    double testMixedArgsFun(int a, double b, int c, double d, int e, double f, int g)
    {
        return cast(double)(a + b + c + d + e + (f - g));
    }
}

unittest
{
    writefln("FFI");

    auto vm = new VM();
    vm.load("tests/ffi/ffi.js");
}

/// Misc benchmarks
unittest
{
    auto vm = new VM();

    writefln("misc/bones");
    vm.load("benchmarks/bones/bones.js");

    writefln("misc/chess");
    vm.load("benchmarks/chess/toledo_chess.js");
}

/// Computer Language Shootout benchmarks
unittest
{
    writefln("shootout");

    auto vm = new VM();

    // Silence the print function
    vm.evalString("print = function (s) {}");

    void run(string name, size_t n)
    {
        writefln("shootout/%s", name);
        vm.evalString("arguments = [" ~ to!string(n) ~ "];");
        vm.load("benchmarks/shootout/" ~ name ~ ".js");
    }

    run("hash", 10);
    vm.assertInt("c", 10);

    run("hash2", 1);

    run("heapsort", 4);
    vm.assertFloat("ary[n]", 0.79348136);

    // TODO: too slow for now
    //run(lists, 1);

    run("mandelbrot", 10);

    run("matrix", 4);
    vm.assertInt("mm[0][0]", 270165);
    vm.assertInt("mm[4][4]", 1856025);

    run("methcall", 10);

    run("nestedloop", 10);
    vm.assertInt("x", 1000000);

    run("objinst", 10);

    run("random", 10);
    vm.assertInt("last", 75056);
}

/// SunSpider benchmarks
unittest
{
    writefln("sunspider");

    auto vm = new VM();

    void run(string name)
    {
        writefln("sunspider/%s", name);
        vm.load("benchmarks/sunspider/" ~ name ~ ".js");
    }

    run("3d-cube");
    run("3d-morph");
    run("3d-raytrace");

    run("access-binary-trees");
    run("access-fannkuch");
    run("access-nbody");
    run("access-nsieve");

    run("bitops-bitwise-and");
    run("bitops-bits-in-byte");
    run("bitops-3bit-bits-in-byte");
    run("bitops-nsieve-bits");

    run("controlflow-recursive");
    vm.assertInt("ack(3,2);", 29);
    vm.assertInt("tak(9,5,3);", 4);

    // FIXME: bug in regexp lib?
    //run("crypto-aes");
    //vm.assertInt("decryptedText.length;", 1311);
    run("crypto-md5");
    run("crypto-sha1");

    run("math-cordic");
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

    auto vm = new VM();
    vm.load("benchmarks/v8bench/base.js");

    void run(string name)
    {
        writefln("v8bench/%s", name);
        vm.load("benchmarks/v8bench/" ~ name ~ ".js");
        vm.load("benchmarks/v8bench/drv-" ~ name ~ ".js");
    }

    run("crypto");

    run("deltablue");

    run("earley-boyer");

    run("navier-stokes");

    run("raytrace");

    run("richards");

    // TODO: enable once faster
    //run("splay");
}

