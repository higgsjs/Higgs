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
 *  Copyright (c) 2011, Universite de Montreal
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

function array_eq(a1, a2)
{
    if (a1.length !== a2.length)
        return false;

    for (var i = 0; i < a1.length; ++i)
        if (a1[i] !== a2[i])
            return false;

    return true;
}

function test_ctor()
{
    if (!array_eq(new Array(3), [undefined, undefined, undefined]))
        return 1;

    if (!array_eq(new Array(0,1,2), [0,1,2]))
        return 2;

    if (!array_eq(Array(0,1,2), [0,1,2]))
        return 3;

    return 0;
}

function test_indexOf()
{
    var a = ['a', 'b', 'c', 'd'];

    if (a.indexOf('a') != 0)
        return 1;
    if (a.indexOf('b') != 1)
        return 2;
    if (a.indexOf('c') != 2)
        return 3;
    if (a.indexOf('d') != 3)
        return 4;
    if (a.indexOf('e') != -1)
        return 5;

    return 0;
}

function test_lastIndexOf()
{
    var a = ['a', 'b', 'c', 'd', 'c', 'c'];

    if (a.lastIndexOf('a') != 0)
        return 1;
    if (a.lastIndexOf('b') != 1)
        return 2;
    if (a.lastIndexOf('c') != 5)
        return 3;
    if (a.lastIndexOf('d') != 3)
        return 4;
    if (a.lastIndexOf('e') != -1)
        return 5;

    return 0;
}

function test_push()
{
    var a = [0,1,2];

    a.push(3);
    if (!array_eq(a, [0,1,2,3]))
        return 1;

    a.push(4,5)
    if (!array_eq(a, [0,1,2,3,4,5]))
        return 2;

    return 0;
}

function test_pop()
{
    var a = [0,1,2,3,4];

    var r = a.pop();
    if (r != 4)
        return 1;
    if (!array_eq(a, [0,1,2,3]))
        return 2;

    var r = a.pop();
    if (r != 3)
        return 3;
    if (!array_eq(a, [0,1,2]))
        return 4;

    while (a.length > 0)
        a.pop();
    if (!array_eq(a, []))
        return 5;

    return 0;
}

function test_unshift()
{
    var a = [0,1,2];

    a.unshift(3);
    if (!array_eq(a, [3,0,1,2]))
        return 1;

    a.unshift(4)
    if (!array_eq(a, [4,3,0,1,2]))
        return 2;

    return 0;
}

function test_shift()
{
    var a = [0,1,2,3,4];

    var r = a.shift();
    if (r != 0)
        return 1;
    if (!array_eq(a, [1,2,3,4]))
        return 2;

    var r = a.shift();
    if (r != 1)
        return 3;
    if (!array_eq(a, [2,3,4]))
        return 4;

    while (a.length > 0)
        a.shift();
    if (!array_eq(a, []))
        return 5;

    return 0;
}

function test_slice()
{
    var a = [0,1,2,3];

    if (!array_eq(a.slice(0), [0,1,2,3]))
        return 1;

    if (!array_eq(a.slice(1,3), [1,2]))
        return 2;

    return 0;
}

function test_concat()
{
    if (!array_eq([].concat([]), []))
        return 1;

    if (!array_eq([].concat([1]), [1]))
        return 2;

    if (!array_eq([].concat([1,2]), [1,2]))
        return 3;

    if (!array_eq([].concat(1), [1]))
        return 4;

    if (!array_eq([1,2].concat([]), [1,2]))
        return 5;

    if (!array_eq([1,2].concat([3,4]), [1,2,3,4]))
        return 6;

    if (!array_eq([1,2].concat([3,4],5), [1,2,3,4,5]))
        return 7;

    if (!array_eq([1,2].concat([3,4],5,[6]), [1,2,3,4,5,6]))
        return 8;

    return 0;
}

function test_join()
{
    var o = { toString: function () { return 'foo'; } };

    if ([].join() != '')
        return 1;

    if ([].join(',') != '')
        return 2;

    if ([1].join(',') != '1')
        return 3;

    if ([1,2].join() != '1,2')
        return 4;

    if ([1,o,2].join() != '1,foo,2')
        return 5;

    if ([1,o,2].join('!?') != '1!?foo!?2')
        return 6;

    return 0;
}

function test_splice()
{
    var a = [0,1,2,3];
    var b = a.splice(0);
    if (!array_eq(b, [0,1,2,3]))
        return 1;
    if (!array_eq(a, []))
        return 2;

    var a = [0,1,2,3];
    var b = a.splice(1,2);
    if (!array_eq(b, [1,2]))
        return 3;
    if (!array_eq(a, [0,3]))
        return 4;

    var a = [0,1,2,3];
    var b = a.splice(1,2,4,5,6)
    if (!array_eq(b, [1,2]))
        return 5;
    if (!array_eq(a, [0,4,5,6,3]))
        return 6;

    return 0;
}

function test_reverse()
{
    var a = [0,1,2,3,4];

    var b = a.reverse();

    if (!array_eq(b, [4,3,2,1,0]))
        return 1;

    return 0;
}

function test_sort()
{
    function numeric_comparefn(x, y)
    {
        if (x < y)
            return -1;
        else if (x > y)
            return 1;
        else
            return 0;
    }

    var a = [0,-5,3,15,12,-33,7];

    a.sort(numeric_comparefn);

    var b = [-33,-5,0,3,7,12,15];

    if (!array_eq(a, b))
        return 1;

    return 0;
}

