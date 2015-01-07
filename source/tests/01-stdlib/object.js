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

require('lib/test');

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
    assert (typeof Object.getOwnPropertyDescriptor === 'function');

    var desc = Object.getOwnPropertyDescriptor({}, 'p');
    assert (desc === undefined);

    var o = { p1: 1 };
    var desc = Object.getOwnPropertyDescriptor(o, 'p1');
    assert (desc.value === 1, 'prop desc missing value');
    assert (desc.writable === true);
    assert (desc.enumerable === true);
    assert (desc.configurable === true);

    var o = {};
    Object.defineProperty(o, 'p', { writable:false, configurable:true, value:5 });
    var desc = Object.getOwnPropertyDescriptor(o, 'p');
    assert (desc.value === 5);
    assert (desc.writable === false);
    assert (desc.enumerable === false);
    assert (desc.configurable === true);

    // Getters and setters
    var o = {};
    var getFn = function () {};
    var setFn = function () {};
    Object.defineProperty(o, 'p', { get:getFn, set:setFn });
    var desc = Object.getOwnPropertyDescriptor(o, 'p');
    assert (desc.get === getFn);
    assert (desc.set === setFn);
    assert (desc.writable === false);
    assert (desc.enumerable === false);
    assert (desc.configurable === false);
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

    // Properties are not enumerable by default
    Object.defineProperty(o, 'p', { value: 7 });
    assert (o.p === 7);
    assert (!o.propertyIsEnumerable('p'));

    // Properties are not writable by default
    o.p = 8;
    assert (o.p === 7);
    o.p++;
    assert (o.p === 7);

    // Properties are not configurable by default
    // Changing the value of p should fail
    assertThrows(function () {
        Object.defineProperty(o, 'p', { value: 9, writable:true });
    });

    // Defining a non-enumerable property
    var obj = Object.defineProperty({}, 'k', { value: 3, enumerable:false });
    assert (obj.k === 3);
    assert (!obj.propertyIsEnumerable('k'));

    var obj = Object.defineProperty({}, 'x', { value: true, enumerable:true });
    assert (obj.x === true);
    assert (obj.propertyIsEnumerable('x'));

    // Empty property descriptor
    var obj = Object.defineProperty({}, 'x', {});
    assert ('x' in obj);
    assert (obj.x === undefined);

    // Cannot delete non-configurable properties
    var obj = Object.defineProperty({}, 'p', { value:5 });
    delete obj.p;
    assert (obj.p === 5);

    // Undeleting a property
    var obj = { k:3 }
    delete obj.k;
    Object.defineProperty(obj, 'k', {});
    assert ('k' in obj);
    assert (obj.k === undefined);

    // Getter accessor test
    var obj = Object.defineProperty({}, 'p', { get: function() {return 5;} });
    assert (obj.p === 5);
    obj.p = 7;
    assert (obj.p === 5);

    // Setter accessor test
    var obj = Object.defineProperty({}, 'p', { set: function(v) {this.k=v} });
    obj.p = 5;
    assert (obj.k === 5, 'setter failed');
    obj.p = 7;
    assert (obj.k === 7);
    assert (obj.p === undefined);

    // Can't have both a value and a getter/setter
    assertThrows(function () {
        Object.defineProperty({}, 'p', { value: 9, set:function() {} });
    });
    assertThrows(function () {
        Object.defineProperty({}, 'p', { value: 9, get:function() {} });
    });
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
            p1: { value: 1 },
            p2: { value: 2 }
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
    assert (typeof Object.seal === 'function')

    var o = { p1: 1 };
    Object.seal(o);

    assert (o.hasOwnProperty('p1'))
    assert (o.propertyIsEnumerable('p1'));
    assert (o.p1 === 1);

    var desc = Object.getOwnPropertyDescriptor(o, 'p1');
    assert (desc.writable === true);
    assert (desc.configurable === false);

    // Extension should be prevented
    o.p2 = 1;
    assert (!o.hasOwnProperty('p2'));
}

