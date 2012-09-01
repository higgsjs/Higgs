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

function parseInt(
    string,
    radix
)
{
    var i = 0;
    var positive = true;

    // Force string value representation.
    string = new String(string).toString();

    // Skip whitespaces.
    while (string_internal_isWhiteSpace(string.charCodeAt(i)))
        ++i;

    // Read + - sign.
    if (string.charCodeAt(i) === 43) // '+'
    {
        ++i;
    }
    else if (string.charCodeAt(i) === 45) // '-'
    {
        ++i;
        positive = false;
    }

    // Reject invalid radix value.
    if (radix !== undefined && radix < 2 && radix > 36)
        // FIXME: must return NaN
        return null;

    // Set radix default value if no valid radix parameter given.
    if (radix === undefined)
        radix = 10;

    // Assume hexadecimal if string begin with '0x' or '0X'
    if (string.charCodeAt(i) === 48 &&
        (string.charCodeAt(i + 1) === 88 ||
         string.charCodeAt(i + 1) === 120))
    {
        i += 2;
        radix = 16;
    }

    var j = i, n = 0;

    while (true)
    {
        var digit = string.charCodeAt(j);

        // Convert character to numerical value.
        if (digit >= 65 && digit <= 90) // A-Z
            digit -= 55;
        else if (digit >= 97 && digit <= 122) // a-z
            digit -= 87;
        else if (digit >= 48 && digit <= 57) // 0-9
            digit -= 48;
        else
            break;

        if (digit >= radix)
            break;

        n = (n * radix) + digit;
        ++j;
    }

    // Return numerical value if characters have been read.
    if (j > i)
       return positive ? n : -n;

    // FIXME: must return NaN
    return null; 
}

/**
15.1.3.1 decodeURI(encodedURI)
*/
function decodeURI (
    encodedURI
)
{
    // Parse and returns a 2 characters hexadecimal value in the string
    // at a given position.
    function extractHexValue (
        str,
        pos
    )
    {
        var value = 0, i = pos;

        for (; i < pos + 2; ++i)
        {
            var hc = str.charCodeAt(i);

            if (hc >= 97 && hc <= 102) // a-f
                value = (value * 16) + (hc - 87);
            else if (hc >= 65 && hc <= 70) // A-F
                value = (value * 16) + (hc - 55);
            else if (hc >= 48 && hc <= 57) // 0-9
                value = (value * 16) + (hc - 48);
            else
                return null;
        }
        return value;
    }

    var decodedURIParts = new Array();
    // FIXME: should be local (backend problem)
    var j = 0;

    for (var i = 0; i < encodedURI.length;)
    {
        while (i < encodedURI.length &&
               encodedURI.charCodeAt(i) !== 37) // '%'
           ++i;

        if (i < encodedURI.length)
        {
            if (j < i)
                decodedURIParts.push(encodedURI.substring(j, i));

            // Parse first byte
            if (i + 2 >= encodedURI.length)
                // FIXME: must throw URIError.
                return null;

            var cbyte = extractHexValue(encodedURI, i + 1);

            if (cbyte === null)
                // FIXME: must throw URIError.
                return null;

            i += 3;
            var bytes = [ cbyte ];
            var bytesToRead;

            if ((cbyte & 0x80) === 0x00)
                bytesToRead = 0;
            else if ((cbyte & 0xE0) === 0xC0)
                bytesToRead = 1;
            else if ((cbyte & 0xF0) === 0xE0)
                bytesToRead = 2;
            else if ((cbyte & 0xF8) === 0xF0)
                bytesToRead = 3;

            for (var k = 0; k < bytesToRead; k++)
            {
                // Check for valid %XX hexadecimal form on current position of value 10xxxxxx
                if (i + 2 >= encodedURI.length ||
                    encodedURI.charCodeAt(i) !== 37 ||
                    (cbyte = extractHexValue(encodedURI, i + 1)) === null ||
                    cbyte < 0x80 || cbyte > 0xBF)
                    // FIXME: must throw URIError.
                    return null;

                i += 3;
                bytes.push(cbyte);
            }

            // Ref. Table 21 ECMA-262
            switch (bytesToRead)
            {
                case 0:
                decodedURIParts.push(String.fromCharCode(bytes[0]));
                break;

                case 1:
                var charCode = ((bytes[0] & 0x1F) << 6) + (bytes[1] & 0x3F);
                decodedURIParts.push(String.fromCharCode(charCode));
                break;

                case 2:
                var charCode = ((bytes[0] & 0x0F) << 12) +
                               ((bytes[1] & 0x3F) << 6) +
                               (bytes[2] & 0x3F);
                decodedURIParts.push(String.fromCharCode(charCode));
                break;

                case 3:
                var u = ((bytes[0] & 0x7) << 2) | ((bytes[1] & 0x30) >> 4);
                var charCode1 = 0xD800 | ((u - 1) << 6) | ((bytes[1] & 0xF) << 2) | ((bytes[2] & 0x30) >> 4);
                var charCode2 = 0xDC00 | ((bytes[2] & 0xF) << 6) | (bytes[3] & 0x3F);

                decodedURIParts.push(String.fromCharCode(charCode1));
                decodedURIParts.push(String.fromCharCode(charCode2));
                break;
            }

            j = i;
        }
    }

    return decodedURIParts.join("");
}

