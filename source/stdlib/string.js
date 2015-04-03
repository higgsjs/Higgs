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
 *  Copyright (c) 2011-2015, Universite de Montreal
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
@class 15.5.2 String constructor
new String(value)
String(value)
*/
function String(value)
{
    // Convert the argument value to a string
    var strVal = ($argc > 0)? $rt_toString(value):'';

    // If this is not a constructor call (new String)
    if ($rt_isGlobalObj(this))
    {
        // Return the string value
        return strVal;
    }
    else
    {
        // Create indexes
        for (var i = 0; i < strVal.length; i++)
        {
            Object.defineProperty(this, i,
            {
                enumerable: true,
                value: strVal[i],
            });
        }

        // Store the value in the new object
        // Value is read-only and not enumerable
        Object.defineProperty(this, "value",
        {
            value: strVal,
        });

        // Set length property.
        Object.defineProperty(this, "length",
        {
            value: strVal.length,
        });
    }
}

// Set the string prototype object
String.prototype = $ir_get_str_proto();

//-----------------------------------------------------------------------------

/**
Internal string functions
*/

function string_internal_toCharCodeArray(x)
{
    var s = x.toString();

    var a = [];
    a.length = s.length;

    for (var i = 0; i < s.length; i++)
        a[i] = $rt_str_get_data(s, i);

    return a;
}

function string_internal_fromCharCodeArray(a)
{
    // Get the array length
    var len = $rt_getArrLen(a);

    // Allocate a string object
    var strObj = $rt_str_alloc(len);

    // Copy the data into the string
    for (var i = 0; i < len; ++i)
        $rt_str_set_data(strObj, i, a[i]);

    // Attempt to find the string in the string table
    return $ir_get_str(strObj);
}

function string_internal_isWhiteSpace(c)
{
    return (c >= 9 && c <= 13) || (c === 32) ||
           (c === 160) || (c >= 8192 && c <= 8202) || (c === 8232) ||
           (c === 8233) || (c === 8239) || (c === 8287) ||
           (c === 12288) || (c === 65279);
}

// Convert a code point into UTF-16 code units (surrogates).
function string_internal_utf16encoding(cp)
{
    assert(cp >= 0 && cp <= 0x10FFFF);

    if (cp < 65535) return [cp];

    var cu1 = Math.floor((cp - 65536) / 1024) + 0xD800;
    var cu2 = ((cp - 65536) % 1024) + 0xDC00;

    return [cu1, cu2];
}

// Convert UTF-8 code units (surrogates) into a code point.
function string_internal_utf16decode(lead, trail)
{
    assert(0xD800 <= lead && lead <= 0xDBFF);
    assert(0xDC00 <= trail && trail <= 0xDFFF);
    return (lead - 0xD800) * 1024 + (trail - 0xDC00) + 0x10000;
}

/// Preallocated character strings for 8-bit char codes
$rt_char_str_table = (function ()
{
    var len = 256;
    var table = $rt_arrtbl_alloc(len);

    for (var c = 0; c < len; c++)
    {
        var str = $rt_str_alloc(1);
        $rt_str_set_data(str, 0, c);
        str = $ir_get_str(str);

        $rt_arrtbl_set_word(table, c, $ir_get_word(str))
        $rt_arrtbl_set_tag(table, c, $ir_get_tag(str))
    }

    return table;
})();

//-----------------------------------------------------------------------------

/**
15.5.3.2 String.fromCharCode([char0 [, char1 [, ... ]]])
*/
function string_fromCharCode(c)
{
    if ($ir_eq_i32($argc, 1))
    {
        // If this is a floating-point number safely convertible to an
        // integer and within the character table range
        if ($ir_is_float64(c) && $ir_ge_f64(c, 0.0) && $ir_lt_f64(c, 256.0))
        {
            c = $ir_f64_to_i32(c);

            return $ir_make_value(
                $rt_arrtbl_get_word($rt_char_str_table, c),
                $rt_arrtbl_get_tag($rt_char_str_table, c)
            );
        }

        // If this is a an integer within the character table range
        if ($ir_is_int32(c) && $ir_ge_i32(c, 0) && $ir_lt_i32(c, 256))
        {
            return $ir_make_value(
                $rt_arrtbl_get_word($rt_char_str_table, c),
                $rt_arrtbl_get_tag($rt_char_str_table, c)
            );
        }
    }

    var str = $rt_str_alloc($argc);

    // TODO: use toUint32 and cap to 0xFFFF, parseInt is dog slow!
    for (var i = 0; i < $argc; ++i)
        $rt_str_set_data(str, i, parseInt($ir_get_arg(i)));

    return $ir_get_str(str);
}

