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

function test_lit()
{
    var str = "foo\
        bar bif boop\
        bleep bloop\
        boof";

    // Verify that the multi-line string is properly formed
    if (str.length !== 54)
        return 1;

    return 0;
}

function test_ctor()
{
    if (String(5) != '5')
        return 1;

    if (String('foo') !== 'foo')
        return 2;

    if (String(new String('foo')) !== 'foo')
        return 3;

    return 0;
}

function test_toString()
{
    var s = 'foo';
    var so = new String('foo');

    if (s.toString() !== s)
        return 1;

    if (so.toString() !== s)
        return 2;

    if (so.toString() === so)
        return 3;

    return 0;
}

function test_valueOf()
{
    var s = 'foo';
    var so = new String('foo');

    if (s.toString() !== s)
        return 1;

    if (so.toString() !== s)
        return 2;

    if (so.toString() === so)
        return 3;

    return 0;
}

function test_charCodeAt()
{
    var s = 'foo';

    if (s.charCodeAt(0) !== 102)
        return 1;
    if (s.charCodeAt(1) !== 111)
        return 2;
    if (s.charCodeAt(2) !== 111)
        return 3;

    return 0;
}

function test_charAt()
{
    var s = 'foo';

    if (s.charAt(0) !== 'f')
        return 1;
    if (s.charAt(1) !== 'o')
        return 2;
    if (s.charAt(2) !== 'o')
        return 3;
    if (s.charAt(3) !== '')
        return 4;

    return 0;
}

function test_indexing()
{
    var s = 'foo';

    if (s[0] !== 'f')
        return 1;
    if (s[1] !== 'o')
        return 2;
    if (s[2] !== 'o')
        return 3;
    if (s[3] !== undefined)
        return 4;

    return 0;
}

function test_indexOf()
{
    if ('foo'.indexOf('f') != 0)
        return 1;
    if ('foo'.indexOf('o') != 1)
        return 2;
    if ('foo'.indexOf('oo') != 1)
        return 3;
    if ('foo'.indexOf('a') != -1)
        return 4;

    return 0;
}

function test_lastIndexOf()
{
    if ('foo'.lastIndexOf('f') != 0)
        return 1;
    if ('foo'.lastIndexOf('o') != 2)
        return 2;
    if ('foo'.lastIndexOf('oo') != 1)
        return 3;
    if ('foo'.lastIndexOf('a') != -1)
        return 4;

    return 0;
}

function test_toLowerCase()
{
    if ('FOO'.toLowerCase() != 'foo')
        return 1;
    if ('FoO'.toLowerCase() != 'foo')
        return 2;
    if ('foo'.toLowerCase() != 'foo')
        return 3;

    return 0;
}

function test_toUpperCase()
{
    if ('FOO'.toUpperCase() != 'FOO')
        return 1;
    if ('FoO'.toUpperCase() != 'FOO')
        return 2;
    if ('foo'.toUpperCase() != 'FOO')
        return 3;

    return 0;
}

function test_slice()
{
    if ('foo'.slice(0) !== 'foo')
        return 1;
    if ('foo'.slice(1) !== 'oo')
        return 2;
    if ('foobar'.slice(1,4) !== 'oob')
        return 3;
    if ((new String('foobar')).slice(1,4) !== 'oob')
        return 4;

    return 0;
}

function test_substring()
{
    if ('foo'.substring(0) !== 'foo')
        return 1;
    if ('foo'.substring(1) !== 'oo')
        return 2;
    if ('foobar'.substring(1,4) !== 'oob')
        return 3;

    return 0;
}

function test_substr()
{
    if ('foo'.substr(0) !== 'foo')
        return 1;
    if ('foo'.substr(1, 1) !== 'o')
        return 2;
    if ('foobar'.substr(1,3) !== 'oob')
        return 3;
    if ('foo'.substr(1,5) !== 'oo')
        return 4;

    return 0;
}

