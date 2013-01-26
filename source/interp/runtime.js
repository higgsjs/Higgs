/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2013, Maxime Chevalier-Boisvert. All rights reserved.
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
function assert(test, errorMsg)
{
    if ($ir_if_true(test))
        return;

    var globalObj = $ir_get_global_obj();
    if (globalObj.Error != undefined)
        throw Error(errorMsg);

    throw errorMsg;
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
Test if a reference is of a given layout
*/
function $rt_refIsLayout(val, layoutId)
{
    return (
        $ir_ne_refptr(val, null) && 
        $ir_eq_i8($rt_obj_get_header(val), layoutId)
    );
}

/**
Test if a value is of a given layout
*/
function $rt_valIsLayout(val, layoutId)
{
    return (
        $ir_is_refptr(val) &&
        $ir_ne_refptr(val, null) && 
        $ir_eq_i8($rt_obj_get_header(val), layoutId)
    );
}

/**
Test if a value is a string
*/
function $rt_isString(val)
{
    return (
        $ir_is_refptr(val) && 
        $ir_ne_refptr(val, null) && 
        $rt_refIsLayout(val, $rt_LAYOUT_STR)
    );
}

/**
Test if a value is an object
*/
function $rt_valIsObj(val)
{
    return (
        $ir_is_refptr(val) && 
        $ir_ne_refptr(val, null) && (
            $ir_eq_i8($rt_obj_get_header(val), $rt_LAYOUT_OBJ) ||
            $ir_eq_i8($rt_obj_get_header(val), $rt_LAYOUT_ARR) ||
            $ir_eq_i8($rt_obj_get_header(val), $rt_LAYOUT_CLOS)
        )
    );
}

/**
Test if a value is the global object
*/
function $rt_isGlobalObj(val)
{
    return $ir_is_refptr(val) && $ir_eq_refptr(val, $ir_get_global_obj());
}

/**
Allocate and initialize a closure cell
*/
function $rt_makeClosCell()
{
    var cell = $rt_cell_alloc();
    return cell;
}

/**
Set the value stored in a closure cell
*/
function $rt_setCellVal(cell, val)
{
    var word = $ir_get_word(val);
    var type = $ir_get_type(val);

    $rt_cell_set_word(cell, word);
    $rt_cell_set_type(cell, type);
}

/**
Get the value stored in a closure cell
*/
function $rt_getCellVal(cell)
{
    var word = $rt_cell_get_word(cell);
    var type = $rt_cell_get_type(cell);

    return $ir_set_value(word, type);
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
Compute the integer value of a string
*/
function $rt_strToInt(strVal)
{
    assert (
        typeof strVal === 'string',
        'expected string value in strToInt'
    );

    // TODO: add radix support

    // TODO: add floating-point support

    var strLen = $rt_str_get_len(strVal);

    var intVal = 0;

    var neg = false;

    var state = 'PREWS';

    // For each string character
    for (var i = 0; i < strLen;)
    {
        var ch = $rt_str_get_data(strVal, i);

        switch (state)
        {
            case 'PREWS':
            {
                // space or tab
                if (ch === 32 || ch === 9)
                {
                    ++i;
                }

                // + or -
                else if (ch === 43 || ch === 45)
                {
                    state = 'SIGN';
                }

                // Any other character
                else
                {
                    state = 'DIGITS';
                }
            }
            break;

            case 'SIGN':
            {
                // Plus sign
                if (ch === 43)
                {
                    ++i;
                }

                // Minus sign
                else if (ch === 45)
                {
                    neg = true;
                    ++i;
                }

                state = 'DIGITS';
            }
            break;

            case 'DIGITS':
            {
                if (ch < 48 || ch > 57)
                {
                    state = 'POSTWS';
                    continue;
                }

                var digit = ch - 48;

                intVal = 10 * intVal + digit;

                ++i;
            }
            break;

            case 'POSTWS':
            {
                // If this is not a space or tab
                if (ch !== 32 && ch !== 9)
                {
                    // Invalid number
                    return NaN;
                }

                ++i;
            }
            break;
        }
    }

    if (neg)
        intVal *= -1;

    return intVal;
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
        if ($ir_is_int(v))
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

            return $ir_f64_to_str(v);
        }
    }

    if (type === "object")
        return v? v.toString():"null";

    if (type === "function" || type === "array")
        return v.toString();

    assert (false, "unhandled type in toString");
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
        if ($ir_eq_refptr(v, null))
            return false;

        var type = $rt_obj_get_header(v);

        if ($ir_eq_i8(type, $rt_LAYOUT_STR))
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
Attempt to convert a value to a number. If this fails, return NaN
*/
function $rt_toNumber(v)
{
    if ($ir_is_int(v) || $ir_is_float(v))
        return v;

    if (v === null)
        return 0;

    if (v === true)
        return 1;

    if (v === false)
        return 0;

    if ($ir_is_refptr(v))
    {
        var type = $rt_obj_get_header(v);

        if ($ir_eq_i8(type, $rt_LAYOUT_STR))
            return $rt_strToInt(v);

        if ($rt_valIsObj(v))
            return $rt_toNumber($rt_toString(v));
    }

    return NaN;
}

/**
Convert any value to a signed 32-bit integer
*/
function $rt_toInt32(x)
{
    x = $rt_toNumber(x);

    if ($ir_is_int(x))
        return x;

    var x = (x>0)? $ir_floor_f64(x):(-$ir_floor_f64(-x));

    if ($ir_is_int(x))
        return x;

    assert (false, "unsupported value in toInt32");
}

/**
Convert any value to an unsigned 32-bit integer
*/
function $rt_toUint32(x)
{
    x = $rt_toNumber(x);

    if ($ir_is_int(x))
        return x;

    var x = (x>0)? $ir_floor_f64(x):$ir_floor_f64(-x);

    if ($ir_is_int(x))
        return x;

    assert (false, "unsupported value in toUInt32");
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
    }

    if ($ir_is_refptr(v))
    {
        if ($ir_eq_refptr(v, null))
            return "object";

        var type = $rt_obj_get_header(v);

        if ($ir_eq_i8(type, $rt_LAYOUT_STR))
            return "string";

        if ($ir_eq_i8(type, $rt_LAYOUT_OBJ) || $ir_eq_i8(type, $rt_LAYOUT_ARR))
            return "object";

        if ($ir_eq_i8(type, $rt_LAYOUT_CLOS))
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

    // Convert the operands to integers
    return $ir_lsft_i32($rt_toUint32(x), $rt_toUint32(y));
}

function $rt_rsft(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_rsft_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_rsft_i32($rt_toInt32(x), $rt_toUint32(y));
}

function $rt_ursft(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        return $ir_ursft_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_ursft_i32($rt_toUint32(x), $rt_toUint32(y));
}

function $rt_not(x)
{
    if ($ir_is_int(x))
    {
        return $ir_not_i32(x);
    }

    assert (false, "unsupported type in bitwise not");
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

    assert (false, "unsupported type in gt");
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

    assert (false, "unsupported type in ge");
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

        if ($ir_eq_i8(tx, $rt_LAYOUT_STR) && $ir_eq_i8(ty, $rt_LAYOUT_STR))
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

        if ($ir_eq_i8(tx, $rt_LAYOUT_STR) && $ir_eq_i8(ty, $rt_LAYOUT_STR))
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

    assert (false, "unsupported type in ne");
}

/**
JS strict equality (===) comparison operator
*/
function $rt_se(x, y)
{
    // If x is integer
    if ($ir_is_int(x))
    {
        if ($ir_is_int(y))
            return $ir_eq_i32(x, y);

        if ($ir_is_float(y))
            return $ir_eq_f64($ir_i32_to_f64(x), y);

        return false;
    }

    // If x is a reference
    else if ($ir_is_refptr(x))
    {
        if ($ir_is_refptr(y))
            return $ir_eq_refptr(x, y);

        return false;
    }

    // If x is a constant
    else if ($ir_is_const(x))
    {
        if ($ir_is_const(y))
            return $ir_eq_const(x, y);

        return false;
    }

    // If x is a float
    else if ($ir_is_float(x))
    {
        if ($ir_is_float(y))
            return $ir_eq_f64(x, y);

        if ($ir_is_int(x))
            return $ir_eq_f64(x, $ir_i32_to_f64(y));

        return false;
    }

    throw TypeError("unsupported types in strict equality comparison");
}

/**
JS strict inequality (!==) comparison operator
*/
function $rt_ne(x, y)
{
    // If x is integer
    if ($ir_is_int(x))
    {
        if ($ir_is_int(y))
            return $ir_ne_i32(x, y);

        if ($ir_is_float(y))
            return $ir_ne_f64($ir_i32_to_f64(x), y);

        return true;
    }

    // If x is a reference
    else if ($ir_is_refptr(x))
    {
        if ($ir_is_refptr(y))
            return $ir_ne_refptr(x, y);

        return true;
    }

    // If x is a constant
    else if ($ir_is_const(x))
    {
        if ($ir_is_const(y))
            return $ir_ne_const(x, y);
        
        return true;
    }

    // If x is a float
    else if ($ir_is_float(x))
    {
        if ($ir_is_float(y))
            return $ir_ne_f64(x, y);

        if ($ir_is_int(x))
            return $ir_ne_f64(x, $ir_i32_to_f64(y));

        return true;
    }

    throw TypeError("unsupported types in strict inequality comparison");
}

//=============================================================================
// Object allocation
//=============================================================================

/**
Initial class size (number of slots)
*/
var $rt_CLASS_INIT_SIZE = 128;

/**
Maximum class hash table load
*/
var $rt_CLASS_MAX_LOAD_NUM = 3;
var $rt_CLASS_MAX_LOAD_DENOM = 5;

/**
Initial number of object properties on class allocation
*/
var $rt_OBJ_INIT_SIZE = 1;

/**
Allocate an object, array or closure
*/
function $rt_getClass(classLink, classInitSize)
{
    // Get the class pointer
    var classPtr = classLink? $ir_get_link(classLink):null;

    //$ir_print_str("Got link\n");

    // If the class is not yet allocated
    if (classPtr === null)
    {
        //$ir_print_str("Getting class\n");

        // Lazily allocate the class
        classPtr = $rt_class_alloc(classInitSize);
        $rt_class_set_id(classPtr, 0);

        //$ir_print_str("Got class\n");

        // Update the instruction's class pointer
        if (classLink !== null)
            $ir_set_link(classLink, classPtr);
    }    

    return classPtr;
}

/**
Allocate an empty object
*/
function $rt_newObj(classLink, protoPtr)
{
    //$ir_print_str("Allocating object\n");

    // Get the class pointer
    var classPtr = $rt_getClass(classLink, $rt_CLASS_INIT_SIZE);

    // Get the number of properties to allocate from the class
    var numProps = $rt_class_get_num_props(classPtr);
    if (numProps === 0)
        numProps = $rt_OBJ_INIT_SIZE;

    // Allocate the object
    var objPtr = $rt_obj_alloc(numProps);

    // Initialize the object
    $rt_obj_set_class(objPtr, classPtr);
    $rt_obj_set_proto(objPtr, protoPtr);

    //$ir_print_str("Allocated object\n");

    return objPtr;
}

/**
Allocate an array
*/
function $rt_newArr(classLink, protoPtr, numElems)
{
    //$ir_print_str("Allocating array\n");

    // Get the class pointer
    var classPtr = $rt_getClass(classLink, $rt_CLASS_INIT_SIZE);

    //$ir_print_str("Got class\n");

    // Get the number of properties to allocate from the class
    var numProps = $rt_class_get_num_props(classPtr);
    if (numProps === 0)
        numProps = $rt_OBJ_INIT_SIZE;

    //$ir_print_str("Allocating table\n");

    // Allocate the array table
    var tblPtr = $rt_arrtbl_alloc(numElems);

    //$ir_print_str("Allocating array\n");

    // Allocate the array
    var objPtr = $rt_arr_alloc(numProps);

    // Initialize the object
    $rt_obj_set_class(objPtr, classPtr);
    $rt_obj_set_proto(objPtr, protoPtr);
    $rt_arr_set_tbl(objPtr, tblPtr);
    $rt_arr_set_len(objPtr, 0);

    //$ir_print_str("Allocated array\n");

    return objPtr;
}

/**
Create a new closure/function object
*/
function $rt_newClos(classLink, protoLink, numCells, funPtr)
{
    // Get the class pointer
    var classPtr = $rt_getClass(classLink, $rt_CLASS_INIT_SIZE);

    // Get the number of properties to allocate from the class
    var numProps = $rt_class_get_num_props(classPtr);
    if (numProps === 0)
        numProps = $rt_OBJ_INIT_SIZE;

    // Allocate the closure
    var closPtr = $rt_clos_alloc(numProps, numCells);

    // Initialize the closure
    $rt_obj_set_class(closPtr, classPtr);
    $rt_obj_set_proto(closPtr, $ir_get_fun_proto());

    // Set the function pointer
    $rt_clos_set_fptr(closPtr, funPtr);

    // Allocate the prototype object
    var objPtr = $rt_newObj(protoLink, $ir_get_obj_proto());

    // Set the prototype property on the closure object
    closPtr.prototype = objPtr;

    return closPtr;
}

/**
Shrink the heap for GC testing purposes
*/
function $rt_shrinkHeap(freeSpace)
{
    assert (
        freeSpace > 0,
        'invalid free space value'
    );

    $ir_gc_collect(0);

    var heapFree = $ir_get_heap_free();
    var heapSize = $ir_get_heap_size();

    var newSize = heapSize - (heapFree - freeSpace);
    $ir_gc_collect(newSize);
}

//=============================================================================
// Objects and property access
//=============================================================================

/**
Find or allocate the property index for a given property name string
*/
function $rt_getPropIdx(classPtr, propStr, alloc)
{
    // Get the size of the property table
    var tblSize = $rt_class_get_cap(classPtr);

    // Get the hash code from the property string
    var hashCode = $rt_str_get_hash(propStr);

    // Get the hash table index for this hash value
    var hashIndex = $ir_mod_i32(hashCode, tblSize);

    // Until the key is found, or a free slot is encountered
    while (true)
    {
        // Get the string value at this hash slot
        var strVal = $rt_class_get_prop_name(classPtr, hashIndex);

        // If this is the string we want
        if ($ir_eq_refptr(strVal, propStr))
        {
            // Return the associated property index
            return $rt_class_get_prop_idx(classPtr, hashIndex);
        }

        // If we have reached an empty slot
        else if ($ir_eq_refptr(strVal, null))
        {
            // Property not found
            break;
        }

        // Move to the next hash table slot
        hashIndex = $ir_mod_i32($ir_add_i32(hashIndex, 1), tblSize);
    }

    // If we are not to allocate new property indices, stop
    if ($ir_if_false(alloc))
        return false;

    // Get the number of class properties
    var numProps = $rt_class_get_num_props(classPtr);

    // Set the property name and index
    var propIdx = numProps;
    $rt_class_set_prop_name(classPtr, hashIndex, propStr);
    $rt_class_set_prop_idx(classPtr, hashIndex, propIdx);

    // Update the number of class properties
    numProps = $ir_add_i32(numProps, 1);
    $rt_class_set_num_props(classPtr, numProps);

    // Test if resizing of the property table is needed
    // numProps > ratio * tblSize
    // numProps > num/denom * tblSize
    // numProps * denom > tblSize * num
    if (numProps * $rt_CLASS_MAX_LOAD_DENOM >
        tblSize  * $rt_CLASS_MAX_LOAD_NUM)
    {
        // Extend the property table
        // TODO
        assert (false, "class capacity exceeded");
    }

    return propIdx;
}

/**
Get a property from an object using a string as key
*/
function $rt_getPropObj(obj, propStr)
{
    // Follow the next link chain
    for (;;)
    {
        var next = $rt_obj_get_next(obj);
        if ($ir_eq_refptr(next, null))
            break;
        obj = next;
    }

    // Find the index for this property
    var propIdx = $rt_getPropIdx($rt_obj_get_class(obj), propStr, false);

    // If the property was found
    if ($ir_is_int(propIdx))
    {
        var word = $rt_obj_get_word(obj, propIdx);
        var type = $rt_obj_get_type(obj, propIdx);
        var val = $ir_set_value(word, type);

        // If the value is not missing, return it
        if (val !== $ir_set_missing())
            return val;
    }

    // Get the object's prototype
    var proto = $rt_obj_get_proto(obj);

    // If the prototype is null, produce undefined
    if ($ir_eq_refptr(proto, null))
        return $ir_set_undef();

    // Do a recursive lookup on the prototype
    return $rt_getPropObj(
        proto,
        propStr
    );
}

/**
Get a property from a value using a value as a key
*/
function $rt_getProp(base, prop)
{
    // If the base is a reference
    if ($ir_is_refptr(base) && $ir_ne_refptr(base, null))
    {
        var type = $rt_obj_get_header(base);

        // If the base is an object or closure
        if ($ir_eq_i8(type, $rt_LAYOUT_OBJ) ||
            $ir_eq_i8(type, $rt_LAYOUT_CLOS))
        {
            // If the property is a string
            if ($rt_isString(prop))
                return $rt_getPropObj(base, prop);

            return $rt_getPropObj(base, $rt_toString(prop));
        }

        // If the base is an array
        if ($ir_eq_i8(type, $rt_LAYOUT_ARR))
        {
            // If the property is a non-negative integer
            if ($ir_is_int(prop) && $ir_ge_i32(prop, 0) &&
                $ir_lt_i32(prop, $rt_arr_get_len(base)))
            {
                var tbl = $rt_arr_get_tbl(base);
                var word = $rt_arrtbl_get_word(tbl, prop);
                var type = $rt_arrtbl_get_type(tbl, prop);
                return $ir_set_value(word, type);
            }

            // If this is the length property
            if (prop === 'length')
                return $rt_arr_get_len(base);

            // If the property is a string
            if ($rt_isString(prop))
                return $rt_getPropObj(base, prop);

            return $rt_getPropObj(base, $rt_toString(prop));
        }

        // If the base is a string
        if ($ir_eq_i8(type, $rt_LAYOUT_STR))
        {
            // If the property is a non-negative integer
            if ($ir_is_int(prop) && $ir_ge_i32(prop, 0) && 
                $ir_lt_i32(prop, $rt_str_get_len(base)))
            {
                var ch = $rt_str_get_data(base, prop);
                var str = $rt_str_alloc(1);
                $rt_str_set_data(str, 0, ch);
                return $ir_get_str(str);
            }

            // If this is the length property
            if (prop === 'length')
                return $rt_str_get_len(base);

            // Recurse on String.prototype
            return $rt_getProp(String.prototype, prop);
        }
    }

    // If the base is a number
    if ($ir_is_int(base) || $ir_is_float(base))
    {
        // Recurse on Number.prototype
        return $rt_getProp(Number.prototype, prop);
    }

    // If the base is a boolean
    if (base === true || base === false)
    {
        // Recurse on Boolean.prototype
        return $rt_getProp(Boolean.prototype, prop);
    }

    // TODO: error on null, undefined

    //println(base);
    //println(prop);

    throw TypeError("invalid base in property read");
}

/**
Extend the internal array table of an array
*/
function $rt_extArrTbl(
    arr, 
    curTbl, 
    curLen, 
    curSize, 
    newSize
)
{
    //println("Extending array");

    // Allocate the new table without initializing it, for performance
    var newTbl = $rt_arrtbl_alloc(newSize);

    // Copy elements from the old table to the new
    for (var i = 0; i < curLen; i++)
    {
        $rt_arrtbl_set_word(newTbl, i, $rt_arrtbl_get_word(curTbl, i));
        $rt_arrtbl_set_type(newTbl, i, $rt_arrtbl_get_type(curTbl, i));
    }

    // Initialize the remaining table entries to undefined
    for (var i = curLen; i < newSize; i++)
    {
        $rt_arrtbl_set_word(newTbl, i, $ir_get_word(undefined));
        $rt_arrtbl_set_type(newTbl, i, $ir_get_type(undefined));
    }

    // Update the table reference in the array
    $rt_arr_set_tbl(arr, newTbl);

    //println("Extended array");

    return newTbl;
}

/**
Set an element of an array
*/
function $rt_setArrElem(arr, index, val)
{
    // Get the array length
    var len = $rt_arr_get_len(arr);

    // Get the array table
    var tbl = $rt_arr_get_tbl(arr);

    // If the index is outside the current size of the array
    if (index >= len)
    {
        // Compute the new length
        var newLen = index + 1;

        // Get the array capacity
        var cap = $rt_arrtbl_get_cap(tbl);

        // If the new length would exceed the capacity
        if (newLen > cap)
        {
            // Compute the new size to resize to
            var newSize = 2 * cap;
            if (newLen > newSize)
                newSize = newLen;

            // Extend the internal table
            tbl = $rt_extArrTbl(arr, tbl, len, cap, newSize);
        }

        // Update the array length
        $rt_arr_set_len(arr, newLen);
    }

    // Set the element in the array
    $rt_arrtbl_set_word(tbl, index, $ir_get_word(val));
    $rt_arrtbl_set_type(tbl, index, $ir_get_type(val));
}

/**
Set/change the length of an array
*/
function $rt_setArrLen(arr, newLen)
{
    // Get the current array length
    var len = $rt_arr_get_len(arr);

    // Get a reference to the array table
    var tbl = $rt_arr_get_tbl(arr);

    // If the array length is increasing
    if (newLen > len)
    {
        // Get the array capacity
        var cap = $rt_arrtbl_get_cap(tbl);

        // If the new length would exceed the capacity
        if (newLen > cap)
        {
            // Extend the internal table
            $rt_extArrTbl(arr, tbl, len, cap, newLen);
        }
    }
    else
    {
        // Initialize removed entries to undefined
        for (var i = newLen; i < len; i++)
        {
            $rt_arrtbl_set_word(tbl, i, $ir_get_word(undefined));
            $rt_arrtbl_set_type(tbl, i, $ir_get_type(undefined));
        }
    }

    // Update the array length
    $rt_arr_set_len(arr, newLen);
}

/**
Set a property on an object using a string as key
*/
function $rt_setPropObj(obj, propStr, val)
{
    // Follow the next link chain
    for (;;)
    {
        var next = $rt_obj_get_next(obj);
        if ($ir_eq_refptr(next, null))
            break;
        obj = next;
    }

    // Get the class from the object
    var classPtr = $rt_obj_get_class(obj);

    // Find the index for this property
    var propIdx = $rt_getPropIdx(classPtr, propStr, true);

    // Get the capacity of the object
    var objCap = $rt_obj_get_cap(obj);

    // If the object needs to be extended
    if (propIdx >= objCap)
    {
        //writeln("*** extending object ***");

        var objType = $rt_obj_get_header(obj);

        var newObj;

        // Switch on the layout type
        switch (objType)
        {
            case $rt_LAYOUT_OBJ:
            newObj = $rt_obj_alloc(objCap+1);
            break;

            case $rt_LAYOUT_CLOS:
            var numCells = $rt_clos_get_num_cells(obj);
            newObj = $rt_clos_alloc(objCap+1, numCells);
            $rt_clos_set_fptr(newObj, $rt_clos_get_fptr(obj));
            for (var i = 0; i < numCells; ++i)
                $rt_clos_set_cell(newObj, i, $rt_clos_get_cell(obj, i));
            break;

            case $rt_LAYOUT_ARR:
            newObj = $rt_arr_alloc(objCap+1);
            $rt_arr_set_len(newObj, $rt_arr_get_len(obj));
            $rt_arr_set_tbl(newObj, $rt_arr_get_tbl(obj));
            break;

            default:
            assert (false, "unhandled object type in setPropObj");
        }

        $rt_obj_set_class(newObj, classPtr);
        $rt_obj_set_proto(newObj, $rt_obj_get_proto(obj));

        // Copy over the property words and types
        for (var i = 0; i < objCap; ++i)
        {
            $rt_obj_set_word(newObj, i, $rt_obj_get_word(obj, i));
            $rt_obj_set_type(newObj, i, $rt_obj_get_type(obj, i));
        }

        // Set the next pointer in the old object
        $rt_obj_set_next(obj, newObj);

        // Update the object pointer
        obj = newObj;
    }

    // Set the value and its type in the object
    $rt_obj_set_word(obj, propIdx, $ir_get_word(val));
    $rt_obj_set_type(obj, propIdx, $ir_get_type(val));
}

/**
Set a property on a value using a value as a key
*/
function $rt_setProp(base, prop, val)
{
    //print(prop);
    //print('\n');

    // If the base is a reference
    if ($ir_is_refptr(base) && $ir_ne_refptr(base, null))
    {
        var type = $rt_obj_get_header(base);

        // If the base is an object or closure
        if ($ir_eq_i8(type, $rt_LAYOUT_OBJ) ||
            $ir_eq_i8(type, $rt_LAYOUT_CLOS))
        {
            // If the property is a string
            if ($rt_isString(prop))
                return $rt_setPropObj(base, prop, val);

            return $rt_setPropObj(base, $rt_toString(prop), val);
        }

        // If the base is an array
        if ($ir_eq_i8(type, $rt_LAYOUT_ARR))
        {
            // If the property is a non-negative integer
            if ($ir_is_int(prop) && $ir_ge_i32(prop, 0))
                return $rt_setArrElem(base, prop, val);            

            // If this is the length property
            if (prop === 'length')
            {
                if ($ir_is_int(val) && $ir_ge_i32(val, 0))
                    return $rt_setArrLen(base, val);

                assert (false, 'invalid array length');
            }

            // If the property is a string
            if ($rt_isString(prop))
                return $rt_setPropObj(base, prop, val);

            return $rt_setPropObj(base, $rt_toString(prop), val);
        }
    }

    //println(typeof base);
    //println(base);
    //println(prop);

    throw TypeError("invalid base in property write");
}

/**
Implementation of the "instanceof" operator
*/
function $rt_instanceof(obj, ctor)
{ 
    if (!$rt_valIsLayout(ctor, $rt_LAYOUT_CLOS))
        throw TypeError('constructor must be function');

    // If the value is not an object
    if ($rt_valIsObj(obj) === false)
    {
        // Return the false value
        return false;
    }

    // Get the prototype for the constructor function
    var ctorProto = ctor.prototype;

    // Until we went all the way through the prototype chain
    do
    {
        var objProto = $rt_obj_get_proto(obj);

        if ($ir_eq_refptr(objProto, ctorProto))
            return true;

        obj = objProto;

    } while ($ir_ne_refptr(obj, null));

    return false;
}

/**
Check if an object has a given property
*/
function $rt_hasPropObj(obj, propStr)
{
    // Follow the next link chain
    for (;;)
    {
        var next = $rt_obj_get_next(obj);
        if ($ir_eq_refptr(next, null))
            break;
        obj = next;
    }

    var classPtr = $rt_obj_get_class(obj);
    var propIdx = $rt_getPropIdx(classPtr, propStr, false);
    if (propIdx === false)
        return false;

    // Check that the property is not missing
    var word = $rt_obj_get_word(obj, propIdx);
    var type = $rt_obj_get_type(obj, propIdx);
    var val = $ir_set_value(word, type);
    return (val !== $ir_set_missing());
}

/**
Check if a value has a given property
*/
function $rt_hasOwnProp(base, prop)
{
    // If the base is a reference
    if ($ir_is_refptr(base) && $ir_ne_refptr(base, null))
    {
        var type = $rt_obj_get_header(base);

        // If the base is an object or closure
        if ($ir_eq_i8(type, $rt_LAYOUT_OBJ) ||
            $ir_eq_i8(type, $rt_LAYOUT_CLOS))
        {
            // If the property is a string
            if ($rt_isString(prop))
                return $rt_hasPropObj(base, prop);

            return $rt_hasPropObj(base, $rt_toString(prop));
        }

        // If the base is an array
        if ($ir_eq_i8(type, $rt_LAYOUT_ARR))
        {
            // If the property is a non-negative integer
            if ($ir_is_int(prop) && $ir_ge_i32(prop, 0) &&
                $ir_lt_i32(prop, $rt_arr_get_len(base)))
                return true;

            // If this is the length property
            if (prop === 'length')
                return true;

            // If the property is a string
            if ($rt_isString(prop))
                return $rt_hasPropObj(base, prop);

            return $rt_hasPropObj(base, $rt_toString(prop));
        }
    }

    assert (false, "unsupported base in hasOwnProp");
}

/**
Implementation of the "in" operator
*/
function $rt_in(prop, obj)
{
    if (!$rt_valIsObj(obj))
        throw TypeError('invalid object passed to "in" operator');

    // Until we went all the way through the prototype chain
    do
    {
        if ($rt_hasOwnProp(obj, prop))
            return true;

        obj = $rt_obj_get_proto(obj);

    } while ($ir_ne_refptr(obj, null));

    return false;
}

/**
Used to enumerate properties in a for-in loop
*/
function $rt_getPropEnum(obj)
{ 
    // If the value is not an object or a string
    if ($rt_valIsObj(obj) === false && 
        $rt_valIsLayout(obj, $rt_LAYOUT_STR) === false)
    {
        // Return the empty enumeration function
        return function ()
        {
            return false;
        };
    }

    var curObj = obj;
    var curIdx = 0;

    // Check if a property is currently shadowed
    function isShadowed(propName)
    {
        // TODO: shadowing check function?
        return false;
    }

    // Move to the next available property
    function nextProp()
    {
        while (true)
        {
            // FIXME: for now, no support for non-enumerable properties
            if (curObj === Object.prototype     || 
                curObj === Array.prototype      || 
                curObj === Function.prototype   ||
                curObj === String.prototype)
                return false;

            // If we are at the end of the prototype chain, stop
            if (curObj === null)
                return false;

            // If the current object is an object or extension
            if ($rt_valIsObj(curObj))
            {
                var classPtr = $rt_obj_get_class(curObj);
                var tblSize = $rt_class_get_cap(classPtr);

                // Until the key is found, or a free slot is encountered
                for (; curIdx < tblSize; ++curIdx)
                {
                    // Get the key value at this hash slot
                    var keyVal = $rt_class_get_prop_name(classPtr, curIdx);

                    // FIXME: until we have support for non-enumerable properties
                    if (keyVal === 'length' ||
                        keyVal === 'callee')
                    {
                        ++curIdx;
                        continue;
                    }

                    // If this is a valid key, return it
                    if (keyVal !== null && $rt_hasOwnProp(curObj, keyVal))
                    {
                        ++curIdx;
                        return keyVal;
                    }
                }

                // If the object is an array
                if ($rt_valIsLayout(curObj, $rt_LAYOUT_ARR))
                {
                    var arrIdx = curIdx - tblSize;
                    var len = curObj.length;

                    if (arrIdx < len)
                    {
                        ++curIdx;
                        return arrIdx;
                    }
                }

                // Move up the prototype chain
                curObj = $rt_obj_get_proto(curObj);
                curIdx = 0;
                continue;
            }

            // If the object is a string
            else if ($rt_valIsLayout(curObj, $rt_LAYOUT_STR))
            {
                var len = curObj.length;

                if (curIdx < len)
                {
                    return curIdx++;
                }
                else
                {
                    // Move up the prototype chain
                    curObj = String.prototype;
                    curIdx = 0;
                    continue;
                }
            }

            else
            {
                return false;
            }
        }
    }

    // Enumerator function, returns a new property name with
    // each call, undefined when no more properties found
    function enumerator()
    {
        while (true)
        {
            var propName = nextProp();

            if (isShadowed(propName))
                continue;

            return propName;
        }
    }

    return enumerator;
}

