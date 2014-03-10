/* _________________________________________________________________________
 *
 *             Tachyon : A Self-Hosted JavaScript Virtual Machine
 *
 *
 *  This file is part of the Tachyon JavaScript project. Tachyon is
 *  distributed at:
 *  http://github.com/Tachyon-Team/Tachyon
 *
 *
 *  Copyright (c) 2011-2014, Universite de Montreal
 *  All rights reserved.
 *
 *  This software is licensed under the following license (Modified BSD
 *  License):
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are
 *  met:
 *    * Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the Universite de Montreal nor the names of its
 *      contributors may be used to endorse or promote products derived
 *      from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 *  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 *  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 *  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL UNIVERSITE DE
 *  MONTREAL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * _________________________________________________________________________
 */

var T = true;
var F = false;
var undef = undefined;

var o1 = {};
var o2 = {};

var o_str = { toString: function () { return 'foo'; } };
var o_num = { toString: function () { return 3; } };

var tests = [
    // v1     v2      <  <= >  >= == != === !==
    [1      , 2     , T, T, F, F, F, T, F, T],
    [1      , '1'   , F, T, F, T, T, F, F, T],
    [1      , ' 1'  , F, T, F, T, T, F, F, T],
    [1      , '1 '  , F, T, F, T, T, F, F, T],
    ['1'    , 2     , T, T, F, F, F, T, F, T],
    [1      , '2'   , T, T, F, F, F, T, F, T],
    ['1'    , '2'   , T, T, F, F, F, T, F, T],
    ['34'   , '4'   , T, T, F, F, F, T, F, T],
    ['-100' , 'a'   , T, T, F, F, F, T, F, T],
    [undef  , '2'   , F, F, F, F, F, T, F, T],
    [o1     , o2    , F, T, F, T, F, T, F, T],

    [2      , 1     , F, F, T, T, F, T, F, T],
    ['1'    , 1     , F, T, F, T, T, F, F, T],
    [' 1'   , 1     , F, T, F, T, T, F, F, T],
    ['1 '   , 1     , F, T, F, T, T, F, F, T],
    [2      , '1'   , F, F, T, T, F, T, F, T],
    ['2'    , 1     , F, F, T, T, F, T, F, T],
    ['2'    , '1'   , F, F, T, T, F, T, F, T],
    ['4'    , '34'  , F, F, T, T, F, T, F, T],
    ['a'    , '-100', F, F, T, T, F, T, F, T],
    ['2'    , undef , F, F, F, F, F, T, F, T],

    [o_num  , '4'   , T, T, F, F, F, T, F, T],
    [o_num  , '3'   , F, T, F, T, T, F, F, T],
    [o_num  , 3     , F, T, F, T, T, F, F, T],

    [o_str  , 'foo' , F, T, F, T, T, F, F, T],
    [o_str  , 'goo' , T, T, F, F, F, T, F, T],

    ['1'    , true  , F, T, F, T, T, F, F, T],
    ['0'    , false , F, T, F, T, T, F, F, T],
    ['0'    , null  , F, T, F, T, F, T, F, T],
    [null   , '0'   , F, T, F, T, F, T, F, T],
    [null   , undef , F, F, F, F, T, F, F, T],
    [null   , 0     , F, T, F, T, F, T, F, T],
    [0      , null  , F, T, F, T, F, T, F, T],

    [1      , 1     , F, T, F, T, T, F, T, F],
    ['2'    , '2'   , F, T, F, T, T, F, T, F],
    ['foo'  , 'foo' , F, T, F, T, T, F, T, F],
    [true   , true  , F, T, F, T, T, F, T, F],
    [false  , false , F, T, F, T, T, F, T, F],
    [null   , null  , F, T, F, T, T, F, T, F],
    [undef  , undef , F, F, F, F, T, F, T, F],
    [o_num  , o_num , F, T, F, T, T, F, T, F],
    [o_str  , o_str , F, T, F, T, T, F, T, F]
];

function testOp(v1, v2, op, produced, expected)
{
    if (produced !== expected)
    {
        print(
            v1 + ' ' + op + ' ' + v2 + ' ==> ' + 
            produced + ' (expected ' + expected + ')'
        );

        throw Error("wrong result for cmp op " + op);
    }
}

for (var i = 0; i < tests.length; ++i)
{
    var test = tests[i];

    var testNo = 10 * i;

    var v1 = test[0]
    var v2 = test[1];

    var lt  = test[2];
    var le  = test[3];
    var gt  = test[4];
    var ge  = test[5];
    var eq  = test[6];
    var ne  = test[7];
    var seq = test[8];
    var sne = test[9];

    /*
    println('test ' + i);
    println(typeof v1);
    println(typeof v2);
    print(v1);
    print('\n');
    print(v2);
    print('\n');
    */

    testOp(v1, v2, '<'  , (v1 < v2)     , lt    );
    testOp(v1, v2, '<=' , (v1 <= v2)    , le    );
    testOp(v1, v2, '>'  , (v1 > v2)     , gt    );
    testOp(v1, v2, '>=' , (v1 >= v2)    , ge    );
    testOp(v1, v2, '==' , (v1 == v2)    , eq    );
    testOp(v1, v2, '!=' , (v1 != v2)    , ne    );
    testOp(v1, v2, '===', (v1 === v2)   , seq   );
    testOp(v1, v2, '!==', (v1 !== v2)   , sne   );
}

