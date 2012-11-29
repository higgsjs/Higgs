/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012, Maxime Chevalier-Boisvert. All rights reserved.
*
*  This software is licensed under the following license (Modified BSD
*  License):
*
*  Redistribution and use in source and binary forms, with or without
*  modification, are permitted provided that the following conditions are
*  met:
*   1. Redistributions of source code must retain the above copyright
*      notice, this list of conditions and the following disclaimer.
*   2. Redistributions in binary form must reproduce the above copyright
*      notice, this list of conditions and the following disclaimer in the
*      documentation and/or other materials provided with the distribution.
*   3. The name of the author may not be used to endorse or promote
*      products derived from this software without specific prior written
*      permission.
*
*  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
*  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
*  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
*  NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
*  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
*  NOT LIMITED TO PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
*  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
*  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
*  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
*  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
*****************************************************************************/

/**
Not-a-number value
*/
var NaN = $ir_div_f64(0.0, 0.0);

/**
Test if a value is NaN
*/
function isNaN(v)
{
    return ($ir_is_float(v) && $ir_ne_f64(v, v));
}

/**
Perform an assertion test
*/
function assert(test, error)
{
    if (test)
        return;

    // TODO: throw Error object
    print(
        'ASSERTION FAILED:\n' + 
        error
    );
}

/**
Print a value to the console
*/
function print(val)
{
    // Convert the value to a string
    var strVal = $rt_toString(val);
       
    // Print the string
    $ir_print_str(strVal);
}

/**
Print a value followed by a newline
*/
function println(val)
{
    print(val);
    print('\n');
}

/**
Concatenate the strings from two string objects
*/
function $rt_strcat(str1, str2)
{
    // Get the length of both strings
    var len1 = $rt_str_get_len(str1);
    var len2 = $rt_str_get_len(str2);

    // Compute the length of the new string
    var newLen = len1 + len2;

    // Allocate a string object
    var newStr = $rt_str_alloc(newLen);

    // Copy the character data from the first string
    for (var i = 0; i < len1; i++)
    {
        var ch = $rt_str_get_data(str1, i);
        $rt_str_set_data(newStr, i, ch);
    }

    // Copy the character data from the second string
    for (var i = 0; i < len2; i++)
    {
        var ch = $rt_str_get_data(str2, i);
        $rt_str_set_data(newStr, len1 + i, ch);
    }

    // Find/add the concatenated string in the string table
    return $ir_get_str(newStr);
}

/**
Create a string representing an integer value
*/
function $rt_intToStr(intVal, radix)
{
    assert (
        $ir_is_int(radix)    &&
        $ir_gt_i32(radix, 0) && 
        $ir_le_i32(radix, 36),
        'invalid radix'
    );

    var strLen;
    var neg;

    // If the integer is negative, adjust the string length for the minus sign
    if (intVal < 0)
    {
        strLen = 1;
        intVal *= -1;
        neg = true;
    }
    else
    {
        strLen = 0;
        neg = false;
    }

    // Compute the number of digits to add to the string length
    var intVal2 = intVal;
    do
    {
        strLen++;
        intVal2 = $ir_div_i32(intVal2, radix);

    } while ($ir_ne_i32(intVal2, 0));

    // Allocate a string object
    var strObj = $rt_str_alloc(strLen);

    // If the string is negative, write the minus sign
    if (neg)
    {
        $rt_str_set_data(strObj, 0, 45);
    }

    var digits = '0123456789abcdefghijklmnopqrstuvwxyz';

    // Write the digits in the string
    var i = strLen - 1;
    do
    {
        var digit = $ir_mod_i32(intVal, radix);

        var ch = $rt_str_get_data(digits, digit);

        $rt_str_set_data(strObj, i, ch);

        intVal = $ir_div_i32(intVal, radix);

        i--;

    } while ($ir_ne_i32(intVal, 0));

    // Get the corresponding string from the string table
    return $ir_get_str(strObj);
}

/**
Get the string representation of a value
*/
function $rt_toString(v)
{
    var type = typeof v;

    if (type === "undefined")
        return "undefined";

    if (type === "boolean")
        return v? "true":"false";

    if (type === "string")
        return v;

    // TODO: floating-point toString
    if (type === "number")
        return $rt_intToStr(v, 10);

    if (type === "object")
        return v? v.toString():"null";

    if (type === "function" || type === "array")
        return v.toString();

    return "unhandled type in toString";
}

/**
Evaluate a value as a boolean
*/
function $rt_toBool(v)
{
    if ($ir_jump_false($ir_is_const(v)))
        return (v === true);

    if ($ir_jump_false($ir_is_int(v)))
        return $ir_ne_i32(v, 0);

    if ($ir_jump_false($ir_is_float(v)))
        return $ir_ne_f64(v, 0.0);

    if ($ir_jump_false($ir_is_refptr(v)))
    {
        var type = $rt_obj_get_header(v);

        if ($ir_jump_false($ir_eq_i32(type, $rt_LAYOUT_STR)))
            return $ir_gt_i32($rt_str_get_len(v), 0);

        return true;
    }

    // TODO: raw ptr?

    return false;
}

/**
JS typeof operator
*/
function $rt_typeof(v)
{
    if ($ir_is_int(v) || $ir_is_float(v))
        return "number";

    if ($ir_is_const(v) === true)
    {
        if (v === true  || v === false)
            return "boolean";

        if (v === undefined)
            return "undefined";
    }

    if ($ir_is_refptr(v) === true)
    {
        var type = $rt_obj_get_header(v);

        if (type === $rt_LAYOUT_STR)
            return "string";

        if (type === $rt_LAYOUT_OBJ || type === $rt_LAYOUT_ARR)
            return "object";

        if (type === $rt_LAYOUT_CLOS)
            return "function";
    }

    return "unhandled type in typeof";
}

/**
JS addition operator
*/
function $rt_add(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        var r;
        if (r = $ir_add_i32_ovf(x, y))
        {
            return r;
        }
        else
        {
            var fx = $ir_i32_to_f64(x);
            var fy = $ir_i32_to_f64(y);
            return $ir_add_f64(fx, fy);
        }
    }

    // If either value is floating-point or integer
    else if (
        ($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_add_f64(fx, fy);
    }

    // Evaluate the string value of both arguments
    var sx = $rt_toString(x);
    var sy = $rt_toString(y);

    // Concatenate the strings
    return $rt_strcat(sx, sy);
}

/**
JS subtraction operator
*/
function $rt_sub(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        var r;
        if (r = $ir_sub_i32_ovf(x, y))
        {
            return r;
        }
        else
        {
            var fx = $ir_i32_to_f64(x);
            var fy = $ir_i32_to_f64(y);
            return $ir_sub_f64(fx, fy);
        }
    }

    // If either value is floating-point or integer
    else if (
        ($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_sub_f64(fx, fy);
    }

    return NaN; 
}