/**
https://people.mozilla.org/~jorendorff/es6-draft.html#sec-string.fromcodepoint (21.1.2.2)
*/
function string_fromCodePoint()
{
    var push = Array.prototype.push;
    var fromCharCode = String.fromCharCode;

    var codePoints = arguments;
    var length = codePoints.length;
    var elements = [];
    var nextIndex = 0;

    while (nextIndex < length)
    {
        var next = codePoints[nextIndex];
        var nextCP = $rt_toNumber(next);

        if (!Object.is(nextCP, $rt_toInteger(nextCP)))
            throw RangeError("Code point cannot be a floating point");

        if (nextCP < 0 || nextCP > 0x10FFFF)
            throw RangeError("Code point " + next + " is not valid");

        push.apply(elements, string_internal_utf16encoding(nextCP));
        nextIndex++;
    }

    return elements.length === 0 ? '' : fromCharCode.apply(null, elements);
}

/**
15.5.4.2 String.prototype.toString()
*/
function string_toString()
{
    if ($ir_is_string(this))
        return this;

    if ($ir_is_rope(this))
        return $rt_ropeToStr(this);

    if (this instanceof String)
        return this.value;

    throw TypeError('unexpected type in String.prototype.toString');
}

/**
15.5.4.3 String.prototype.valueOf()
*/
function string_valueOf()
{
    if ($ir_is_string(this))
        return this;

    if ($ir_is_rope(this))
        return $rt_ropeToStr(this);

    if (this instanceof String)
        return this.value;

    return this;
}

/**
15.5.4.4 String.prototype.charAt(pos)
*/
function string_charAt(pos)
{
    if ($ir_is_string(this) &&
        $ir_is_int32(pos) &&
        $ir_ge_i32(pos, 0) &&
        $ir_lt_i32(pos, $rt_str_get_len(this)))
    {
        var ch = $rt_str_get_data(this, pos);
        var str = $rt_str_alloc(1);
        $rt_str_set_data(str, 0, ch);
        return $ir_get_str(str);
    }

    var source = this.toString();
    var len = $rt_str_get_len(source);

    if (pos < 0 || pos >= len)
    {
        return '';
    }

    var ch = source.charCodeAt(pos);
    var str = $rt_str_alloc(1);
    $rt_str_set_data(str, 0, ch);
    return $ir_get_str(str);
}

/**
15.5.4.5 String.prototype.charCodeAt(pos)
*/
function string_charCodeAt(pos)
{
    if ($ir_is_int32(pos) && $ir_ge_i32(pos, 0))
    {
        if ($ir_is_string(this) && $ir_lt_i32(pos, $rt_str_get_len(this)))
            return $rt_str_get_data(this, pos);

        if ($ir_is_rope(this) && $ir_lt_i32(pos, $rt_rope_get_len(this)))
            return $rt_str_get_data($rt_ropeToStr(this), pos);
    }

    var source = this.toString();
    var len = $rt_str_get_len(source);

    if (pos >= 0 && pos < len)
    {
        if ($ir_is_int32(pos) == false)
            pos = $rt_toUint32(pos);

        return $rt_str_get_data(source, pos);
    }

    return NaN;
}

/**
https://people.mozilla.org/~jorendorff/es6-draft.html#sec-string.prototype.codepointat
*/
function string_codePointAt(pos)
{
    if (this === null || this === undefined)
        throw new TypeError("this cannot be null or undefined");

    var src = $rt_toString(this);
    var position = $rt_toInteger(pos);
    var size = src.length;

    if (position < 0 || position >= size) return undefined;

    var first = src.charCodeAt(position);

    if (first < 0xD800 || first > 0xDBFF || (position + 1) === size) return first;

    var second = src.charCodeAt(position + 1);

    if (second < 0xDC00 || second > 0xDFFF) return first;

    return string_internal_utf16decode(first, second);
}

/**
15.5.4.6 String.prototype.concat([string1 [, string2 [, ... ]]])
*/
function string_concat()
{
    var outStr = this;

    // Use the += operator to do concatenation lazily using ropes
    for (var i = 0; i < $argc; ++i)
        outStr += $ir_get_arg(i);

    return outStr;
}

