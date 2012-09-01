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

/**
@fileOverview

Tests for stdlib array implementation.

@copyright
Copyright (c) 2010-2011 Tachyon Javascript Engine, All Rights Reserved
*/

/**
Test suite for the standard library implementation
*/
tests.stdlib = (tests.stdlib !== undefined)? tests.stdlib : tests.testSuite();

/**
Test suite for the arrays code
*/
tests.stdlib.arrays = function ()
{

function check_equal_arrays(arr1, arr2, msg)
{
    if (arr1.length !== arr2.length)
        throw msg+" bad: ["+arr1+"] ["+arr2+"]";

    for (var i=0; i<arr1.length; i++)
        if (arr1[i] !== arr2[i])
            throw msg+" bad: ["+arr1+"] ["+arr2+"]";
}

function check_toString(expected_arr, expected_res, arr)
{
    var res = arr.toString();

    check_equal_arrays(arr, expected_arr, "toString input array");

    if (res !== expected_res)
        throw "toString result bad";
}

function check_concat(expected_arr, expected_res, arr, arg1, arg2, arg3)
{
    var res;

    if (arg3 !== undefined)
        res = arr.concat(arg1, arg2, arg3);
    else if (arg2 !== undefined)
        res = arr.concat(arg1, arg2);
    else if (arg1 !== undefined)
        res = arr.concat(arg1);
    else
        res = arr.concat();

    check_equal_arrays(arr, expected_arr, "concat input array");
    check_equal_arrays(res, expected_res, "concat result");
}

function check_join(expected_arr, expected_res, arr, sep)
{
    var res;

    if (sep !== undefined)
        res = arr.join(sep);
    else
        res = arr.join();

    check_equal_arrays(arr, expected_arr, "join input array");

    if (res !== expected_res)
        throw "join result bad";
}

function check_pop(expected_arr, expected_res, arr)
{
    var res = arr.pop();

    check_equal_arrays(arr, expected_arr, "pop input array");

    if (res !== expected_res)
        throw "pop result bad";
}

function check_push(expected_arr, expected_res, arr, item1, item2, item3)
{
    var res;

    if (item3 !== undefined)
        res = arr.push(item1, item2, item3);
    else if (item2 !== undefined)
        res = arr.push(item1, item2);
    else if (item1 !== undefined)
        res = arr.push(item1);
    else
        res = arr.push();

    check_equal_arrays(arr, expected_arr, "push input array");

    if (res !== expected_res)
        throw "push result bad";
}

function check_reverse(expected_arr, expected_res, arr)
{
    var res = arr.reverse();

    check_equal_arrays(arr, expected_arr, "reverse input array");
    check_equal_arrays(res, expected_res, "reverse result");
}

function check_shift(expected_arr, expected_res, arr)
{
    var res = arr.shift();

    check_equal_arrays(arr, expected_arr, "shift input array");

    if (res !== expected_res)
        throw "shift result bad";
}

function check_slice(expected_arr, expected_res, arr, start, end)
{
    var res = arr.slice(start, end);

    check_equal_arrays(arr, expected_arr, "slice input array");
    check_equal_arrays(res, expected_res, "slice result");
}

function check_sort(expected_arr, expected_res, arr, comparefn)
{
    var res;

    if (comparefn !== undefined)
        res = arr.sort(comparefn);
    else
        res = arr.sort();

    check_equal_arrays(arr, expected_arr, "sort input array");
    check_equal_arrays(res, expected_res, "sort result");
}

function check_sort_comparefn(x, y)
{
    if (x < y)
        return -1;
    else if (x > y)
        return 1;
    else
        return 0;
}

function check_splice(expected_arr, expected_res, arr, start, end, item1, item2, item3)
{
    var res;

    if (item3 !== undefined)
        res = arr.splice(start, end, item1, item2, item3);
    else if (item2 !== undefined)
        res = arr.splice(start, end, item1, item2);
    else if (item1 !== undefined)
        res = arr.splice(start, end, item1);
    else if (end !== undefined)
        res = arr.splice(start, end);
    else if (start !== undefined)
        res = arr.splice(start);
    else
        res = arr.splice();

    check_equal_arrays(arr, expected_arr, "splice input array");
    check_equal_arrays(res, expected_res, "splice result");
}

function check_unshift(expected_arr, expected_res, arr, item1, item2, item3)
{
    var res;

    if (item3 !== undefined)
        res = arr.unshift(item1, item2, item3);
    else if (item2 !== undefined)
        res = arr.unshift(item1, item2);
    else if (item1 !== undefined)
        res = arr.unshift(item1);
    else
        res = arr.unshift();

    check_equal_arrays(arr, expected_arr, "unshift input array");

    if (res !== expected_res)
        throw "unshift result bad";
}

function check_indexOf(expected_arr, expected_res, arr, searchElement, fromIndex)
{
    var res;

    if (fromIndex !== undefined)
        res = arr.indexOf(searchElement, fromIndex);
    else
        res = arr.indexOf(searchElement);

    check_equal_arrays(arr, expected_arr, "indexOf input array");

    if (res !== expected_res)
        throw "indexOf result bad";
}

function check_lastIndexOf(expected_arr, expected_res, arr, searchElement, fromIndex)
{
    var res;

    if (fromIndex !== undefined)
        res = arr.lastIndexOf(searchElement, fromIndex);
    else
        res = arr.lastIndexOf(searchElement);

    check_equal_arrays(arr, expected_arr, "lastIndexOf input array");

    if (res !== expected_res)
        throw "lastIndexOf result bad";
}

function check_forEach(expected_arr, expected_sum, arr)
{
    var callbackfn = check_forEach_callbackfn;
    var thisArg = undefined;

    check_forEach_sum = 0;
    arr.forEach(callbackfn, thisArg);

    check_equal_arrays(arr, expected_arr, "forEach input array");

    if (check_forEach_sum !== expected_sum)
        throw "forEach sum bad";
}

var check_forEach_sum;

function check_forEach_callbackfn(val, index, arr)
{
    check_forEach_sum += (val + index * 100 + arr.length * 10000);
}

function check_map(expected_arr, expected_res, expected_sum, arr)
{
    var callbackfn = check_map_callbackfn;
    var thisArg = undefined;

    check_map_sum = 0;
    var res = arr.map(callbackfn, thisArg);

    check_equal_arrays(arr, expected_arr, "map input array");
    check_equal_arrays(res, expected_res, "map result");

    if (check_map_sum !== expected_sum)
        throw "map sum bad";
}

var check_map_sum;

function check_map_callbackfn(val, index, arr)
{
    check_map_sum += (val + index * 100 + arr.length * 10000);
    return val*val + 1000;
}

function check_filter(expected_arr, expected_res, expected_sum, arr)
{
    var callbackfn = check_filter_callbackfn;
    var thisArg = undefined;

    check_filter_sum = 0;
    var res = arr.filter(callbackfn, thisArg);

    check_equal_arrays(arr, expected_arr, "filter input array");
    check_equal_arrays(res, expected_res, "filter result");

    if (check_filter_sum !== expected_sum)
        throw "filter sum bad";
}

var check_filter_sum;

function check_filter_callbackfn(val, index, arr)
{
    check_filter_sum += (val + index * 100 + arr.length * 10000);
    return (val & 1) === 1;
}

check_toString([], "", []);
check_toString([11], "11", [11]);
check_toString([11,22], "11,22", [11,22]);
check_toString([11,22,33], "11,22,33", [11,22,33]);
check_toString([11,22,33,44,55,66,77,88,99], "11,22,33,44,55,66,77,88,99", [11,22,33,44,55,66,77,88,99]);

check_concat([11,22], [11,22], [11,22]);
check_concat([11,22], [11,22,33,44], [11,22], [33,44]);
check_concat([11,22], [11,22,33,44,55,66], [11,22], [33,44], [55,66]);
check_concat([11,22], [11,22,33,44,55,66,77,88], [11,22], [33,44], [55,66], [77,88]);

check_join([], "", []);
check_join([11], "11", [11]);
check_join([11,22], "11,22", [11,22]);
check_join([11,22,33], "11,22,33", [11,22,33]);
check_join([], "", [], "::");
check_join([11], "11", [11], "::");
check_join([11,22], "11::22", [11,22], "::");
check_join([11,22,33], "11::22::33", [11,22,33], "::");

check_pop([], undefined, []);
check_pop([], 11, [11]);
check_pop([11], 22, [11,22]);
check_pop([11,22], 33, [11,22,33]);
check_pop([11,22,33,44,55,66,77,88], 99, [11,22,33,44,55,66,77,88,99]);

check_push([11,22,33], 3, [11,22,33]);
check_push([11,22,33,44], 4, [11,22,33], 44);
check_push([11,22,33,44,55], 5, [11,22,33], 44, 55);
check_push([11,22,33,44,55,66], 6, [11,22,33], 44, 55, 66);

check_reverse([], [], []);
check_reverse([11], [11], [11]);
check_reverse([22,11], [22,11], [11,22]);
check_reverse([33,22,11], [33,22,11], [11,22,33]);
check_reverse([99,88,77,66,55,44,33,22,11], [99,88,77,66,55,44,33,22,11], [11,22,33,44,55,66,77,88,99]);

check_shift([], undefined, []);
check_shift([], 11, [11]);
check_shift([22], 11, [11,22]);
check_shift([22,33], 11, [11,22,33]);
check_shift([22,33,44,55,66,77,88,99], 11, [11,22,33,44,55,66,77,88,99]);

check_slice([11,22,33,44,55,66,77,88,99], [11,22,33,44,55,66,77,88,99], [11,22,33,44,55,66,77,88,99]);
check_slice([11,22,33,44,55,66,77,88,99], [22,33,44,55,66,77,88,99], [11,22,33,44,55,66,77,88,99], 1);
check_slice([11,22,33,44,55,66,77,88,99], [22,33], [11,22,33,44,55,66,77,88,99], 1, 3);
check_slice([11,22,33,44,55,66,77,88,99], [22,33,44,55,66], [11,22,33,44,55,66,77,88,99], 1, -3);
check_slice([11,22,33,44,55,66,77,88,99], [33,44,55,66], [11,22,33,44,55,66,77,88,99], -7, -3);

check_sort([], [], [], check_sort_comparefn);
check_sort([11], [11], [11], check_sort_comparefn);
check_sort([11,22], [11,22], [11,22], check_sort_comparefn);
check_sort([11,22], [11,22], [22,11], check_sort_comparefn);
check_sort([11,22,33], [11,22,33], [11,22,33], check_sort_comparefn);
check_sort([11,22,33], [11,22,33], [11,33,22], check_sort_comparefn);
check_sort([11,22,33], [11,22,33], [22,11,33], check_sort_comparefn);
check_sort([11,22,33], [11,22,33], [33,11,22], check_sort_comparefn);
check_sort([11,22,33], [11,22,33], [22,33,11], check_sort_comparefn);
check_sort([11,22,33], [11,22,33], [33,22,11], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [11,22,33,44], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [11,33,22,44], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [22,11,33,44], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [33,11,22,44], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [22,33,11,44], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [33,22,11,44], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [11,22,44,33], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [11,33,44,22], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [22,11,44,33], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [33,11,44,22], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [22,33,44,11], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [33,22,44,11], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [11,44,22,33], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [11,44,33,22], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [22,44,11,33], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [33,44,11,22], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [22,44,33,11], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [33,44,22,11], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [44,11,22,33], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [44,11,33,22], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [44,22,11,33], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [44,33,11,22], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [44,22,33,11], check_sort_comparefn);
check_sort([11,22,33,44], [11,22,33,44], [44,33,22,11], check_sort_comparefn);
check_sort([11,22,33,44,55,66,77,88,99], [11,22,33,44,55,66,77,88,99], [11,22,33,44,55,66,77,88,99], check_sort_comparefn);
check_sort([11,22,33,44,55,66,77,88,99], [11,22,33,44,55,66,77,88,99], [99,88,77,66,55,44,33,22,11], check_sort_comparefn);
check_sort([45,49,405], [45,49,405], [49,405,45], check_sort_comparefn);
check_sort([405,45,49], [405,45,49], [49,405,45]);

check_splice([11,22,33,44,55,66,77,88,99], [], [11,22,33,44,55,66,77,88,99]);
check_splice([11], [22,33,44,55,66,77,88,99], [11,22,33,44,55,66,77,88,99], 1);
check_splice([11,55,66,77,88,99], [22,33,44], [11,22,33,44,55,66,77,88,99], 1, 3);
check_splice([11,11111,44,55,66,77,88,99], [22,33], [11,22,33,44,55,66,77,88,99], 1, 2, 11111);
check_splice([11,11111,22222,44,55,66,77,88,99], [22,33], [11,22,33,44,55,66,77,88,99], 1, 2, 11111, 22222);
check_splice([11,11111,22222,33333,44,55,66,77,88,99], [22,33], [11,22,33,44,55,66,77,88,99], 1, 2, 11111, 22222, 33333);
check_splice([11,22,11111,55,66,77,88,99], [33,44], [11,22,33,44,55,66,77,88,99], -7, 2, 11111);
check_splice([11,22,11111,22222,55,66,77,88,99], [33,44], [11,22,33,44,55,66,77,88,99], -7, 2, 11111, 22222);
check_splice([11,22,11111,22222,33333,55,66,77,88,99], [33,44], [11,22,33,44,55,66,77,88,99], -7, 2, 11111, 22222, 33333);

check_unshift([11,22,33], 3, [11,22,33]);
check_unshift([44,11,22,33], 4, [11,22,33], 44);
check_unshift([44,55,11,22,33], 5, [11,22,33], 44, 55);
check_unshift([44,55,66,11,22,33], 6, [11,22,33], 44, 55, 66);

check_indexOf([11,22,11,33,22,44,22], 1, [11,22,11,33,22,44,22], 22);
check_indexOf([11,22,11,33,22,44,22], 1, [11,22,11,33,22,44,22], 22, 0);
check_indexOf([11,22,11,33,22,44,22], 1, [11,22,11,33,22,44,22], 22, 1);
check_indexOf([11,22,11,33,22,44,22], 4, [11,22,11,33,22,44,22], 22, 2);
check_indexOf([11,22,11,33,22,44,22], -1, [11,22,11,33,22,44,22], 22, 7);
check_indexOf([11,22,11,33,22,44,22], 6, [11,22,11,33,22,44,22], 22, -1);
check_indexOf([11,22,11,33,22,44,22], 6, [11,22,11,33,22,44,22], 22, -2);
check_indexOf([11,22,11,33,22,44,22], 1, [11,22,11,33,22,44,22], 22, -10);

check_lastIndexOf([11,22,11,33,22,44,22], 6, [11,22,11,33,22,44,22], 22);
check_lastIndexOf([11,22,11,33,22,44,22], -1, [11,22,11,33,22,44,22], 22, 0);
check_lastIndexOf([11,22,11,33,22,44,22], 1, [11,22,11,33,22,44,22], 22, 1);
check_lastIndexOf([11,22,11,33,22,44,22], 1, [11,22,11,33,22,44,22], 22, 2);
check_lastIndexOf([11,22,11,33,22,44,22], 6, [11,22,11,33,22,44,22], 22, 7);
check_lastIndexOf([11,22,11,33,22,44,22], 6, [11,22,11,33,22,44,22], 22, -1);
check_lastIndexOf([11,22,11,33,22,44,22], 4, [11,22,11,33,22,44,22], 22, -2);
check_lastIndexOf([11,22,11,33,22,44,22], -1, [11,22,11,33,22,44,22], 22, -10);

check_forEach([], 0, []);
check_forEach([1], 10001, [1]);
check_forEach([1,2], 40103, [1,2]);
check_forEach([1,2,3], 90306, [1,2,3]);
check_forEach([1,2,3,4], 160610, [1,2,3,4]);

check_map([], [], 0, []);
check_map([1], [1001], 10001, [1]);
check_map([1,2], [1001,1004], 40103, [1,2]);
check_map([1,2,3], [1001,1004,1009], 90306, [1,2,3]);
check_map([1,2,3,4], [1001,1004,1009,1016], 160610, [1,2,3,4]);

check_filter([], [], 0, []);
check_filter([1], [1], 10001, [1]);
check_filter([1,2], [1], 40103, [1,2]);
check_filter([1,2,3], [1,3], 90306, [1,2,3]);
check_filter([1,2,3,4], [1,3], 160610, [1,2,3,4]);

};
