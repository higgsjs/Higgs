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

/***
Undefined value
*/
var undefined = $ir_set_undef();

/**
Not-a-number value
*/
var NaN = $ir_div_f64(0.0, 0.0);

/**
Infinity value
*/
var Infinity = $ir_div_f64(1.0, 0.0);

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
    if ($ir_if_true(test))
        return;

    // TODO: throw Error object
    println(
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

    if (type === "number")
    {
        if ($ir_is_int(v) === true)
        {
            return $rt_intToStr(v, 10);
        }
        else
        {
            if (isNaN(v))
                return "NaN";
            if (v === Infinity)
                return "Infinity";
            if (v === -Infinity)
                return "-Infinity";

            // TODO: $rt_floatToStr
            return "fp tostring unimplemented";
        }
    }

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
    if ($ir_is_const(v))
        return $ir_eq_const(v, true);

    if ($ir_is_int(v))
        return $ir_ne_i32(v, 0);

    if ($ir_is_float(v))
        return $ir_ne_f64(v, 0.0);

    if ($ir_is_refptr(v))
    {
        var type = $rt_obj_get_header(v);

        if ($ir_eq_i32(type, $rt_LAYOUT_STR))
            return $ir_gt_i32($rt_str_get_len(v), 0);

        return true;
    }

    if ($ir_is_rawptr(v))
    {
        // TODO: raw ptr?



    }

    return false;
}

/**
JS typeof operator
*/
function $rt_typeof(v)
{
    if ($ir_is_int(v) || $ir_is_float(v))
        return "number";

    if ($ir_is_const(v))
    {
        if ($ir_eq_const(v, true) || $ir_eq_const(v, false))
            return "boolean";

        if ($ir_eq_const(v, undefined))
            return "undefined";

        if ($ir_eq_const(v, null))
            return "object";
    }

    if ($ir_is_refptr(v))
    {
        var type = $rt_obj_get_header(v);

        if ($ir_eq_i32(type, $rt_LAYOUT_STR))
            return "string";

        if ($ir_eq_i32(type, $rt_LAYOUT_OBJ) || $ir_eq_i32(type, $rt_LAYOUT_ARR))
            return "object";

        if ($ir_eq_i32(type, $rt_LAYOUT_CLOS))
            return "function";
    }

    return "unhandled type in typeof";
}

//=============================================================================
// Arithmetic operators
//=============================================================================

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

/**
JS multiplication operator
*/
function $rt_mul(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        var r;
        if (r = $ir_mul_i32_ovf(x, y))
        {
            return r;
        }
        else
        {
            var fx = $ir_i32_to_f64(x);
            var fy = $ir_i32_to_f64(y);
            return $ir_mul_f64(fx, fy);
        }
    }

    // If either value is floating-point or integer
    else if (
        ($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_mul_f64(fx, fy);
    }

    return NaN; 
}

/**
JS division operator
*/
function $rt_div(x, y)
{
    // If either value is floating-point or integer
    if (($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_div_f64(fx, fy);
    }

    return NaN; 
}

/**
JS modulo operator
*/
function $rt_mod(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_mod_i32(x, y);
    }

    assert (false, "floating-point modulo unsupported");
}

//=============================================================================
// Bitwise operators
//=============================================================================

function $rt_and(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_and_i32(x, y);
    }

    assert (false, "unsupported type in bitwise and");
}

function $rt_or(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_or_i32(x, y);
    }

    assert (false, "unsupported type in bitwise or");
}

function $rt_xor(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_xor_i32(x, y);
    }

    assert (false, "unsupported type in bitwise xor");
}

function $rt_lsft(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_lsft_i32(x, y);
    }

    assert (false, "unsupported type in bitwise xor");
}

function $rt_rsft(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_rsft_i32(x, y);
    }

    assert (false, "unsupported type in bitwise xor");
}

function $rt_ursft(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_ursft_i32(x, y);
    }

    assert (false, "unsupported type in bitwise xor");
}