/**
https://people.mozilla.org/~jorendorff/es6-draft.html#sec-string.prototype.endswith (21.1.3.6)
*/
function string_endsWith(searchString, endPosition)
{
    if (this === null || this === undefined)
        throw new TypeError("this cannot be null or undefined");

    if (searchString instanceof RegExp)
        throw new TypeError("searchString cannot be a RegExp");

    var src = $rt_toString(this);
    var searchStr = $rt_toString(searchString);
    var len = src.length;
    var pos = endPosition === undefined ? len : $rt_toInteger(endPosition);
    var end = Math.min(Math.max(pos, 0), len);
    var searchLength = searchStr.length;

    var start = end - searchLength;
    if (start < 0)
        return false;

    return src.substr(start, searchLength) === searchStr;
}

/**
https://people.mozilla.org/~jorendorff/es6-draft.html#sec-string.prototype.includes (21.1.3.7)
*/
function string_includes(searchString, position)
{
    if (this === null || this === undefined)
        throw new TypeError("this cannot be null or undefined");

    if (searchString instanceof RegExp)
        throw new TypeError("searchString cannot be a RegExp");

    var src = $rt_toString(this);
    var searchStr = $rt_toString(searchString);
    var pos = $rt_toInteger(position);
    var len = src.length;
    var start = Math.min(Math.max(pos, 0), len);
    var searchLen = searchStr.length;

    var k = start;
    while ((k + searchLen) <= len)
    {
        var j = 0;
        while (j < searchLen)
        {
            if (src[k + j] !== searchStr[j]) break;
            j++;
        }
        // Found a valid `k`.
        if (j === searchLen) return true;
        k++;
    }

    return false;
}

/**
15.5.4.7 String.prototype.indexOf(searchString, position)
*/
function string_indexOf(searchString, pos)
{
    var i;

    if (pos === undefined || pos < 0)
        i = 0;
    else
        i = pos;

    for (; i < this.length; ++i)
    {
        var j;

        for (j = 0; j < searchString.length; ++j)
            if (this.charCodeAt(i + j) !== searchString.charCodeAt(j))
                break;
        if (j === searchString.length)
            return i;
    }
    return -1;
}

/**
15.5.4.8 String.prototype.lastIndexOf(searchString, position)
*/
function string_lastIndexOf(searchString, pos)
{
    if (searchString.length > this.length)
        return -1;

    if (pos === undefined)
        pos = this.length;
    else if (pos >= this.length)
        pos = this.length;
    else if (pos < 0)
        pos = 0;

    if (searchString.length === 0)
        return pos;

    if (pos + searchString.length > this.length)
        pos = this.length - searchString.length;

    var firstChar = searchString.charCodeAt(0);
    for (var i = pos; i >= 0; i--)
    {
        if (this.charCodeAt(i) === firstChar)
        {
            var match = true;
            for (var j = 1; j < searchString.length; j++)
            {
                if (this.charCodeAt(i + j) !== searchString.charCodeAt(j))
                {
                    match = false;
                    break;
                }
            }
            if (match) return i;
        }
    }

    return -1;
}

/**
15.5.4.9 String.prototype.localeCompare(that)
*/
function string_localeCompare(that)
{
    var length = this.length;

    if (that.length < length)
        length = that.length;

    var i;

    for (i = 0; i < length; i++)
    {
        var a = this.charCodeAt(i);
        var b = this.charCodeAt(i);

        if (a !== b)
        {
            return a - b;
        }
    }

    if (this.length > length)
    {
        return 1;
    }
    else if (that.length > length)
    {
        return -1;
    }
    else
    {
        return 0;
    }
}

/**
15.5.4.10 String.prototype.match(regexp)
*/
function string_match(regexp)
{
    var re;

    if (regexp instanceof $rt_RegExp)
        re = regexp;
    else
        re = new $rt_RegExp(regexp);

    if (re.global)
    {
        var result = [];
        var match;
        var previousMatch;

        while (true)
        {
            match = re.exec(this);

            // Stop if no match left
            if (match === null)
                break;

            // Stop if we matched an empty string twice in a row (15.10.2.5 NOTE4)
            if (previousMatch && match[0].length === 0 && previousMatch[0].length === 0)
                break;

            result.push(match[0]);
            previousMatch = match;
        }

        if (result.length === 0)
            return null;

        return result;
    }
    else
    {
        return re.exec(this);
    }
}