/**
Filter for the classes uriUnescaped. (15.1.3)
*/
function unescapedClassFilter (c)
{
    return ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
            (c >= 48 && c <= 57) || (c >= 39 && c <= 42)  ||
            c === 45 || c === 95 || c === 46 || c === 33  ||
            c === 126)
}

/**
Filter for the classes uriUnescaped, uriReserved and #. (15.1.3)
*/
function unescapedClassFilterComponent (c)
{
    return ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
            (c >= 48 && c <= 57) || (c >= 39 && c <= 42)  ||
            c === 45 || c === 95 || c === 46 || c === 33  ||
            c === 126 || c === 35 || c === 59 || c === 47 ||
            c === 63 || c === 58 || c === 64 || c === 38  ||
            c === 61 || c === 43 || c === 36 || c === 44)
}

/**
Generic uri encoding function that takes a unescapedClass filter function.
*/
function _encodeURI (
    uri,
    unescapedClassFilter
)
{
    var encodedURIParts = [], i = 0, j = 0;

    for (var i = 0; i < uri.length;)
    {
        // Skip unescaped characters.
        while (i < uri.length &&
               unescapedClassFilter(uri.charCodeAt(i)))
           ++i;

        if (i < uri.length)
        {
            // Push skipped substring if needed.
            if (j < i)
                encodedURIParts.push(uri.substring(j, i));

            // Current character has to be escaped.
            var c = uri.charCodeAt(i), v;

            // 15.1.3 .4 .d .i
            if (c >= 0xDC00 && c <= 0xDFFF)
                // FIXME: must throw URIError
                return null;

            if (c < 0xD800 || c > 0xDBFF)
            {
                // Character fit in one 16 bits 
                v = c;
            }
            else
            {
                // Character is 32 bits wide : get next character
                // compose the value of the unicode character.

                if (i + 1 >= uri.length)
                    // FIXME: must throw URIError
                    return null;

                var cnext = uri.charCodeAt(i + 1);

                // Reject invalid values.
                if (cnext < 0xDC00 || cnext > 0xDFFF)
                    // FIXME: must throw URIError
                    return null;

                ++i;

                // Compose character.
                v = (c - 0xD800) * 0x400 + (cnext - 0xDC00) + 0x10000;
            }

            var utfbytes;

            // Encode the character value to an array of bytes following
            // the UTF-8 convention (15.1.3 Table 21)
            if (v < 0x80)
                utfbytes = [v];   
            else if (v < 0x0800)
                utfbytes = [0xC0 | v >> 6, 0x80 | v & 0x3F];
            else if (v < 0x10000)
                utfbytes = [0xE0 | v >> 12, 0x80 | v >> 6 & 0x3F, 0x80 | v & 0x3F];
            else if (v < 0x200000)
                utfbytes = [0xF0 | v >> 18, 0x80 | v >> 12 & 0x3F, 0x80 | v >> 6 & 0x3F, 0x80 | v & 0x3F];

            // Encode the array of bytes to a series of %XX hexadecimal format.
            var utfchars = new Array(utfbytes.length * 3);
            for (var k = 0, l = 0; k < utfbytes.length; ++k, l += 3)
            {
                utfchars[l] = 37; // '%'

                if (((utfbytes[k] & 0xF0) >> 4) < 10)
                    utfchars[l + 1] = ((utfbytes[k] & 0xF0) >> 4) + 48;
                else
                    utfchars[l + 1] = ((utfbytes[k] & 0xF0) >> 4) + 55;

                if ((utfbytes[k] & 0x0F) < 10)
                    utfchars[l + 2] = (utfbytes[k] & 0x0F) + 48;
                else
                    utfchars[l + 2] = (utfbytes[k] & 0x0F) + 55;
            }

            // Push the string in the result.
            encodedURIParts.push(string_internal_fromCharCodeArray(utfchars));
            j = ++i;
        }
    }

    // Push remaining characters of the source string if needed.
    if (j < i)
        encodedURIParts.push(uri.substring(j, i));

    return encodedURIParts.join("");
}

/**
15.1.3.3 encodeURI(uri)
*/
function encodeURI (
    uri
)
{
    return _encodeURI(uri, unescapedClassFilter);
}

/**
15.1.3.4 encodeURIComponent(uriComponent)
*/
function encodeURIComponent (
    uri
)
{
    return _encodeURI(uri, unescapedClassFilterComponent);
}

function parseFloat (
    string
)
{
    // FIXME: implement fully once floating-point support is added
    return parseInt(string);
}

function isNaN (
    number
)
{
    return false;
}

function isFinite (
    number
)
{
    return true;
}

