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
import parser.parser;
import ir.ast;
import interp.layout;
import interp.interp;
import repl;

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
        ret.type == Type.FLOAT,
        "non-numeric value: " ~ valToString(ret)
    );

    auto fRet = (ret.type == Type.FLOAT)? ret.word.floatVal:ret.word.int32Val;

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
            "incorrect boolan value: %s, expected: %s",
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

void assertInt(string input, int32 intVal)
{
    assertInt(new Interp(), input, intVal);
}

void assertFloat(string input, double floatVal, double eps = 1E-4)
{
    assertFloat(new Interp(), input, floatVal, eps);
}

void assertBool(string input, bool boolVal)
{
    assertBool(new Interp(), input, boolVal);
}

void assertStr(string input, string strVal)
{
    assertStr(new Interp(), input, strVal);
}

void assertThrows(string input)
{
    assertThrows(new Interp(), input);
}

unittest
{
    Word w0 = Word.int32v(0);
    Word w1 = Word.int32v(1);
    assert (w0.int32Val != w1.int32Val);
}

unittest
{
    auto v = (new Interp()).evalString("1");
    assert (v.word.int32Val == 1);
}

/// Global expression tests
unittest
{
    assertInt("return 7", 7);
    assertInt("return 1 + 2", 3);
    assertInt("return 5 - 1", 4);
    assertInt("return 8 % 5", 3);
    assertInt("return -3", -3);
    assertInt("return +7", 7);
    assertInt("return 2 + 3 * 4", 14);
    assertInt("return 5 % 3", 2);
    assertInt("return 1 - (2+3)", -4);
    assertInt("return 6 - (3-3)", 6);
    assertInt("return 3 - 3 - 3", -3);

    assertInt("return 5 | 3", 7);
    assertInt("return 5 & 3", 1);
    assertInt("return 5 ^ 3", 6);
    assertInt("return 5 << 2", 20);
    assertInt("return 7 >> 1", 3);
    assertInt("return 7 >>> 1", 3);
    assertInt("return ~2", -3);
    assertInt("return undefined | 1", 1);

    assertFloat("return 3.5", 3.5);
    assertFloat("return 2.5 + 2", 4.5);
    assertFloat("return 2.5 + 2.5", 5);
    assertFloat("return 2.5 - 1", 1.5);
    assertFloat("return 2 * 1.5", 3);
    assertFloat("return 6 / 2.5", 2.4);
    assertFloat("return 6/2/2", 1.5);
    assertFloat("return 6/2*2", 6);
}

/// Global function calls
unittest
{
    assertInt("return function () { return 9; } ()", 9);
    assertInt("return function () { return 2 * 3; } ()", 6);

    // Calling null as a function
    assertThrows("null()");
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
    assertInt("return function () { var x = 0; ++x; return ++x; } ()", 2);
    assertInt("return function () { var x = 0; return x++ + 1; } ()", 1);
    assertInt("return function () { var x = 1; return x = x++ % 2; } ()", 1);
    assertBool("return function () { var x; return (x === undefined); } ()", true);
}