/**
http://people.mozilla.org/~jorendorff/es6-draft.html#sec-properties-of-the-string-constructor (21.1.3.12)
*/
function string_repeat(count)
{
    if (this === null || this === undefined)
        throw new TypeError("this cannot be null or undefined");

    var str = $rt_toString(this);
    var n = $rt_toInteger(count);

    if (n < 0 || n === Infinity)
        throw new RangeError("Count must be positive and cannot be Infinity");

    if (str.length === 0 || count === 0) return '';

    var buff = '';
    for (var i = 0; i < count; i++)
    {
        buff += str;
    }

    return buff;
}

/**
15.5.4.11 String.prototype.replace(searchValue, replaceValue)
*/
function string_replace(searchValue, replaceValue)
{
    if (typeof searchValue === "string")
    {
        var pos = this.indexOf(searchValue);

        if (pos === -1)
            return this;

        if (typeof replaceValue === "function")
        {
            var ret = replaceValue(searchValue, pos, this.toString());

            return this.substring(0, pos).concat(
                String(ret),
                this.substring(pos + $rt_str_get_len(searchValue))
            );
        }
        else
        {
            return this.substring(0, pos).concat(
                replaceValue.toString(),
                this.substring(pos + $rt_str_get_len(searchValue))
            );
        }
    }
    else if (searchValue instanceof $rt_RegExp)
    {
        // Save regexp state
        var globalFlagSave = searchValue.global;
        var lastIndexSave = searchValue.lastIndex;

        // Set the regexp global to get matches' index
        searchValue.global = true;
        searchValue.lastIndex = 0;

        // Current and previous regexp matches
        var previousMatch;
        var match;

        // Will hold new string parts
        var nsparts = [];
        var nslen = 0;
        var i = 0;

        do
        {
            // Execute regexp
            match = searchValue.exec(this);

            // Stop if no match left
            if (match === null)
                break;

            // Stop if we matched an empty string twice in a row (15.10.2.5 NOTE4)
            if (previousMatch && match[0].length === 0 && previousMatch[0].length === 0)
                break;

            // Get the last match index
            var matchIndex = searchValue.lastIndex - match[0].length;

            if (typeof replaceValue === "function")
            {
                if (i < matchIndex)
                    nsparts.push(this.substring(i, matchIndex));

                // Compose the arguments array with the match array
                match.push(matchIndex);
                match.push(this.toString());

                var ret = replaceValue.apply(null, match);
                nsparts.push(new String(ret).toString());
            }
            else
            {
                // Expand replaceValue
                var rvparts = [];
                var j = 0, k = 0;

                // Get the string representation of the object
                replaceValue = replaceValue.toString();

                for (; j < replaceValue.length; ++j)
                {
                    // Expand special $ form
                    if (replaceValue.charCodeAt(j) === 36) // '$'
                    {
                        if (k < j)
                            rvparts.push(replaceValue.substring(k, j));

                        var c = replaceValue.charCodeAt(j + 1);

                        if (c === 36) // '$'
                        {
                            ++j;
                            rvparts.push("$");
                        }
                        else if (c === 38) // '&'
                        {
                            ++j;
                            rvparts.push(match[0]);
                        }
                        else if (c === 96) // '`'
                        {
                            ++j;
                            rvparts.push(this.substring(0, matchIndex));
                        }
                        else if (c === 39) // '''
                        {
                            ++j;
                            rvparts.push(this.substring(searchValue.lastIndex));
                        }
                        else if (c >= 48 && c <= 57)
                        {
                            ++j;

                            var n = 0;
                            var cn = replaceValue.charCodeAt(j + 1);
                            if (cn >= 48 && cn <= 57)
                            {
                                n = (cn - 48) * 10;
                                ++j;
                            }
                            n += c - 48;

                            // Push submatch if index is valid, or the raw string if not
                            if (n < match.length)
                                rvparts.push(match[n]);
                            else
                                rvparts.push("$" + n);
                        }
                        else
                        {
                            rvparts.push("$");
                        }

                        k = j + 1;
                    }
                }

                if (k === 0)
                {
                    if (i < matchIndex)
                        nsparts.push(this.substring(i, matchIndex));

                    // Not expansion occured : push raw replaceValue.
                    if (replaceValue.length > 0)
                        nsparts.push(replaceValue);
                }
                else
                {
                    // Get the last not expanded part of replaceValue.
                    if (k < replaceValue.length - 1)
                        rvparts.push(replaceValue.substring(k, replaceValue.length));

                    if (i < matchIndex)
                        nsparts.push(this.substring(i, matchIndex));

                    var expandedrv = rvparts.join("");

                    if (expandedrv.length > 0)
                        nsparts.push(expandedrv);
                }
            }

            i = searchValue.lastIndex;

            previousMatch = match;

        } while (globalFlagSave);

        if (i < this.length)
            nsparts.push(this.substring(i, this.length));

        searchValue.global = globalFlagSave;
        searchValue.lastIndex = lastIndexSave;

        return nsparts.join("");
    }

    return this.toString();
}

