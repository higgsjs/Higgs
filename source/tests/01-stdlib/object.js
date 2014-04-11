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

function test_ctor()
{
    var o = {};

    if (typeof Object !== 'function')
        return 1;

    if (typeof o !== 'object')
        return 2;

    if (!(o instanceof Object))
        return 3;

    if (typeof new Object() !== 'object')
        return 4;

    if (typeof Object() !== 'object')
        return 5;

    if (!(Object('foobar') instanceof String))
        return 6;

    return 0;
}

function test_getPrototypeOf()
{
    //Object.getPrototypeOf = function (obj)

    var o = {}

    if (Object.getPrototypeOf(o) !== Object.prototype)
        return 1;

    if (Object.getPrototypeOf(Object.prototype) !== null)
        return 2;

    return 0;
}

function test_getOwnPropertyDescriptor()
{
    // Test that the method exists
    if (!Object.getOwnPropertyDescriptor)
        return 1;

    var o = {p1:1};

    var desc = Object.getOwnPropertyDescriptor(o, 'p1');

    if (desc.value !== 1)
        return 2;

    return 0;
}

function test_getOwnPropertyNames()
{
    var a = {k1:1};
    var b = Object.create(a);
    b.k2 = 2;
    b.k3 = 3;

    var keys = Object.keys(b);

    if (keys.length !== 2)
        return 1;

    if (keys.indexOf('k2') === -1)
        return 2;

    if (keys.indexOf('k3') === -1)
        return 3;

    return 0;
}

function test_create()
{
    //Object.create = function (obj, props)

    var a = {};

    var o = Object.create(a);

    if (Object.getPrototypeOf(o) !== a)
        return 1;

    return 0;
}

function test_defineProperty()
{
    //Object.defineProperty = function (obj, prop, attribs)

    var o = {};

    Object.defineProperty(o, 'p', { value: 7 });

    if (o.p !== 7)
        return 1;

    var obj = Object.defineProperty({}, 'x', { value: true });
    if (obj.x !== true)
        return 2;

    return 0;
}

function test_defineProperties()
{
    // Test that the method exists
    if (!Object.defineProperties)
        return 1;

    var o = {};

    var o1 = Object.defineProperties(
        o, 
        {
            p1: { value: 1},
            p2: { value: 2}
        }
    );

    if (o.p1 !== 1)
        return 2;

    if (o.p2 !== 2)
        return 3;

    if (o1.p1 !== 1)
        return 3;

    return 0;
}

function test_seal()
{
    // Test that the method exists
    if (!Object.seal)
        return 1;

    return 0;
}

function test_freeze()
{
    // Test that the method exists
    if (!Object.freeze)
        return 1;

    return 0;
}

function test_preventExtensions()
{
    // Test that the method exists
    if (!Object.preventExtensions)
        return 1;

    return 0;
}

function test_isSealed()
{
    // Test that the method exists
    if (!Object.isSealed)
        return 1;

    return 0;
}

function test_isFrozen()
{
    // Test that the method exists
    if (!Object.isFrozen)
        return 1;

    return 0;
}

function test_isExtensible()
{
    // Test that the method exists
    if (!Object.isExtensible)
        return 1;

    return 0;
}

function test_keys()
{
    var a = {k1:1};
    var b = Object.create(a);
    b.k2 = 2;
    b.k3 = 3;

    var keys = Object.keys(b);
    assert (keys.length === 2)
    assert (keys.indexOf('k2') !== -1)
    assert (keys.indexOf('k3') !== -1)

    var a = {length:3};
    var keys = Object.keys(a);
    assert (keys.length === 1)

    var a = [];
    var keys = Object.keys(a);
    assert (keys.indexOf('length') === -1)

    // Object with no prototype
    var a = Object.create(null);
    a.x = 'foo';
    a.y = 'bar';
    var keys = Object.keys(a);
    assert (keys.length === 2)
}

function test_toString()
{
    //Object.prototype.toString = function ()

    var o = {};

    if (typeof o.toString() !== 'string')
        return 1;

    return 0;
}

function test_toLocaleString()
{
    var o = {};

    if (typeof o.toLocaleString() !== 'string')
        return 1;

    return 0;
}

function test_valueOf()
{
    //Object.prototype.valueOf = function ()

    var o = {};

    if (o.valueOf() !== o)
        return 1;

    return 0;
}

function test_hasOwnProperty()
{
    //Object.prototype.hasOwnProperty = function (prop)

    var a = { va: 9 };

    var b = Object.create(a);

    b.vb = 10;

    if (b.hasOwnProperty('vb') !== true)
        return 1;

    if (b.hasOwnProperty('va') !== false)
        return 2;

    if (a.hasOwnProperty('va') !== true)
        return 3;

    return 0;
}

function test_isPrototypeOf()
{
    //Object.prototype.isPrototypeOf = function (obj)

    var a = {};

    var o = Object.create(a);

    if (a.isPrototypeOf(o) !== true)
        return 1;

    if (Object.prototype.isPrototypeOf(a) !== true)
        return 2;

    return 0;
}

function test_propertyIsEnumerable()
{
    var o = {};

    // Test that the method exists
    if (!o.propertyIsEnumerable)
        return 1;

    return 0;
}

function test()
{
    var r = test_ctor();
    if (r != 0)
        return 100 + r;

    var r = test_getPrototypeOf();
    if (r != 0)
        return 200 + r;

    var r = test_getOwnPropertyDescriptor();
    if (r != 0)
        return 300 + r;

    var r = test_getOwnPropertyNames();
    if (r != 0)
        return 400 + r;

    var r = test_create();
    if (r != 0)
        return 500 + r;

    var r = test_defineProperty();
    if (r != 0)
        return 600 + r;

    var r = test_defineProperties();
    if (r != 0)
        return 700 + r;

    var r = test_seal();
    if (r != 0)
        return 800 + r;

    var r = test_freeze();
    if (r != 0)
        return 900 + r;

    var r = test_preventExtensions();
    if (r != 0)
        return 1000 + r;

    var r = test_isSealed();
    if (r != 0)
        return 1100 + r;

    var r = test_isFrozen();
    if (r != 0)
        return 1200 + r;

    var r = test_isExtensible();
    if (r != 0)
        return 1300 + r;

    test_keys();

    var r = test_toString();
    if (r != 0)
        return 1500 + r;

    var r = test_toLocaleString();
    if (r != 0)
        return 1600 + r;

    var r = test_valueOf();
    if (r != 0)
        return 1700 + r;

    var r = test_hasOwnProperty();
    if (r != 0)
        return 1800 + r;

    var r = test_isPrototypeOf();
    if (r != 0)
        return 1900 + r;

    var r = test_propertyIsEnumerable();
    if (r != 0)
        return 2000 + r;

    return 0;
}

// TODO: convert this test to use assertions &
// exceptions instead of return codes 
var r = test();
assert (r === 0, 'code ' + r);

