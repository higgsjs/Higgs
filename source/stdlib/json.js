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
Implementation of ECMAScript 5 JSON serialization/deserialization.

@author
Maxime Chevalier-Boisvert, Olivier Matz

@copyright
Copyright (c) 2011 Tachyon Javascript Engine, All Rights Reserved
*/

// TODO: parse float number
// TODO: throw SyntaxError where applicable
// TODO: properties attributes

function JSON () {}

JSON.toString = function ()
{
    return "[object JSON]";
}

/**
15.12.2 JSON.parse(text, [, reviver])
*/
JSON.parse = function (
    text,
    reviver
)
{
    var index = 0;

    // Return current char code, or undefined if at the end of input.
    function current ()
    {
        if (index < text.length)
            return text.charCodeAt(index);
        else
            return undefined;
    }

    // Skip <n> characters from input.
    function consume (
        n
    )
    {
        index += (n === undefined ? 1 : n);
    }

    // Set input to the next non whitespace character.
    function skipWhiteSpace ()
    {
        var c;

        while (true)
        {
            c = current();

            if (c === 9 || c === 10 || c === 32 || c === 13)
                consume();
            else
                return;
        }
    }

    // Parse a JSON input and return its value.
    function parseJSON ()
    {
        skipWhiteSpace();

        var c = current();

        if (c === 123) // '{'
            return parseObject();
        else if (c === 91) // '['
            return parseArray();
        else if (c === 34) // '"'
            return parseString();
        else if (c === 110) // 'n'
            return parseNull();
        else if (c === 116) // 't'
            return parseTrue();
        else if (c === 102) // 'f'
            return parseFalse();
        else if ((c >= 48 && c <= 57) || c === 45) // 0-9 | '-'
            return parseNumber();
        else
            // FIXME: throw SyntaxError
            return undefined;
    }

    function parseObject ()
    {
        var o = {};

        // Consume opening {
        consume();
    
        skipWhiteSpace();
        while (current() !== 125) // '}'
        {
            skipWhiteSpace();

            if (current() !== 34) // '"'
                // FIXME: throw SyntaxError
                return undefined;
            
            var propName = parseString();

            skipWhiteSpace();

            if (current() !== 58) // ':'
                // FIXME: throw SyntaxError
                return undefined;
            else
                consume();

            skipWhiteSpace();

            var propValue = parseJSON();

            if (propValue === undefined)
                // FIXME: throw SyntaxError
                return undefined;

            o[propName] = propValue;

            skipWhiteSpace();

            if (current() === 44) // ','
                consume();
            else if (current() !== 125) // '}'
                // FIXME: throw SyntaxError
                return undefined;
        }

        // Consume closing }
        consume();
        return o;
    }

    function parseArray ()
    {
        var a = [];

        // Consume opening [
        consume();
    
        skipWhiteSpace();

        while (current() !== 93) // ']'
        {
            skipWhiteSpace();

            var value = parseJSON();

            if (value === undefined)
                // FIXME: throw SyntaxError
                return undefined;

            a.push(value);

            skipWhiteSpace();

            if (current() === 44) // ','
                consume();
            else if (current() !== 93) // ']'
                // FIXME: throw SyntaxError
                return undefined;
        }
        
        // Consume closing ]
        consume();
        return a;
    }

    function parseString ()
    {
        var parts = [], j = index + 1;

        // Consume opening "
        consume();

        while (true)
        {
            var c = current(); 

            if (c === 34) // '"'
            {
                consume();
                break;
            }

            if (c === 92) // '\'
            {
                // Parse escape sequence
                if (index > j)
                    parts.push(text.substring(j, index));

                consume();

                switch (current())
                {
                    case 34: // '\'
                    parts.push("\"");
                    break;

                    case 47: // '/'
                    parts.push("\/");
                    break;

                    case 92: // '\'
                    parts.push("\\");
                    break;

                    case 98: // 'b'
                    parts.push("\b");
                    break;

                    case 110: // 'n'
                    parts.push("\n");
                    break;

                    case 114: // 'r'
                    parts.push("\r");
                    break;

                    case 116: // 't'
                    parts.push("\t");
                    break;

                    default:
                    // FIXME: throw SyntaxError
                    return undefined;
                }

                consume();
                j = index;
            }
            else
            {
                consume();
            }
        }

        if (index > j)
            parts.push(text.substring(j, index - 1));

        return parts.join("");
    }

    function parseTrue ()
    {
        var str = "true";

        for (var i = 0; i < str.length; ++i)
            if (current() !== str.charCodeAt(i))
                return undefined;
            else
                consume();
        return true;
    }

    function parseFalse ()
    {
        var str = "false";

        for (var i = 0; i < str.length; ++i)
            if (current() !== str.charCodeAt(i))
                return undefined;
            else
                consume();
        return false;
    }

    function parseNull ()
    {
        var str = "null";

        for (var i = 0; i < str.length; ++i)
            if (current() !== str.charCodeAt(i))
                return undefined;
            else
                consume();
        return null;
    }

    function isDigit (c) { return (c >= 48 && c <= 57); }

    function parseNumber ()
    {
        var n = 0;
        var positive = true;

        if (current() === 45) // '-'
        {
            positive = false;
            consume();
        }

        while (isDigit(current()))
        {
            n = (n * 10) + current() - 48;
            consume();
        }

        if (current() === 46) // '.'
        {
            consume();

            // Parse fraction
            while (isDigit(current()))
                consume();
        }

        if (current() === 69 || current() === 101) // 'e' | 'E'
        {
            consume();
            
            // Parse exponent
            while (isDigit(current()))
                consume();
        }

        return positive ? n : -n;
    }

    function walk (
        holder,
        name
    )
    {
        var value;
        if (name === null)
            value = holder;
        else
            value = holder[name];

        if ((typeof value) === "object")
        {
            if (value instanceof Array)
            {
                for (var i = 0; i < value.length; ++i)
                {
                    var elt = walk(value, i.toString());

                    if (elt === undefined)
                        // FIXME: Delete a value in an array is not currently supported.
                        // delete value[i.toString()];
                        value[i.toString()] = undefined;
                }
            }
            else
            {
                for (prop in value)
                {
                    var elt = walk(value, prop);

                    if (elt === undefined)
                        delete value[prop];
                }
            }
        }

        return reviver.call(holder, name, value);
    }

    var r = parseJSON();
    if (reviver !== undefined)
        walk(r, null);
    return r;
}