/**
15.5.4.12 String.prototype.search(regexp)
*/
function string_search(regexp)
{
    var re;
    var globalSave;
    var lastIndexSave;

    if (regexp instanceof $rt_RegExp)
        re = regexp;
    else
        re = new $rt_RegExp(regexp);

    globalSave = re.global;
    lastIndexSave = re.lastIndex;
    re.global = true;
    re.lastIndex = 0;

    var matchIndex = -1;
    var match = re.exec(this);
    if (match !== null)
    {
        matchIndex = re.lastIndex - match[0].length;
    }

    re.global = globalSave;
    re.lastIndex = lastIndexSave;
    return matchIndex;
}

/**
15.5.4.14 String.prototype.split(separator, limit)
*/
function string_split(separator, limit)
{
    var res = new Array();
    var len = this.length;

    // special cases
    if (limit === 0)
    {
        return res;
    }

    if (separator === undefined)
    {
        res[0] = this;
        return res;
    }

    if (separator instanceof $rt_RegExp)
    {
        var start  = 0,
            string = this;

        while (true)
        {
            var pos = string.search(separator);
            if (pos === -1)
            {
                res.push(string);
                break;
            }

            res.push(string.substring(start, pos));
            string = string.substring(pos + 1, len);
        }

        return res;
    }

    var sep = separator + "";
    var this_blank = (len === 0);
    var sep_blank = (sep.length === 0);

    // special cases
    if (this_blank)
    {
        if (sep_blank)
            return res;

        res[0] = this;
        return res;
    }
    else if (sep_blank)
    {
        for (var i = 0; i < len; i ++)
            res[i] = this[i];

        return res;
    }

    var pos = this.indexOf(sep);
    var start = 0;
    var sepLen = sep.length;

    while (pos >= 0)
    {
        res.push(this.substring(start, pos));
        if (res.length === limit) return res;
        start = pos + sepLen;
        pos = this.indexOf(sep, pos + sepLen);
    }

    if (start <= len)
    {
        res.push(this.substring(start));
    }

    return res;
}

/**
https://people.mozilla.org/~jorendorff/es6-draft.html#sec-string.prototype.startswith (21.1.3.18)
*/
function string_startsWith(searchString, position)
{
    if (this === null || this === undefined)
        throw new TypeError("this cannot be null or undefined");

    if (searchString instanceof RegExp)
        throw new TypeError("searchString cannot be a RegExp");

    var src = $rt_toString(this);
    var searchStr = $rt_toString(searchString);
    var pos = $rt_toInteger(position);
    var len = src.length;
    var start = Math.min(Math.max(pos, 0), len);
    var searchLength = searchStr.length;

    if (start + searchLength > len)
        return false;

    return src.substr(start, searchLength) === searchStr;
}

/**
15.5.4.15 String.prototype.substring(start, end)
*/
function string_substring(start, end)
{
    var source = this.toString();
    var length = $rt_str_get_len(source);

    if (!$ir_is_int32(start))
    {
        start = $rt_toInt32(start);
    }

    if (!$ir_is_int32(end))
    {
        if (end === undefined)
            end = length;
        else
            end = $rt_toInt32(end);
    }

    if (start < 0)
        start = 0;
    else if (start > length)
        start = length;

    if (end > length)
        end = length;
    else if (end < 0)
        end = 0;

    if (start > end)
    {
        var tmp = start;
        start = end;
        end = tmp;
    }

    // Allocate new string
    var s = $rt_str_alloc(end - start);

    // Copy substring characters in the new allocated string
    for (var i = start, j = 0; i < end; ++i, ++j)
    {
        var ch = $rt_str_get_data(source, i);
        $rt_str_set_data(s, j, ch);
    }

    return $ir_get_str(s);
}

