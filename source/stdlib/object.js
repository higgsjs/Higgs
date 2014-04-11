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
 *  Copyright (c) 2012-2014, Universite de Montreal
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
@class 15.2.2 The Object Constructor
new Object([value])
Object([value])
*/
function Object(value)
{
    if (value !== undefined && value !== null)
    {
        switch (typeof value)
        {
            case 'object':
            case 'function':
            return value;

            case 'boolean':
            return new Boolean(value);

            case 'string':
            return new String(value);

            case 'number':
            return new Number(value);
        }

        error('invalid value passed to Object constructor');
    }

    return {};
}

// Set the object prototype object
Object.prototype = $ir_get_obj_proto();

Object.length = 1;

/**
15.2.4.1 Object.prototype.constructor
*/
Object.prototype.constructor = Object;

//-----------------------------------------------------------------------------

/**
15.2.3.2 Get the prototype of an object
*/
Object.getPrototypeOf = function (obj)
{
    assert (
        $rt_valIsObj(obj),
        'non-object value in getPrototypeOf'
    );

    var proto = $rt_getProto(obj);

    return proto;
};

/**
15.2.3.3 Get a descriptor for an object's property
FIXME: for now, no property attributes
*/
Object.getOwnPropertyDescriptor = function (O, P)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in getOwnPropertyDescriptor');

    name = String(P);

    return { writable:true, enumerable:true, configurable: true, value: O[name] };
};

/**
15.2.3.4 Get the named own properties of an object (excludes the prototype chain)
*/
Object.getOwnPropertyNames = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in getOwnPropertyNames');

    var propNames = [];

    for (k in O)
    {
        if (O.hasOwnProperty(k) === true)
            propNames.push(k);
    }

    return propNames;
};

/**
15.2.3.5 Object.create ( O [, Properties] )
*/
Object.create = function (O, Properties)
{
    if ($rt_valIsObj(O) === false && O !== null)
        throw TypeError('can only create object from object or null prototype');

    var newObj = $rt_newObj($ir_make_map(null, 0), O);

    if (Properties !== undefined)
        Object.defineProperties(newObj, Properties);

    return newObj;
};

/**
15.2.3.6 Object.defineProperty ( O, P, Attributes )
FIXME: for now, we ignore most attributes
*/
Object.defineProperty = function (obj, prop, attribs)
{
    assert (
        $rt_valIsObj(obj),
        'non-object value in defineProperty'
    );

    if (attribs.hasOwnProperty('value'))
        obj[prop] = attribs.value;

    return obj;
};

/**
15.2.3.7 Object.defineProperties ( O, Properties )
*/
Object.defineProperties = function (O, Properties)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in defineProperties');

    for (name in Properties)
    {
        Object.defineProperty(O, name, Properties[name]);
    }

    return O;
};

/**
15.2.3.8 Object.seal ( O )
FIXME: noop function for now
*/
Object.seal = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in seal');

    return O;
};

/**
15.2.3.9 Object.freeze ( O )
FIXME: noop function for now
*/
Object.freeze = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in freeze');

    return O;
};

/**
15.2.3.10 Object.preventExtensions ( O )
FIXME: noop function for now
*/
Object.preventExtensions = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in preventExtensions');

    return O;
};

/**
15.2.3.11 Object.isSealed ( O )
FIXME: noop function for now
*/
Object.isSealed = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in isSealed');

    return false; 
};

/**
15.2.3.12 Object.isFrozen ( O )
FIXME: for now, all objects are extensible
*/
Object.isFrozen = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in isFrozen');

    return false;
};

/**
15.2.3.13 Object.isExtensible ( O )
FIXME: for now, all objects are extensible
*/
Object.isExtensible = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in isExtensible');

    return true;
};

/**
15.2.3.14 Object.keys ( O )
*/
Object.keys = function (O)
{
    if ($rt_valIsObj(O) === false)
        throw TypeError('invalid object in keys');

    var propNames = [];

    for (var k in O)
    {
        if ($rt_hasOwnProp(O, k) === true)
            propNames.push(k);
    }

    return propNames;
};

/**
15.2.4.2 Default object to string conversion function
*/
Object.prototype.toString = function ()
{
    return "object";
};

/**
15.2.4.3 Object to string conversion function with locale handling
*/
Object.prototype.toLocaleString = function ()
{
    return this.toString();
};

/**
15.2.4.4 Object.prototype.valueOf ()
*/
Object.prototype.valueOf = function ()
{
    return this;
};

/**
15.2.4.5 Test that an object has a given property
*/
Object.prototype.hasOwnProperty = function (prop)
{
    return $rt_hasOwnProp(this, prop);
};

/**
15.2.4.6 Test that an object is the prototype of another
*/
Object.prototype.isPrototypeOf = function (O)
{
    var proto = Object.getPrototypeOf(O);

    return (this === proto);
};

/**
15.2.4.7 Object.prototype.propertyIsEnumerable (V)
FIXME: for now, all properties are enumerable
*/
Object.prototype.propertyIsEnumerable = function (V)
{
    if (this.hasOwnProperty(V) === false)
        return false;

    return true;
};

