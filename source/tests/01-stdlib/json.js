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

// Test case from mjsunit (http://v8.googlecode.com/svn/trunk/test/mjsunit/)
// TODO: test invalid inputs

function equal(a, b)
{
    //println(a);
    //println(b);

    if (a === b)
        return true;

    if (typeof a !== "object")
        return a === b;

    var pa = Object.keys(a);
    var pb = Object.keys(b);

    if (pa.length !== pb.length)
        return false;

    for (var i = 0; i < pa.length; ++i)
    {
        if (!equal(a[pa[i]], b[pb[i]]))
            return false;
    }
    return true;
}

function get_filter(name)
{
    function filter(key, value)
    {
        //println('key: ' + key);
        //println('value: ' + value);

        return (key == name) ? undefined : value;
    }

    return filter;
}

function test_parse()
{
    if (!equal({}, JSON.parse("{}")))
        return 1;
    if (!equal({42:37}, JSON.parse('{"42":37}')))
        return 2;
    if (!equal(null, JSON.parse('null')))
        return 3;
    if (!equal(true, JSON.parse('true')))
        return 4;
    if (!equal(false, JSON.parse('false')))
        return 5;
    if (!equal("foo", JSON.parse('"foo"')))
        return 6;
    if (!equal("f\no", JSON.parse('"f\\no"')))
        return 7;
    if (!equal("f\no", JSON.parse('"f\\no"')))
        return 8;
    if (!equal([1], JSON.parse("[1]")))
        return 9;
    if (!equal(0, JSON.parse("0")))
        return 10;
    if (!equal(1, JSON.parse("1")))
        return 11;
    if (!equal([], JSON.parse("[]")))
        return 12;
    if (!equal([1, "2", true, null], JSON.parse('[1, "2", true, null]')))
        return 13;
    if (!equal("", JSON.parse('""')))
        return 14;
    if (!equal("", JSON.parse('""')))
        return 15;
    if (!equal(["", "", -0, ""], JSON.parse('[     ""     ,    ""   ,    -0,     ""]')))
        return 16;

    var pointJSON = '{"x": 1, "y": 2}';

    if (!equal({'x': 1, 'y': 2}, JSON.parse(pointJSON)))
        return 17;
    if (!equal({'x': 1}, JSON.parse(pointJSON, get_filter('y'))))
        return 18;
    if (!equal({'y': 2}, JSON.parse(pointJSON, get_filter('x'))))
        return 19;
    if (!equal([1, 2, 3], JSON.parse("[1, 2, 3]")))
        return 20;
    if (!equal([1, undefined, 3], JSON.parse("[1, 2, 3]", get_filter(1))))
        return 21;
    if (!equal([1, 2, undefined], JSON.parse("[1, 2, 3]", get_filter(2))))
        return 22;
    if (!equal({"a": {"b": 1, "c": 2}, "d": {"e" : {"f": 3}}}, JSON.parse('{"a": {"b": 1, "c": 2}, "d": {"e" : {"f": 3}}}')))
        return 23;
    return 0;
}

function test_stringify()
{
    if ("true" !== JSON.stringify(true))
        return 1;
    if ("false" !== JSON.stringify(false))
        return 2;
    if ("null" !== JSON.stringify(null))
        return 3;
    if ("false" !== JSON.stringify({toJSON: function () {return false; }}))
        return 4;
    if ("4" !== JSON.stringify(4))
        return 5;
    if ('"foo"' !== JSON.stringify("foo"))
        return 6;
    if ("4" !== JSON.stringify(new Number(4)))
        return 7;
    if ('"bar"' !== JSON.stringify(new String("bar")))
        return 8;
    if ('"f\\"o\'o\\\\b\\ba\\fr\\nb\\ra\\tz"' !== JSON.stringify("f\"o\'o\\b\ba\fr\nb\ra\tz"))
        return 9;
    if ("[1,2,3]" !== JSON.stringify([1, 2, 3]))
        return 10;
    if ("[\n 1,\n 2,\n 3\n]" !== JSON.stringify([1, 2, 3], null, 1))
        return 11;
    if ("[\n  1,\n  2,\n  3\n]" !== JSON.stringify([1, 2, 3], null, 2))
        return 12;
    if ("[\n  1,\n  2,\n  3\n]" !== JSON.stringify([1, 2, 3], null, new Number(2)))
        return 13;
    if ("[\n^1,\n^2,\n^3\n]" !== JSON.stringify([1, 2, 3], null, "^"))
        return 14;
    if ("[\n^1,\n^2,\n^3\n]" !== JSON.stringify([1, 2, 3], null, new String("^")))
        return 15;
    if ("[\n 1,\n 2,\n [\n  3,\n  [\n   4\n  ],\n  5\n ],\n 6,\n 7\n]" !== JSON.stringify([1, 2, [3, [4], 5], 6, 7], null, 1))
        return 16;
    if ("[]" !== JSON.stringify([], null, 1))
        return 17;
    if ("[1,2,[3,[4],5],6,7]" !== JSON.stringify([1, 2, [3, [4], 5], 6, 7], null))
        return 18;
    if ('["a","ab","abc"]' !== JSON.stringify(["a","ab","abc"]))
        return 19;

    return 0;
}

function test()
{
    var r;

    r = test_parse();
    if (r !== 0)
        return 100 + r;
    r = test_stringify();
    if (r !== 0)
        return 200 + r;

    return 0;
}

// TODO: convert this test to use assertions &
// exceptions instead of return codes 
assert (test() === 0);