function test_map()
{
    var a = [0,1,2,3,4,5];

    var o = a.map(function (v) { return 2*v + 1; });

    if (!array_eq(o, [1,3,5,7,9,11]))
        return 1;

    return 0;
}

function test_forEach()
{
    var a = [0,1,2,3,4,5];

    var o = [];

    a.forEach(function (v) { o.push(2*v + 1); });

    if (!array_eq(o, [1,3,5,7,9,11]))
        return 1;

    return 0;
}

function test_reduce()
{
    if ([0,2,2,3,1].reduce(function(a,b){ return a * b; })  != 0)
        return 1;
    if ([1,2,4,5].reduce(function(a,b){ return a * b; }) != 40)
        return 2;
    if ([0,2,3,4].reduce(function(a,b){ return a + b; }, 4) != 13)
        return 3;
    if ([1,2,3].reduce(function(a,b){ return a * b; }, 4) != 24)
        return 4;

    // operations on sparse array
    var sparseArray = [];
    sparseArray[15] = 10;
    sparseArray[12] = 20;
    sparseArray[30] = 30;
    if (sparseArray.reduce(function(a,b){ return a - b; }, 100) != 40)
        return 5;
    if (sparseArray.reduce(function(a,b){return a+1;}) != 22)
        return 6;

    if (sparseArray.reduce(function(a,b){return a+1;}, 10) != 13)
        return 7;

    // operations on object passed as param
    var count = [1, 2, 3, 4].reduce(function(a,b, i, thisObj){ thisObj.length--;  return a + 1; }, 0);
    if (count != 2)
        return 8;

    count = [1, 2, 3, 4].reduce(function(a,b, i, thisObj){ thisObj.length++; return a + 1; }, 0);
    if (count != 4)
        return 9;

    var opArr = [[0,1], [2,3], [4,5]].reduce(function(a,b) {return a.concat(b);}, []);
    if (!array_eq(opArr, [0,1,2,3,4,5]))
        return 10;

    opArr = [0,1,2,3,4,5].reduce(function(a,b,i) {return a.concat([i,b, i + b]);}, []);
    if (!array_eq(opArr, [0,0,0,1,1,2,2,2,4,3,3,6,4,4,8,5,5,10]))
         return 11;

    return 0;
}

function test_reduceRight()
{
    if ([0,2,2,3,1].reduceRight(function(a,b){ return a * b; })  != 0)
        return 1;
    if ([1,2,4,5].reduceRight(function(a,b){ return a * b; }) != 40)
        return 2;
    if ([0,2,3,4].reduceRight(function(a,b){ return a + b; }, 4) != 13)
        return 3;
    if ([1,2,3].reduceRight(function(a,b){ return a * b; }, 4) != 24)
        return 4;

    // operations on sparse array
    var sparseArray = [];
    sparseArray[15] = 10;
    sparseArray[12] = 20;
    sparseArray[30] = 30;
    if (sparseArray.reduceRight(function(a,b){ return a - b; }, 100) != 40)
        return 5;
    if (sparseArray.reduceRight(function(a,b){return a+1;}) != 32)
        return 6;

    if (sparseArray.reduceRight(function(a,b){return a+1;}, 10) != 13)
        return 7;

    // operations on object passed as param
    var count = [1, 2, 3, 4].reduceRight(function(a,b, i, thisObj){ thisObj.length--;  return a + 1; }, 0);
    if (count != 4)
        return 8;

    count = [1, 2, 3, 4].reduceRight(function(a,b, i, thisObj){ thisObj.length++; return a + 1; }, 0);
    if (count != 4)
        return 9;

    var opArr = [[0,1], [2,3], [4,5]].reduceRight(function(a,b) {return a.concat(b);}, []);
    if (!array_eq(opArr, [4,5,2,3,0,1]))
        return 10;

    opArr = [0,1,2,3,4,5].reduceRight(function(a,b,i) {return a.concat([i,b, i + b]);}, []);
    if (!array_eq(opArr, [5,5,10,4,4,8,3,3,6,2,2,4,1,1,2,0,0,0]))
         return 11;

    return 0;
}

function test()
{
    var r = test_ctor();
    if (r != 0)
        return 100 + r;

    var r = test_indexOf();
    if (r != 0)
        return 200 + r;

    var r = test_lastIndexOf();
    if (r != 0)
        return 300 + r;

    var r = test_push();
    if (r != 0)
        return 400 + r;

    var r = test_pop();
    if (r != 0)
        return 500 + r;

    var r = test_unshift();
    if (r != 0)
        return 600 + r;

    var r = test_shift();
    if (r != 0)
        return 700 + r;

    var r = test_slice();
    if (r != 0)
        return 800 + r;

    var r = test_concat();
    if (r != 0)
        return 900 + r;

    var r = test_join();
    if (r != 0)
        return 1000 + r;

    var r = test_splice();
    if (r != 0)
        return 1100 + r;

    var r = test_reverse();
    if (r != 0)
        return 1200 + r;

    var r = test_sort();
    if (r != 0)
        return 1300 + r;

    var r = test_map();
    if (r != 0)
        return 1400 + r;

    var r = test_forEach();
    if (r != 0)
        return 1500 + r;

    var r = test_reduce()
    if (r != 0)
        return 1600 + r;

    var r = test_reduceRight()
    if (r != 0)
        return 1700 + r;

    return 0;
}