/// Comparison and branching
unittest
{
    assertInt("if (true) return 1; else return 0;", 1);
    assertInt("if (false) return 1; else return 0;", 0);
    assertInt("if (3 < 7) return 1; else return 0;", 1);
    assertInt("if (5 < 2) return 1; else return 0;", 0);
    assertInt("if (1 < 1.5) return 1; else return 0;", 1);
    assertBool("3 <= 5", true);
    assertBool("5 <= 5", true);
    assertBool("7 <= 5", false);
    assertBool("7 > 5", true);
    assertBool("true == false", false);
    assertBool("true === true", true);
    assertBool("true !== false", true);
    assertBool("3 === 3.0", true);
    assertBool("3 !== 3.5", true);

    assertBool("return 1 < undefined", false);
    assertBool("return 1 > undefined", false);
    assertBool("return 0.5 == null", false);
    assertBool("return 'Foo' != null", true);
    assertBool("return null != null", false);
    assertBool("return 'Foo' == null", false);
    assertBool("return undefined == undefined", true);
    assertBool("return undefined == null", true);
    assertBool("o = {}; return o == o", true);
    assertBool("oa = {}; ob = {}; return oa == ob", false);

    assertInt("return true? 1:0", 1);
    assertInt("return false? 1:0", 0);

    assertInt("return 0 || 2", 2);
    assertInt("return 1 || 2", 1);
    assertInt("1 || 2; return 3", 3);
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

                sum = sum + i;
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

/// Switch statement
unittest
{
    assertInt(
        "
        switch (0)
        {
        }
        return 0;
        ",
        0
    );

    assertInt(
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

    assertInt(
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

    assertInt(
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

    assertInt(
        "
        var v;
        switch (3)
        {
            case 0: v = 5;
            case 1: v += 1; break;
            case 2: v = 7; beak;
            default: v = 9;
        }
        return v;
        ",
        9
    );

    assertInt(
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
    assertBool("return ('foo' === 'foo')", true);
    assertBool("return ('foo' === 'f' + 'oo')", true);
    assertBool("return ('bar' == 'bar')", true);
    assertBool("return ('bar' != 'b')", true);
    assertBool("return ('bar' != 'bar')", false);
    assertBool("!true", false);
    assertBool("!false", true);
    assertBool("!0", true);

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

// Typeof operator
unittest
{
    assertStr("return typeof 'foo'", "string");
    assertStr("return typeof 1", "number");
    assertStr("return typeof true", "boolean");
    assertStr("return typeof false", "boolean");
    assertStr("return typeof null", "object");
    assertInt("return (typeof 'foo' === 'string')? 1:0", 1);
    assertStr("x = 3; return typeof x;", "number");
    assertStr("delete x; return typeof x;", "undefined");
}

/// Global scope, global object
unittest
{
    assertBool("var x; return !x", true);
    assertInt("a = 1; return a;", 1);
    assertInt("var a; a = 1; return a;", 1);
    assertInt("var a = 1; return a;", 1);
    assertInt("a = 1; b = 2; return a+b;", 3);
    assertInt("var x=3,y=5; return x;", 3);

    assertInt("return a = 1,2;", 2);
    assertInt("a = 1,2; return a;", 1);
    assertInt("a = (1,2); return a;", 2);

    assertInt("f = function() { return 7; }; return f();", 7);
    assertInt("function f() { return 9; }; return f();", 9);
    assertInt("(function () {}); return 0;", 0);
    assertInt("a = 7; function f() { return this.a; }; return f();", 7);

    assertInt(
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
    assertThrows("foo");
}

/// In-place operators
unittest
{
    assertInt("a = 1; a += 2; return a;", 3);
    assertInt("a = 1; a += 4; a -= 3; return a;", 2);
    assertInt("a = 1; b = 3; a += b; return a;", 4);
    assertInt("a = 1; b = 3; return a += b;", 4);
    assertInt("a = 3; a -= 2; return a", 1);
    assertInt("a = 5; a %= 3; return a", 2);
    assertInt("function f() { var a = 0; a += 1; a += 1; return a; }; return f();", 2);
    assertInt("function f() { var a = 0; a += 2; a *= 3; return a; }; return f();", 6);
}

/// Object literals, property access, method calls
unittest
{
    assertInt("{}; return 1;", 1);
    assertInt("{x: 7}; return 1;", 1);
    assertInt("o = {}; o.x = 7; return 1;", 1);
    assertInt("o = {}; o.x = 7; return o.x;", 7);
    assertInt("o = {x: 9}; return o.x;", 9);
    assertInt("o = {x: 9}; o.y = 1; return o.x + o.y;", 10);
    assertInt("o = {x: 5}; o.x += 1; return o.x;", 6);
    assertInt("o = {x: 5}; return o.y? 1:0;", 0);

    assertBool("o = {x: 5}; return 'x' in o;", true);
    assertBool("o = {x: 5}; return 'k' in o;", false);

    // Delete operator
    assertBool("o = {x: 5}; delete o.x; return 'x' in o;", false);
    assertBool("o = {x: 5}; delete o.x; return !o.x;", true);
    assertThrows("a = 5; delete a; a;");

    // Function object property
    assertInt("function f() { return 1; }; f.x = 3; return f() + f.x;", 4);

    // Method call
    assertInt("o = {x:7, m:function() {return this.x;}}; return o.m();", 7);
}

/// New operator, prototype chain
unittest
{
    assertInt("function f() {}; o = new f(); return 0", 0);
    assertInt("function f() {}; o = new f(); return o? 1:0", 1);
    assertInt("function f() { g = this; }; o = new f(); return g? 1:0", 1);
    assertInt("function f() { this.x = 3 }; o = new f(); return o.x", 3);
    assertInt("function f() { return {y:7}; }; o = new f(); return o.y", 7);

    assertInt("function f() {}; return f.prototype? 1:0", 1);
    assertInt("function f() {}; f.prototype.x = 9; return f.prototype.x", 9);

    assertBool(
        "
        function f() {}
        a = new f();
        a.x = 3;
        b = new f();
        return (b.x === undefined);
        ",
        true
    );

    assertInt(
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

    assertBool(
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

    assertInt(
        "
        function f() {}
        f.prototype.x = 9;
        o = new f();
        return o.x;
        ",
        9
    );

    assertInt(
        "
        function f() {}
        f.prototype.x = 9;
        f.prototype.y = 1;
        o = new f();
        return o.x;
        ",
        9
    );

    assertInt(
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
    assertInt("a = []; return 0", 0);
    assertInt("a = [1]; return 0", 0);
    assertInt("a = [1,2]; return 0", 0);
    assertInt("a = [1,2]; return a[0]", 1);
    assertInt("a = [1,2]; a[0] = 3; return a[0]", 3);
    assertInt("a = [1,2]; a[3] = 4; return a[1]", 2);
    assertInt("a = [1,2]; a[3] = 4; return a[3]", 4);
    assertInt("a = [1,2]; return a[3]? 1:0;", 0);
    assertInt("a = [1337]; return a['0'];", 1337);
    assertInt("a = []; a['0'] = 55; return a[0];", 55);
}

/// Inline IR
unittest
{
    assertInt("return $ir_add_i32(5,3);", 8);
    assertInt("return $ir_sub_i32(5,3);", 2);
    assertInt("return $ir_mul_i32(5,3);", 15);
    assertInt("return $ir_div_i32(5,3);", 1);
    assertInt("return $ir_mod_i32(5,3);", 2);
    assertInt("return $ir_eq_i32(3,3)? 1:0;", 1);
    assertInt("return $ir_eq_i32(3,2)? 1:0;", 0);
    assertInt("return $ir_ne_i32(3,5)? 1:0;", 1);
    assertInt("return $ir_ne_i32(3,3)? 1:0;", 0);
    assertInt("return $ir_lt_i32(3,5)? 1:0;", 1);
    assertInt("return $ir_ge_i32(5,5)? 1:0;", 1);

    assertInt(
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

    assertInt(
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

    assertInt(
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

    assertInt(
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

    assertInt(
        "
        var ptr = $ir_heap_alloc(16);
        $ir_store_u8(ptr, 0, 77);
        return $ir_load_u8(ptr, 0);
        ",
        77
    );

    assertInt(
        "
        var link = $ir_make_link(0);
        $ir_set_link(link, 133);
        return $ir_get_link(link);
        ",
        133
    );

    assertInt(
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

    assertInt("$rt_toBool(0)? 1:0", 0);
    assertInt("$rt_toBool(5)? 1:0", 1);
    assertInt("$rt_toBool(true)? 1:0", 1);
    assertInt("$rt_toBool(false)? 1:0", 0);
    assertInt("$rt_toBool(null)? 1:0", 0);
    assertInt("$rt_toBool('')? 1:0", 0);
    assertInt("$rt_toBool('foo')? 1:0", 1);

    assertStr("$rt_toString(5)", "5");
    assertStr("$rt_toString('foo')", "foo");
    assertStr("$rt_toString(null)", "null");

    assertStr("$rt_toString({toString: function(){return 's';}})", "s");

    assertInt("$rt_add(5, 3)", 8);
    assertFloat("$rt_add(5, 3.5)", 8.5);
    assertStr("$rt_add(5, 'bar')", "5bar");
    assertStr("$rt_add('foo', 'bar')", "foobar");

    assertInt("$rt_sub(5, 3)", 2);
    assertFloat("$rt_sub(5, 3.5)", 1.5);

    assertInt("$rt_mul(3, 5)", 15);
    assertFloat("$rt_mul(5, 1.5)", 7.5);
    assertFloat("$rt_mul(0xFFFF, 0xFFFF)", 4294836225);

    assertFloat("$rt_div(15, 3)", 5);
    assertFloat("$rt_div(15, 1.5)", 10);

    assertBool("$rt_eq(3,3)", true);
    assertBool("$rt_eq(3,5)", false);
    assertBool("$rt_eq('foo','foo')", true);

    assertInt("isNaN(3)? 1:0", 0);
    assertInt("isNaN(3.5)? 1:0", 0);
    assertInt("isNaN(NaN)? 1:0", 1);
    assertStr("$rt_toString(NaN);", "NaN");

    assertInt("$rt_getProp('foo', 'length')", 3);
    assertStr("$rt_getProp('foo', 0)", "f");
    assertInt("$rt_getProp([0,1], 'length')", 2);
    assertInt("$rt_getProp([3,4,5], 1)", 4);
    assertInt("$rt_getProp({v:7}, 'v')", 7);
    assertInt("a = [0,0,0]; $rt_setProp(a,1,5); return $rt_getProp(a,1);", 5);
    assertInt("a = [0,0,0]; $rt_setProp(a,9,7); return $rt_getProp(a,9);", 7);
    assertInt("a = []; $rt_setProp(a,'length',5); return $rt_getProp(a,'length');", 5);

    assertInt(
        "
        o = {};
        $rt_setProp(o,'a',1);
        $rt_setProp(o,'b',2);
        $rt_setProp(o,'c',3);
        return $rt_getProp(o,'c');
        ",
        3
    );

    assertBool("({}) instanceof Object", true);
    assertThrows("false instanceof false");
    assertBool("'foo' in {}", false);
    assertThrows("2 in null");
}

/// Closures, captured and escaping variables
unittest
{
    assertInt(
        "
        function foo(x) { return function() { return x; } }
        f = foo(5);
        return f();
        ",
        5
    );

    assertInt(
        "
        function foo(x) { var y = x + 1; return function() { return y; } }
        f = foo(5);
        return f();
        ",
        6
    );

    assertInt(
        "
        function foo(x) { return function() { return x++; } }
        f = foo(5);
        f();
        return f();
        ",
        6
    );

    assertInt(
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
    writefln("math");

    assertInt("Math.max(1,2);", 2);
    assertInt("Math.max(5,1,2);", 5);
    assertInt("Math.min(5,-1,2);", -1);

    assertFloat("Math.cos(0)", 1);
    assertFloat("Math.cos(Math.PI)", -1);
    assertInt("isNaN(Math.cos('f'))? 1:0", 1);

    assertFloat("Math.sin(0)", 0);
    assertFloat("Math.sin(Math.PI)", 0);

    assertFloat("Math.sqrt(4)", 2);

    assertInt("Math.pow(2, 0)", 1);
    assertInt("Math.pow(2, 4)", 16);
    assertInt("Math.pow(2, 8)", 256);

    assertFloat("Math.log(Math.E)", 1);
    assertFloat("Math.log(1)", 0);

    assertFloat("Math.exp(0)", 1);

    assertFloat("Math.ceil(1.5)", 2);
    assertInt("Math.ceil(2)", 2);

    assertFloat("Math.floor(1.5)", 1);
    assertInt("Math.floor(2)", 2);

    assertBool("r = Math.random(); return r >= 0 && r < 1;", true);
    assertBool("r0 = Math.random(); r1 = Math.random(); return r0 !== r1;", true);
}

/// Stdlib Object library
unittest
{
    assertBool("o = {k:3}; return o.hasOwnProperty('k');", true);
    assertBool("o = {k:3}; p = Object.create(o); return p.hasOwnProperty('k')", false);
    assertBool("o = {k:3}; p = Object.create(o); return 'k' in p;", true);
}

/// Stdlib Number library
unittest
{
    assertInt("Number(10)", 10);
    assertInt("Number(true)", 1);
    assertInt("Number(null)", 0);

    assertStr("(10).toString()", "10");
}

/// Stdlib Array library
unittest
{
    assertInt("a = Array(10); return a.length;", 10);
    assertInt("a = Array(1,2,3); return a.length;", 3);
    assertStr("([0,1,2]).toString()", "0,1,2");
}

/// Stdlib String library
unittest
{
    assertStr("String(10)", "10");
    assertStr("String(1.5)", "1.5");
    assertStr("String([0,1,2])", "0,1,2");

    assertStr("'foobar'.substring(0,3)", "foo");

    assertInt("'f,o,o'.split(',').length", 3);
}

/// Stdlib global functions
unittest
{
    assertInt("parseInt(10)", 10);
    assertInt("parseInt(-1)", -1);
    assertBool("isNaN(parseInt('zux'))", true);
}

/// Exceptions
unittest
{
    writefln("exceptions");

    auto interp = new Interp();

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
    interp.load("programs/exceptions/throw_inter.js");
    interp.assertInt("test();", 0);
    interp.load("programs/exceptions/throw_inter_fnl.js");
    interp.assertStr("str;", "abcdef");
    interp.load("programs/exceptions/try_call.js");
    interp.assertStr("str;", "abc");
}

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

/// Tachyon tests
unittest
{
    writefln("tachyon");

    auto interp = new Interp();

    // ES5 comparison operator test
    interp.load("programs/es5_cmp/es5_cmp.js");
    interp.assertInt("test();", 0);

    // Recursive Fibonacci computation
    interp.load("programs/fib/fib.js");
    interp.assertInt("fib(8);", 21);

    interp.load("programs/nested_loops/nested_loops.js");
    interp.assertInt("foo(10);", 510);

    interp.load("programs/bubble_sort/bubble_sort.js");
    interp.assertInt("test();", 0);

    // N-queens solver
    interp.load("programs/nqueens/nqueens.js");
    interp.assertInt("test();", 0);

    interp.load("programs/merge_sort/merge_sort.js");
    interp.assertInt("test();", 0);

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

    writefln("apply");

    // Call with apply
    interp.load("programs/apply/apply.js");
    interp.assertInt("test();", 0);

    writefln("arguments");

    // Arguments object
    interp.load("programs/arg_obj/arg_obj.js");
    interp.assertInt("test();", 0);

    writefln("for-in");

    // For-in loop
    interp.load("programs/for_in/for_in.js");
    interp.assertInt("test();", 0);

    writefln("load");

    // Dynamic code loading
    interp.load("programs/load/loader.js");

    writefln("stdlib");

    // Standard library
    interp.load("programs/stdlib_math/stdlib_math.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_boolean/stdlib_boolean.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_number/stdlib_number.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_function/stdlib_function.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_object/stdlib_object.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_array/stdlib_array.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_string/stdlib_string.js");
    interp.assertInt("test();", 0);
    interp.load("programs/stdlib_json/stdlib_json.js");
    interp.assertInt("test();", 0);
    // TODO: regexp support, regexp test
}

/// Regression tests
unittest
{
    writefln("regression");

    auto interp = new Interp();

    interp.load("programs/regress/regress_delta.js");
    interp.load("programs/regress/regress_in.js");
    interp.load("programs/regress/regress_tostring.js");
    interp.assertBool("4294967295.0 === 0xFFFFFFFF", true);
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

    interp = new Interp();
    interp.load("programs/gc/collect.js");
    interp.assertInt("test();", 0);

    interp = new Interp();
    interp.load("programs/gc/objects.js");

    interp = new Interp();
    interp.load("programs/gc/arrays.js");

    interp = new Interp();
    interp.load("programs/gc/closures.js");
    interp.assertInt("test();", 0);
  
    interp = new Interp();
    interp.load("programs/gc/deepstack.js");
    interp.assertInt("test();", 0);

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
}

/// SunSpider benchmarks
unittest
{
    writefln("sunspider");

    auto interp = new Interp();

    //interp.load("programs/sunspider/bitops-bitwise-and.js");

    interp.load("programs/sunspider/controlflow-recursive.js");
    interp.assertInt("ack(3,2);", 29);
    interp.assertInt("tak(9,5,3);", 4);

    //interp.load("programs/sunspider/math-partial-sums.js");
}

