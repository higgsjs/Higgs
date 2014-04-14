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

var ffi = require('lib/ffi');
var c = ffi.c;
var console = require('lib/console');

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

var Bob = c.TestCustomer;
assertEq(Bob.name.toString(), "Bob");
assertEq(Bob.get_num(), 6);
assertEq(Bob.get_balance(), 2.22);

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
var os = ffi.getOSName();
assertTrue(os === "LINUX" || os === "BSD" || os === "OSX");