/**
15.12.3 JSON.stringify(value, [, replace [, space ]])
*/
JSON.stringify = function (
    value,
    replacer,
    space
)
{
    // Holds references to stringified object to avoid cyclic evaluation.
    var objStack = [];
    var replacerFunction;
    var propertyList;
    var espace;

    if (typeof replacer === "function")
        replacerFunction = replacer;

    if (replacer instanceof Array)
    {
        propertyList = [];

        for (var i = 0; i < replacer.length; ++i)
        {
            var p = replacer[i].toString();

            if (value[p] !== undefined)
                propertyList.push(p);
        }
    }

    if (space !== undefined)
    {
        if (typeof space === "number" || space instanceof Number)
        {
            var espaceParts = [];
            for (var i = 0; i < space; ++i)
                espaceParts.push(" ");
            espace = espaceParts.join("");
        } else if (typeof space === "string" || space instanceof String) {
            if (space.length > 0)
            {
                if (space.length <= 10)
                    espace = space.toString();
                else
                    espace = space.substring(0, 10);
            }
        }
    }

    function toJSON (
        key,
        holder,
        depth
    )
    {
        var value;

        if (key === "")
            value = holder;
        else
            value = holder[key];

        if (value !== null && 
            value !== undefined && 
            typeof value.toJSON === "function")
           value = value.toJSON(); 

        if (replacerFunction !== undefined)
            value = replacerFunction.call(holder, key, value);

        if (value instanceof Number)
            value = value.valueOf();
        else if (value instanceof String)
            value = value.valueOf();
        else if (value instanceof Boolean)
            value = value.valueOf();

        if (value === null)
            return "null";
        else if (value === false)
            return "false";
        else if (value === true)
            return "true";

        if (typeof value === "string")
            return quote(value);

        if (typeof value === "number")
            // TODO: return "null" if value is not finite.
            return value.toString();

        if (typeof value === "object")
        {
            // If value is already in objStack, a cyclic object is detected.
            for (var i = 0; i < objStack.length; ++i)
                if (objStack[i] === value)
                    // FIXME: throw SyntaxError
                    return undefined;

            objStack.push(value);

            if (value instanceof Array)
                return arrayToJSON(value, depth);

            return objectToJSON(value, depth);
        }
        return undefined;
    }

    function objectToJSON (
        o,
        depth
    )
    {
        if (o === null)
            return 'null';

        var keys;

        if (propertyList === undefined)
            keys = Object.keys(o);
        else
            keys = propertyList;

        if (keys.length === 0)
            return "{}";

        var parts = [];

        if (espace === undefined)
        {
            parts.push("{");

            for (var i = 0; i < keys.length; ++i)
            {
                var strp = toJSON(keys[i], o, depth + 1);

                if (strp !== undefined)
                {
                    parts.push(quote(keys[i]));        
                    parts.push(":");
                    parts.push(strp);
                    parts.push(",");
                }
            }

            if (parts.length > 1)
                parts.pop();
            parts.push("}");
        }
        else
        {
            parts.push("{\n");

            for (var i = 0; i < keys.length; ++i)
            {
                var strp = toJSON(keys[i], o, depth + 1);

                if (strp !== undefined)
                {
                    for (var j = 0; j < depth; ++j)
                        parts.push(espace);

                    parts.push(quote(keys[i]));        
                    parts.push(": ");
                    parts.push(strp);
                    parts.push(",\n");
                }
            }

            if (parts.length > 1)
                parts.pop();

            parts.push("\n");
            for (var j = 0; j < depth - 1; ++j)
                parts.push(espace);
            parts.push("}");
        }

        return parts.join("");
    }

    function arrayToJSON (
        a,
        depth
    )
    {
        var parts = [];

        if (a.length === 0)
            return "[]";

        if (espace === undefined)
        {
            parts.push("[");

            for (var i = 0; i < a.length; ++i)
            {
                var strp = toJSON(i.toString(), a, depth + 1);

                parts.push(strp);
                parts.push(",");
            }

            if (a.length > 0)
                parts.pop();

            parts.push("]");
        }
        else
        {
            parts.push("[\n");

            for (var i = 0; i < a.length; ++i)
            {
                var strp = toJSON(i.toString(), a, depth + 1);

                for (var j = 0; j < depth; ++j)
                    parts.push(espace);
                parts.push(strp);
                parts.push(",\n");
            }

            if (a.length > 0)
                parts.pop();

            parts.push("\n");
            for (var j = 0; j < depth - 1; ++j)
                parts.push(espace);
            parts.push("]");
        }

        return parts.join("");
    }

    function quote (
        s
    )
    {
        // TODO: Control sequence escaping.
        var parts = ["\""];

        var i = 0, j = 0;
        for (; i < s.length; ++i)
        {
            var c = s.charCodeAt(i);
            var escapedSeq = undefined;

            switch (c)
            {
                case 34: // '"'
                // Escape double quote character.
                escapedSeq = "\\\"";
                break;

                case 92: // '\'
                // Escape backslash character.
                escapedSeq = "\\\\";
                break;

                case 8: // '\b'
                // Escape backspace character.
                escapedSeq = "\\b";
                break;

                case 12: // '\f'
                // Escape formfeed character.
                escapedSeq = "\\f";
                break;

                case 10: // '\n'
                // Escape linefeed character.
                escapedSeq = "\\n";
                break;

                case 13: // '\r'
                // Escape carriage return character.
                escapedSeq = "\\r";
                break;

                case 9: // '\t'
                // Escape tab character.
                escapedSeq = "\\t";
                break;
            }

            if (escapedSeq !== undefined)
            {
                if (j < i)
                    parts.push(s.substring(j, i));

                parts.push(escapedSeq);
                j = i + 1;
            }
        }

        if (j < i)
            parts.push(s.substring(j, i));
        parts.push("\"");

        return parts.join("");
    }

    return toJSON("", value, 1);
}