//=============================================================================
// Comparison operators
//=============================================================================

/**
JS less-than operator
*/
function $rt_lt(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_lt_i32(x, y);
    }

    // If either value is floating-point or integer
    if (($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_lt_f64(fx, fy);
    }

    assert (false, "unsupported type in lt");
}

/**
JS less-than or equal operator
*/
function $rt_le(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_le_i32(x, y);
    }

    // If either value is floating-point or integer
    if (($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_le_f64(fx, fy);
    }

    assert (false, "unsupported type in le");
}

/**
JS greater-than operator
*/
function $rt_gt(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_gt_i32(x, y);
    }

    // If either value is floating-point or integer
    if (($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_gt_f64(fx, fy);
    }

    assert (false, "unsupported type in le");
}

/**
JS greater-than or equal operator
*/
function $rt_ge(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_ge_i32(x, y);
    }

    // If either value is floating-point or integer
    if (($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_ge_f64(fx, fy);
    }

    assert (false, "unsupported type in le");
}

/**
JS equality (==) comparison operator
*/
function $rt_eq(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_eq_i32(x, y);
    }

    // If both values are references
    else if ($ir_is_refptr(x) && $ir_is_refptr(y))
    {
        var tx = $rt_obj_get_header(x);
        var ty = $rt_obj_get_header(y);

        if ($ir_eq_i32(tx, $rt_LAYOUT_STR) && $ir_eq_i32(ty, $rt_LAYOUT_STR))
            return $ir_eq_refptr(x, y);
    }

    // If both values are constants
    else if ($ir_is_const(x) && $ir_is_const(y))
    {
        return $ir_eq_const(x, y);
    }

    // If both values are floating-point
    else if ($ir_is_float(x) && $ir_is_float(y))
    {
        return $ir_eq_f64(x, y);
    }

    assert (false, "unsupported type in eq");
}

/**
JS inequality (!=) comparison operator
*/
function $rt_ne(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_ne_i32(x, y);
    }

    // If both values are references
    else if ($ir_is_refptr(x) && $ir_is_refptr(y))
    {
        var tx = $rt_obj_get_header(x);
        var ty = $rt_obj_get_header(y);

        if ($ir_eq_i32(tx, $rt_LAYOUT_STR) && $ir_eq_i32(ty, $rt_LAYOUT_STR))
            return $ir_ne_refptr(x, y);
    }

    // If both values are constants
    else if ($ir_is_const(x) && $ir_is_const(y))
    {
        return $ir_ne_const(x, y);
    }

    // If both values are floating-point
    else if ($ir_is_float(x) && $ir_is_float(y))
    {
        return $ir_ne_f64(x, y);
    }

    assert (false, "unsupported type in eq");
}

/**
JS strict equality (===) comparison operator
*/
function $rt_se(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_eq_i32(x, y);
    }

    // If both values are references
    else if ($ir_is_refptr(x) && $ir_is_refptr(y))
    {
        return $ir_eq_refptr(x, y);
    }

    // If both values are constants
    else if ($ir_is_const(x) && $ir_is_const(y))
    {
        return $ir_eq_const(x, y);
    }

    // If both values are floating-point
    else if ($ir_is_float(x) && $ir_is_float(y))
    {
        return $ir_eq_f64(x, y);
    }

    assert (false, "unsupported type in se");
}

/**
JS strict inequality (!==) comparison operator
*/
function $rt_ne(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_ne_i32(x, y);
    }

    // If both values are references
    else if ($ir_is_refptr(x) && $ir_is_refptr(y))
    {
        return $ir_ne_refptr(x, y);
    }

    // If both values are constants
    else if ($ir_is_const(x) && $ir_is_const(y))
    {
        return $ir_ne_const(x, y);
    }

    // If both values are floating-point
    else if ($ir_is_float(x) && $ir_is_float(y))
    {
        return $ir_ne_f64(x, y);
    }

    assert (false, "unsupported type in se");
}