/**
15.5.4.12 String.prototype.slice(start, end)
*/
function string_slice(start, end)
{
    var source = this.toString();
    var length = $rt_str_get_len(source);

    if (start === $undef)
        start = 0;
    if (end === $undef)
        end = length;

    if (start < 0)
        start += length;
    if (end < 0)
        end += length;

    return string_substring.call(this, start, end);
}

/**
String.prototype.substr(start, length)
*/
function string_substr(start, length)
{
    var end = (length === undefined) ? undefined:(start + length);

    return string_substring.apply(this, [start, end]);
}

/**
15.5.4.16 String.prototype.toLowerCase()
*/
function string_toLowerCase()
{
    var a = string_internal_toCharCodeArray(this);

    // This code assumes the array is a copy of the internal char array.
    // It may be more efficient to expose the internal data directly and
    // make a copy only when necessary.

    for (var i = 0; i < a.length; i++)
    {
        var c = a[i];
        // FIXME: support full Unicode
        if (c > 255) error("Only ASCII characters are currently supported");

        if ((c >= 65 && c <= 90)
                || (c >= 192 && c <= 214)
                || (c >= 216 && c <= 222))
        {
            a[i] = c + 32;
        }
    }

    return string_internal_fromCharCodeArray(a);
}

/**
15.5.4.17 String.prototype.toLocaleLowerCase()
*/
function string_toLocaleLowerCase()
{
    // FIXME: not quire correct for the full Unicode
    return this.toLowerCase();
}

/**
15.5.4.18 String.prototype.toUpperCase()
*/
function string_toUpperCase()
{
    var a = string_internal_toCharCodeArray(this);

    for (var i = 0; i < a.length; i++)
    {
        var c = a[i];

        // FIXME: support full Unicode
        if (c > 255)
            error("Only ASCII characters are currently supported");

        if ((c >= 97 && c <= 122)  ||
            (c >= 224 && c <= 246) ||
            (c >= 248 && c <= 254))
            a[i] = c - 32;
    }

    return string_internal_fromCharCodeArray(a);
}

/**
15.5.4.19 String.prototype.toLocaleUpperCase()
*/
function string_toLocaleUpperCase()
{
    // FIXME: not quire correct for the full Unicode
    return this.toUpperCase();
}

/**
15.5.4.20 String.prototype.trim()
*/
function string_trim()
{
    var from = 0, to = this.length - 1;

    while (string_internal_isWhiteSpace(this.charCodeAt(from)))
        ++from;

    while (string_internal_isWhiteSpace(this.charCodeAt(to)))
        --to;

    if (from > to)
        return "";
    else
        return this.substring(from, to + 1);
}

/**
Setup String method.
*/

String.fromCharCode = string_fromCharCode;
String.fromCodePoint = string_fromCodePoint;

// Setup String prototype
String.prototype.toString = string_toString;
String.prototype.charCodeAt = string_charCodeAt;
String.prototype.codePointAt = string_codePointAt;
String.prototype.valueOf = string_valueOf;
String.prototype.charAt = string_charAt;
String.prototype.concat = string_concat;
String.prototype.endsWith = string_endsWith;
String.prototype.includes = string_includes;
String.prototype.indexOf = string_indexOf;
String.prototype.lastIndexOf = string_lastIndexOf;
String.prototype.localeCompare = string_localeCompare;
String.prototype.slice = string_slice;
String.prototype.match = string_match;
String.prototype.repeat = string_repeat;
String.prototype.replace = string_replace;
String.prototype.search = string_search;
String.prototype.split = string_split;
String.prototype.startsWith = string_startsWith;
String.prototype.substring = string_substring;
String.prototype.substr = string_substr;
String.prototype.toLowerCase = string_toLowerCase;
String.prototype.toLocaleLowerCase = string_toLocaleLowerCase;
String.prototype.toUpperCase = string_toUpperCase;
String.prototype.toLocaleUpperCase = string_toLocaleUpperCase;
String.prototype.trim = string_trim;

String.prototype.concat.length = 1;
String.prototype.indexOf.length = 1;
String.prototype.lastIndexOf.length = 1;
String.prototype.slice.length = 2;
String.prototype.split.length = 2;
String.prototype.substring.length = 2;

// Make the String.prototype properties non-enumerable
for (p in String.prototype)
{
    Object.defineProperty(
        String.prototype,
        p,
        {enumerable:false, writable:true, configurable:true }
    );
}
