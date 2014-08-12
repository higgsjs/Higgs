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

    var proto = $ir_shape_get_proto(obj);

    return proto;
};

/**
15.2.3.3 Get a descriptor for an object's property
*/
Object.getOwnPropertyDescriptor = function (obj, prop)
{
    if ($rt_valIsObj(obj) === false)
        throw TypeError('invalid object in getOwnPropertyDescriptor');

    prop = $rt_toString(prop);

    // Get the defining shape for the property
    var defShape = $ir_shape_get_def(obj, prop);

    var desc = {};

    // Extract the current property attributes
    var attrs = $ir_ne_rawptr(defShape, $nullptr)? $ir_shape_get_attrs(defShape):$rt_ATTR_DEFAULT;
    desc.writable = !!(attrs & $rt_ATTR_WRITABLE);
    desc.enumerable = !!(attrs & $rt_ATTR_ENUMERABLE);
    desc.configurable = !!(attrs & $rt_ATTR_CONFIGURABLE);

    // Get the property value
    var propVal = $ir_shape_get_prop(obj, defShape);

    // If this property is a getter-setter
    if ($ir_shape_is_getset(defShape))
    {
        desc.get = propVal.get;
        desc.set = propVal.set;
    }
    else
    {
        desc.value = propVal;
    }

    return desc;
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
Object.create = function (proto, properties)
{
    if ($rt_valIsObj(proto) === false && proto !== null)
        throw TypeError('can only create object from object or null prototype');

    var newObj = $rt_newObj(proto);

    if (properties !== undefined)
        Object.defineProperties(newObj, properties);

    return newObj;
};

/**
15.2.3.6 Object.defineProperty ( O, P, Attributes )
*/
Object.defineProperty = function (obj, prop, attribs)
{
    if (!$rt_valIsObj(obj))
        throw TypeError('non-object value in defineProperty');

    if (!$rt_valIsObj(attribs))
        throw TypeError('property descriptor must be an object');

    if ((attribs.hasOwnProperty('value')) &&
        (attribs.hasOwnProperty('get') || attribs.hasOwnProperty('set')))
        throw TypeError('property cannot have both a value and accessors');

    prop = $rt_toString(prop);

    // Test if accessors were specified
    var isGS = attribs.hasOwnProperty('get') || attribs.hasOwnProperty('set');

    // If a value is specified, try to set it,
    // this will do nothing if writable is false
    if (attribs.hasOwnProperty('value'))
    {
        obj[prop] = attribs.value;
    }

    // Otherwise, if accessors are specified
    else if (isGS)
    {
        var defFn = function () {};
        var get = attribs.hasOwnProperty('get')? attribs.get:defFn;
        var set = attribs.hasOwnProperty('set')? attribs.set:defFn;

        if (typeof get !== 'function' || typeof set !== 'function')
            throw TypeError('accessors must be functions');

        // Create a property descriptor pair
        obj[prop] = { get:get, set:set };
    }

    // Extract the current property attributes
    var defShape = $ir_shape_get_def(obj, prop);
    var oldAttrs = $ir_ne_rawptr(defShape, $nullptr)? $ir_shape_get_attrs(defShape):$rt_ATTR_DEFAULT;
    var oldWR = !!(oldAttrs & $rt_ATTR_WRITABLE);
    var oldEN = !!(oldAttrs & $rt_ATTR_ENUMERABLE);
    var oldCF = !!(oldAttrs & $rt_ATTR_CONFIGURABLE);

    // Assemble the new property attributes
    var newWR = attribs.hasOwnProperty('writable')? !!attribs.writable:false;
    var newEN = attribs.hasOwnProperty('enumerable')? !!attribs.enumerable:false;
    var newCF = attribs.hasOwnProperty('configurable')? !!attribs.configurable:false;
    var newAttrs = (
        (newWR? $rt_ATTR_WRITABLE:0) |
        (newEN? $rt_ATTR_ENUMERABLE:0) |
        (newCF? $rt_ATTR_CONFIGURABLE:0) |
        (isGS? $rt_ATTR_GETSET:0)
    );

    // If the property is not currently configurable
    if (oldCF === false)
    {
        if (newEN != oldEN)
            throw TypeError('cannot unset enumerable flag when configurable is false');
        if (newWR != oldWR)
            throw TypeError('cannot unset writable flag when configurable is false');
        if (newCF != oldCF)
            throw TypeError('cannot unset configurable flag');
    }
    else
    {
        // Set the new property attributes
        $ir_shape_set_attrs(obj, prop, newAttrs);
    }

    // Return the object
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
*/
Object.prototype.propertyIsEnumerable = function (V)
{
    if (this.hasOwnProperty(V) === false)
        return false;

    var defShape = $ir_shape_get_def(this, V);

    if ($ir_eq_rawptr(defShape, $nullptr))
        return false;

    var attrs = $ir_shape_get_attrs(defShape);
    return !!(attrs & $rt_ATTR_ENUMERABLE);
};

// Make the Object.prototype properties non-enumerable
for (p in Object.prototype)
{
    Object.defineProperty(
        Object.prototype,
        p,
        {enumerable:false, writable:true, configurable:true }
    );
}

