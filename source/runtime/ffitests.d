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

module runtime.FFItests;

import std.stdio;
import std.string;
import std.math;
import std.conv;
import parser.parser;
import ir.ast;
import runtime.layout;
import runtime.vm;
import repl;

// Include the FFI test harness only if compiling a (unit)test binary or "FFIdev" binary
version (unittest)
    version = TestFFI;

version (FFIdev)
    version = TestFFI;

// Dummy functions used for FFI tests
version (TestFFI)
{
    // Used to test the low-level FFI ops
    extern (C)
    {
        void testVoidFun()
        {
            return;
        }

        short testShortFun()
        {
            return 2;
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

        void* testPtrArgFun(void* ptrArg)
        {
            return ptrArg;
        }

        double testMixedArgsFun(int a, double b, int c, double d, int e, double f, int g)
        {
            return cast(double)(a + b + c + d + e + (f - g));
        }

    }

    // Used to test the FFI lib
    extern (C)
    {
        // test struct wrappers
        struct CustomerStruct { int num; double balance; char name[10]; }
        static CustomerStruct TestCustomer = { num: 6, balance: 2.22, name: "Bob" };

        // test union wrappers
        union NumberUnion { int i; double f; }
        static NumberUnion TestNumberUnionInt = { i: 32 };
        static NumberUnion TestNumberUnionDouble = { f: 5.50 };

        // test arrays
        static int TestIntArray[3] = [1, 2, 3];

        static string HelloWorld = "Hello World!";

        immutable(char)* getTestString()
        {
            return HelloWorld.ptr;
        }
    }
}

unittest
{
    writefln("FFI");

    auto vm = new VM();
    vm.load("tests/core/ffi/ffi.js");
}