function test_freeze()
{
    // Test that the method exists
    assert (typeof Object.freeze === 'function')

    var o = { p1: 1 };
    Object.freeze(o);

    assert (o.hasOwnProperty('p1'))
    assert (o.propertyIsEnumerable('p1'));
    assert (o.p1 === 1);

    var desc = Object.getOwnPropertyDescriptor(o, 'p1');
    assert (desc.writable === false);
    assert (desc.configurable === false);

    // Extension should be prevented
    o.p2 = 1;
    assert (!o.hasOwnProperty('p2'));
}

function test_preventExtensions()
{
    // Test that the method exists
    assert (typeof Object.preventExtensions === 'function')

    var o = { p1:1, p2:2, p3:3 };
    Object.preventExtensions(o);

    // Extension prevented
    o.p4 = 4;
    assert (!o.hasOwnProperty('p4'));
    assert (o.p3 === 3);

    // Extension prevented with dynamic key
    o['p' + 4] = 4;
    assert (!o.hasOwnProperty('p4'));
    assert (o.p3 === 3);

    // Deleting last property, can't re-add it
    delete o.p3;
    assert (!o.hasOwnProperty('p3'));
    assert (o.p3 === undefined);

    // Deleting last prop shouldn't make obj re-extensible
    o.p5 = 5;
    assert (!o.hasOwnProperty('p5'));
    o.p4 = 4;
    assert (!o.hasOwnProperty('p4'));
    o.p3 = 3;
    assert (!o.hasOwnProperty('p3'));

    var o = { p1:1, p2:2, p3:3 };
    Object.preventExtensions(o);

    // Setting some attr on last prop shouldn't make obj re-extensile
    Object.defineProperty(o, 'p3', { enumerable:false });
    assert (o.p3 === 3);
    o.p4 = 4;
    assert (!o.hasOwnProperty('p4'));

    // Deleting a property in the middle of obj, can't re-add prop
    delete o.p2;
    assert (!o.hasOwnProperty('p2'));
    o.p2 = 2;
    assert (!o.hasOwnProperty('p2'));

    var o = { p1:1, p2:2, p3:3 };
    Object.preventExtensions(o);

    // Using defineProperty to add a new property
    // should throw a TypeError if not extensible
    assertThrows(function () {
        Object.defineProperty(o, 'p4', { value: 9 });
    });
}

function test_isSealed()
{
    // Test that the method exists
    assert (typeof Object.isSealed === 'function')

    // TODO
}

function test_isFrozen()
{
    // Test that the method exists
    assert (typeof Object.isFrozen === 'function')

    // TODO
}

function test_isExtensible()
{
    // Test that the method exists
    assert (typeof Object.isExtensible === 'function');

    var o1 = {};
    assert (Object.isExtensible(o1));

    var o2 = Object.preventExtensions({});
    assert (!Object.isExtensible(o2));
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
    assert (a.x === 'foo');
    assert (a.z === undefined);
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
    var o = { x:3 };

    // Test that the method exists
    assert (typeof o.propertyIsEnumerable === 'function');

    assert (!o.propertyIsEnumerable(o.propertyIsEnumerable));

    assert (o.propertyIsEnumerable('x'));

    assert (!Object.prototype.propertyIsEnumerable('toString'));
}

function test()
{
    var r = test_ctor();
    if (r != 0)
        return 100 + r;

    var r = test_getPrototypeOf();
    if (r != 0)
        return 200 + r;

    test_getOwnPropertyDescriptor();

    var r = test_getOwnPropertyNames();
    if (r != 0)
        return 400 + r;

    var r = test_create();
    if (r != 0)
        return 500 + r;

    test_defineProperty();

    var r = test_defineProperties();
    if (r != 0)
        return 700 + r;

    test_seal();

    test_freeze();

    test_preventExtensions();

    test_isSealed();

    test_isFrozen();

    test_isExtensible();

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

    test_propertyIsEnumerable();

    return 0;
}

// TODO: convert this test to use assertions &
// exceptions instead of return codes 
var r = test();
assert (r === 0, 'code ' + r);