function test_concat()
{
    if (''.concat() !== '')
        return 1;

    if ('foo'.concat() !== 'foo')
        return 2;

    if ('foo'.concat('') !== 'foo')
        return 3;

    if ('foo'.concat('bar') !== 'foobar')
        return 4;

    if ('foo'.concat('bar', 'bif') !== 'foobarbif')
        return 5;

    return 0;
}

function test_replace()
{
    if ('foobif'.replace('oo', 'oobar') !== 'foobarbif')
        return 1;

    if ('foobar'.replace(/(.)\1/, '$1') !== 'fobar')
        return 2;

    if ('foobar'.replace(/(.)/g, '$1$1') !== 'ffoooobbaarr')
        return 3;

    if ('foobar foobar'.replace(/\bf/g, "$`") !== 'oobar foobar oobar')
        return 4;
    
    if ('foobar foobar'.replace(/\bf/g, "$'") !== 'oobar foobaroobar oobaroobar')
        return 5;
                        
    return 0;
}

function test_split()
{
    function array_eq(a1, a2)
    {
        if (a1.length !== a2.length)
            return false;

        for (var i = 0; i < a1.length; ++i)
            if (a1[i] !== a2[i])
                return false;

        return true;
    }

    if (!array_eq('foo,bar,bif'.split(','), ['foo','bar','bif']))
        return 1;

    if (!array_eq('foo,bar,bif'.split(',', 0), []))
        return 2;

    if (!array_eq('foo,bar,bif'.split(',', 1), ['foo']))
        return 3;

    if (!array_eq('foo,bar,bif'.split(',', 2), ['foo','bar']))
        return 4;

    if (!array_eq('foo,bar,bif'.split(',', 3), ['foo','bar','bif']))
        return 5;

    if (!array_eq('foo,bar,bif'.split(), ['foo,bar,bif']))
        return 6;

    return 0;
}

function test_trim()
{
    if ('foo'.trim() !== 'foo')
        return 1;

    if (' foo'.trim() !== 'foo')
        return 2;

    if ('   \n  foo \r\n \t  '.trim() !== 'foo')
        return 3;

    if ('   \n  foo bar \r\n \t  '.trim() !== 'foo bar')
        return 4;

    return 0;
}

function test_fromCharCode()
{
    if (String.fromCharCode() != '')
        return 1;

    if (String.fromCharCode(102, 111, 111) != 'foo')
        return 2;

    return 0;
}

function test()
{
    var r = test_lit();
    if (r != 0)
        return 100 + r;

    var r = test_ctor();
    if (r != 0)
        return 200 + r;

    var r = test_toString();
    if (r != 0)
        return 300 + r;

    var r = test_valueOf();
    if (r != 0)
        return 400 + r;

    var r = test_charCodeAt();
    if (r != 0)
        return 500 + r;

    var r = test_charAt();
    if (r != 0)
        return 600 + r;

    var r = test_indexing();
    if (r != 0)
        return 700 + r;

    var r = test_indexOf();
    if (r != 0)
        return 800 + r;

    var r = test_lastIndexOf();
    if (r != 0)
        return 900 + r;

    var r = test_toLowerCase();
    if (r != 0)
        return 1000 + r;

    var r = test_toUpperCase();
    if (r != 0)
        return 1100 + r;

    var r = test_slice();
    if (r != 0)
        return 1200 + r;

    var r = test_substring();
    if (r != 0)
        return 1300 + r;

    var r = test_substr();
    if (r != 0)
        return 1400 + r;

    var r = test_concat();
    if (r != 0)
        return 1500 + r;

    var r = test_replace();
    if (r != 0)
        return 1600 + r;

    var r = test_split();
    if (r != 0)
        return 1700 + r;

    var r = test_trim();
    if (r != 0)
        return 1800 + r;

    var r = test_fromCharCode();
    if (r != 0)
        return 1900 + r;

    return 0;
}

