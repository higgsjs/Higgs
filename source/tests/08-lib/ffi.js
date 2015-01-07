/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013, Maxime Chevalier-Boisvert. All rights reserved.
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

var test = require('lib/test');
var console = require('lib/console');
var ffi = require('lib/ffi');
var c = ffi.c;

// JS <=> C string conversion
assert(ffi.string(ffi.cstr('foo')) == 'foo');
assert(ffi.string(ffi.cstr('f' + 'oo')) == 'foo');

// Test array wrappers
c.cdef("\
       int TestIntArray[3];\
");

assertEq(c.TestIntArray.toString(), "[ 1, 2, 3 ]");
assertEqArray(c.TestIntArray.toJS(), [1,2,3]);

// Test struct wrappers
c.cdef("\
       struct CustomerStruct { int num; double balance; char name[10]; };\
       typedef struct CustomerStruct Customer;\
       Customer TestCustomer;\
");

var bob = c.TestCustomer;
assertEq(bob.name.toString(), "Bob");
assertEq(bob.get_num(), 6);
assertEq(bob.get_balance(), 2.22);

// Accessing the CustomerStruct CType
var custType = c.ctypes['struct CustomerStruct'];
assertTrue(custType.size > 0);

// Allocating a new struct (with malloc)
var sarah = custType.wrapper_fun();
assertNotEq(sarah.ptr, undefined);
assertFalse(ffi.isNullPtr(sarah.ptr));
sarah.set_num(777);
assertEq(sarah.get_num(), 777);

// Test union wrappers

c.cdef("\
       union NumberUnion { int i; double f; };\
       union NumberUnion TestNumberUnionInt;\
       union NumberUnion TestNumberUnionDouble;\
");

assertEq(c.TestNumberUnionInt.get_i(), 32);
assertEq(c.TestNumberUnionDouble.get_f(), 5.50);

// Test enum wrappers

c.cdef("\
       enum Charms { HEARTS, STARS, HORSESHOES };\
");

assertEq(c.Charms.HEARTS, 0);
assertEq(c.Charms.STARS, 1);
assertEq(c.Charms.HORSESHOES, 2);

// Test string wrapping
c.cdef("\
       char *getTestString();\
");

assertEq(ffi.string(c.getTestString()), "Hello World!");

// Test os name
var os = ffi.os;
assertTrue(os === "LINUX" || os === "BSD" || os === "OSX");

// issue #102 regression
// TODO: explain what this is a regression test for
c.cdef(`
       typedef unsigned long long  __uint64_t;
       typedef unsigned int        __uint32_t;
       typedef unsigned short      __uint16_t;
       typedef unsigned char       __uint8_t;
       struct direntBSD {
           __uint64_t d_fileno;
           __uint16_t d_seekoff;
           __uint16_t d_reclen;
           __uint16_t d_namlen;
           __uint8_t  d_type;
           char       d_name[1024];
       };
       struct direntBSD TestDirEnt;
`);

var testdir = c.TestDirEnt;
//assertTrue($ir_eq_i64(1, testdir.get_d_fileno())); // FIXME: fails under DMD 2.066
assertEq(testdir.get_d_seekoff(), 2);
assertEq(testdir.get_d_reclen(), 3);
assertEq(testdir.get_d_namlen(), 4);
assertEq(testdir.get_d_type(), 5);
assertEq(testdir.d_name.toString(), "foo");

