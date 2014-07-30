/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2014, Maxime Chevalier-Boisvert. All rights reserved.
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
$ir_shape_def_const(this, 'undefined', $undef, false);

/**
Not-a-number value
*/
$ir_shape_def_const(this, 'NaN', $ir_div_f64(0.0, 0.0), false);

/**
Infinity value
*/
$ir_shape_def_const(this, 'Infinity', $ir_div_f64(1.0, 0.0), false);

/**
Test if a value is NaN
*/
function isNaN(v)
{
    if ($ir_is_f64(v))
        return $ir_ne_f64(v,v);

    var n = $rt_toNumber(v);
    return ($ir_is_f64(n) && $ir_ne_f64(n, n));
}

/**
Load and execute a source file
*/
function load(fileName)
{
    if (!$ir_is_string(fileName))
        throw TypeError("expected filename string argument");

    return $ir_load_file(fileName);
}

/**
Evaluate a source string in the global scope
*/
function eval(input)
{
    if ($ir_is_string(input))
        return $ir_eval_str(input);

    return input;
}

/**
Print a value to the console
*/
function print()
{
    // For each argument
    for (var i = 0; i < $argc; ++i)
    {
        var arg = $ir_get_arg(i);

        // Convert the value to a string if it isn't one
        if (!$ir_is_string(arg))
            arg = $rt_toString(arg);

        // Print the string
        $ir_print_str(arg);
    }

    // Print a final newline
    $ir_print_str('\n');
}

/**
Perform an assertion test
*/
function assert(testVal, errorMsg)
{
    if ($ir_is_const(testVal) && $ir_eq_const(testVal, true))
        return;

    // If no error message is specified
    if ($argc < 2)
        errorMsg = 'assertion failed';

    // If the global Error object exists
    if (this.Error !== $undef)
        throw Error(errorMsg);

    // Throw the error message as-is
    $ir_throw(errorMsg);
}

/**
Throw an exception value
Note: this primitive makes exception handling simpler as the
throw instruction will always unwind at least one stack frame.
*/
function $rt_throwExc(excVal)
{
    $ir_throw(excVal);
}

/**
Test if a value is an object
*/
function $rt_valIsObj(val)
{
    return ($ir_is_object(val) || $ir_is_array(val) || $ir_is_closure(val));
}

/**
Test if a value is the global object
*/
function $rt_isGlobalObj(val)
{
    return $ir_is_object(val) && $ir_eq_refptr(val, $ir_get_global_obj());
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

    //print('getCellVal: ' + $ir_make_value(word, 0));

    return $ir_make_value(word, type);
}

/**
Concatenate the strings from two string objects
*/
function $rt_strcat(strA, strB)
{
    // Get the length of both strings
    var lenA = $rt_str_get_len(strA);
    var lenB = $rt_str_get_len(strB);

    // Allocate a string object
    var lenO = $ir_add_i32(lenA, lenB);
    var strO = $rt_str_alloc(lenO);

    // Copy the character data from the first string
    for (var i = 0; $ir_lt_i32(i, lenA); i = $ir_add_i32(i, 1))
    {
        var ch = $rt_str_get_data(strA, i);
        $rt_str_set_data(strO, i, ch);
    }

    // Copy the character data from the second string
    for (var i = 0; $ir_lt_i32(i, lenB); i = $ir_add_i32(i, 1))
    {
        var ch = $rt_str_get_data(strB, i);
        $rt_str_set_data(strO, $ir_add_i32(lenA, i), ch);
    }

    // Find/add the concatenated string in the string table
    return $ir_get_str(strO);
}

/**
Compare two string objects lexicographically by iterating over UTF-16
code units. This conforms to section 11.8.5 of the ECMAScript 262
specification.
*/
function $rt_strcmp(strA, strB)
{
    // Get the length of both strings
    var lenA = $rt_str_get_len(strA);
    var lenB = $rt_str_get_len(strB);

    // Compute the minimum of both string lengths
    var minLen = $ir_lt_i32(lenA, lenB)? lenA:lenB;

    // For each character to be compared
    for (var i = 0; $ir_lt_i32(i, minLen); i = $ir_add_i32(i, 1))
    {
        var ch1 = $rt_str_get_data(strA, i);
        var ch2 = $rt_str_get_data(strB, i);

        if ($ir_lt_i32(ch1, ch2))
            return -1;
        if ($ir_gt_i32(ch1, ch2))
            return 1;
    }

    if ($ir_lt_i32(lenA, lenB))
        return -1;
    if ($ir_gt_i32(lenB, lenA))
        return 1;
    return 0;
}

/**
Create a string representing an integer value
*/
function $rt_intToStr(intVal, radix)
{
    assert (
        $ir_is_i32(radix)    &&
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
        strLen = $ir_add_i32(strLen, 1);
        intVal2 = $ir_div_i32(intVal2, radix);

    } while ($ir_ne_i32(intVal2, 0));

    // Allocate a string object
    var strObj = $rt_str_alloc(strLen);

    // If the string is negative, write the minus sign
    if ($ir_eq_const(neg, true))
    {
        $rt_str_set_data(strObj, 0, 45);
    }

    var digits = '0123456789abcdefghijklmnopqrstuvwxyz';

    // Write the digits in the string
    var i = $ir_sub_i32(strLen, 1);
    do
    {
        var digit = $ir_mod_i32(intVal, radix);

        var ch = $rt_str_get_data(digits, digit);

        $rt_str_set_data(strObj, i, ch);

        intVal = $ir_div_i32(intVal, radix);

        i = $ir_sub_i32(i, 1);

    } while ($ir_ne_i32(intVal, 0));

    // Get the corresponding string from the string table
    return $ir_get_str(strObj);
}

/**
Compute the integer value of a string
*/
function $rt_strToInt(strVal)
{
    // TODO: add radix support

    // TODO: add floating-point support

    var strLen = $rt_str_get_len(strVal);

    var intVal = 0;
    var neg = false;
    var state = 'PREWS';

    // For each string character
    for (var i = 0; $ir_lt_i32(i, strLen);)
    {
        var ch = $rt_str_get_data(strVal, i);

        if ($ir_eq_refptr(state, 'PREWS'))
        {
            // Space or tab
            if ($ir_eq_i32(ch, 32) || $ir_eq_i32(ch, 9))
            {
                i = $ir_add_i32(i, 1);
            }

            // + or -
            else if ($ir_eq_i32(ch, 43) || $ir_eq_i32(ch, 45))
            {
                state = 'SIGN';
            }

            // Any other character
            else
            {
                state = 'DIGITS';
            }
        }
        else if ($ir_eq_refptr(state, 'SIGN'))
        {
            // Plus sign
            if ($ir_eq_i32(ch, 43))
            {
                i = $ir_add_i32(i, 1);
            }

            // Minus sign
            else if ($ir_eq_i32(ch, 45))
            {
                neg = true;
                i = $ir_add_i32(i, 1);
            }

            state = 'DIGITS';
        }
        else if ($ir_eq_refptr(state, 'DIGITS'))
        {
            // If this is not a digit
            if ($ir_lt_i32(ch, 48) || $ir_gt_i32(ch, 57))
            {
                state = 'POSTWS';
                continue;
            }

            var digit = ch - 48;

            intVal = 10 * intVal + digit;

            i = $ir_add_i32(i, 1);
        }
        else if ($ir_eq_refptr(state, 'POSTWS'))
        {
            // If this is not a space or tab
            if ($ir_ne_i32(ch, 32) && $ir_ne_i32(ch, 9))
            {
                // Invalid number
                return NaN;
            }

            i = $ir_add_i32(i, 1);
        }
    }

    if ($ir_eq_const(neg, true))
        intVal *= -1;

    return intVal;
}

/**
Get the string representation of a value
*/
function $rt_toString(v)
{
    if ($rt_valIsObj(v))
    {
        var str = v.toString();

        if ($ir_is_string(str))
            return str;

        if ($rt_valIsObj(str))
            throw TypeError('toString produced non-primitive value');

        return $rt_toString(str);
    }

    if ($ir_is_i32(v) || $ir_is_f64(v))
    {
        return $rt_numberToString(v, 10);
    }

    if ($ir_is_string(v))
    {
        return v;
    }

    if ($ir_is_const(v))
    {
        if ($ir_eq_const(v, $undef))
            return "undefined";

        if ($ir_eq_const(v, true))
            return "true";

        if ($ir_eq_const(v, false))
            return "false";
    }

    if ($ir_is_refptr(v) && $ir_eq_refptr(v, null))
    {
        return "null";
    }

    assert (false, "unhandled type in toString");
}

/**
Convert number to string
*/
function $rt_numberToString(v, radix)
{
    if (!$ir_is_i32(radix))
    {
        radix = 10;
    }

    if (radix < 2 || radix > 36)
    {
        throw RangeError("radix is not between 2 and 36");
    }

    if ($ir_is_i32(v))
    {
        return $rt_intToStr(v, radix);
    }

    // NaN
    if ($ir_ne_f64(v, v))
        return "NaN";
    if (v === Infinity)
        return "Infinity";
    if (v === -Infinity)
        return "-Infinity";

    return $ir_f64_to_str(v);
}

/**
Convert a boxed value to a primitive value.
*/
function $rt_toPrim(v)
{
    if ($ir_is_i32(v) ||
        $ir_is_f64(v) ||
        $ir_is_const(v))
        return v

    if ($ir_is_refptr(v) && $ir_eq_refptr(v, null))
        return v;

    if ($ir_is_string(v))
        return v;

    if ($ir_is_object(v) || $ir_is_array(v) || $ir_is_closure(v))
    {
        var str = v.toString();

        if ($ir_is_refptr(str) && $ir_ne_refptr(str, null) && !$ir_is_string(str))
            throw TypeError('toString produced non-primitive value');

        return str;
    }

    throw TypeError('unexpected type in toPrimitive');
}

/**
Evaluate a value as a boolean
*/
function $rt_toBool(v)
{
    if ($ir_is_const(v))
        return $ir_eq_const(v, true);

    if ($ir_is_i32(v))
        return $ir_ne_i32(v, 0);

    if ($ir_is_f64(v))
        return $ir_ne_f64(v, 0.0);

    if ($ir_is_refptr(v) && $ir_eq_refptr(v, null))
        return false;

    if ($ir_is_string(v))
        return $ir_gt_i32($rt_str_get_len(v), 0);

    if ($ir_is_object(v) || $ir_is_array(v) || $ir_is_closure(v))
        return true;

    if ($ir_is_rawptr(v))
        return $ir_ne_rawptr(v, $nullptr);

    return false;
}

/**
Specialized version of toBool for constant types
*/
function $rt_toBoolConst(v)
{
    if ($ir_is_const(v))
        return $ir_eq_const(v, true);

    return $rt_toBool(v);
}

/**
Attempt to convert a value to a number. If this fails, return NaN
*/
function $rt_toNumber(v)
{
    if ($ir_is_i32(v) || $ir_is_f64(v))
        return v;

    if ($ir_is_refptr(v) && $ir_eq_refptr(v, null))
        return 0;

    if ($ir_is_const(v))
    {
        if ($ir_eq_const(v, true))
            return 1;

        if ($ir_eq_const(v, false))
            return 0;
    }

    if ($ir_is_string(v))
        return $rt_strToInt(v);

    if ($rt_valIsObj(v))
        return $rt_toNumber($rt_toString(v));

    return NaN;
}

/**
Convert any value to a signed 32-bit integer
*/
function $rt_toInt32(x)
{
    x = $rt_toNumber(x);

    if ($ir_is_i32(x))
        return x;

    // NaN or infinity
    if ($ir_ne_f64(x, x) || x === Infinity || x === -Infinity)
        return 0;

    return $ir_f64_to_i32(x);
}

/**
Convert any value to an unsigned 32-bit integer
*/
function $rt_toUint32(x)
{
    x = $rt_toNumber(x);

    if ($ir_is_i32(x))
        return x;

    // NaN or infinity
    if ($ir_ne_f64(x, x) || x === Infinity || x === -Infinity)
        return 0;

    if ($ir_ge_i32(x, 0.0))
        return $ir_f64_to_i32(x);
    else
        return $ir_f64_to_i32($ir_sub_f64(0.0, x));
}

/**
JS typeof operator
*/
function $rt_typeof(v)
{
    if ($ir_is_i32(v) || $ir_is_f64(v))
        return "number";

    if ($ir_is_const(v))
    {
        if ($ir_eq_const(v, true) || $ir_eq_const(v, false))
            return "boolean";

        if ($ir_eq_const(v, undefined))
            return "undefined";
    }

    if ($ir_is_refptr(v) && $ir_eq_refptr(v, null))
        return "object";

    if ($ir_is_object(v) || $ir_is_array(v))
        return "object";

    if ($ir_is_closure(v))
        return "function";

    if ($ir_is_string(v))
        return "string";

    if ($ir_is_rawptr(v))
        return "rawptr";

    throw TypeError("unhandled type in typeof");
}

//=============================================================================
// Arithmetic operators
//=============================================================================

/**
JS unary plus (+) operator
*/
function $rt_plus(x)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        return x;
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        return x;
    }

    return $rt_toNumber(x);
}

/**
JS unary minus (-) operator
*/
function $rt_minus(x)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_eq_i32(x, 0))
            return -0;

        return $ir_sub_i32(0, x);
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        if ($ir_eq_f64(x, 0.0))
            return -0;

        return $ir_sub_f64(0.0, x);
    }

    return -1 * $rt_toNumber(x);
}

/**
JS addition operator
*/
function $rt_add(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
        {
            var r;
            if (r = $ir_add_i32_ovf(x, y))
            {
                return r;
            }
            else
            {
                // Handle the overflow case
                var fx = $ir_i32_to_f64(x);
                var fy = $ir_i32_to_f64(y);
                return $ir_add_f64(fx, fy);
            }
        }

        if ($ir_is_f64(y))
            return $ir_add_f64($ir_i32_to_f64(x), y);
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_add_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_add_f64(x, y);
    }

    // Convert x and y to primitives
    var px = $rt_toPrim(x);
    var py = $rt_toPrim(y);

    // If x is a string
    if ($ir_is_string(px))
    {
        return $rt_strcat(px, $rt_toString(y));
    }

    // If y is a string
    if ($ir_is_string(py))
    {
        return $rt_strcat($rt_toString(x), py);
    }

    // Convert both values to numbers and add them
    return $rt_add($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized add for the (int,int) case (e.g.: index increment)
*/
function $rt_addInt(x, y)
{
    // If x,y are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        var r;
        if (r = $ir_add_i32_ovf(x, y))
        {
            return r;
        }
        else
        {
            // Reconstruct x from r and y
            // Hence x is not live after the add
            x = r - y;
        }
    }

    return $rt_add(x, y);
}

/**
Specialized add for the (int,int) and (float,float) cases
*/
function $rt_addIntFloat(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
        {
            var r;
            if (r = $ir_add_i32_ovf(x, y))
            {
                return r;
            }
            else
            {
                // Handle the overflow case
                var fx = $ir_i32_to_f64(x);
                var fy = $ir_i32_to_f64(y);
                return $ir_add_f64(fx, fy);
            }
        }

        if ($ir_is_f64(y))
            return $ir_add_f64($ir_i32_to_f64(x), y);
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        if ($ir_is_f64(y))
            return $ir_add_f64(x, y);

        if ($ir_is_i32(y))
            return $ir_add_f64(x, $ir_i32_to_f64(y));
    }

    return $rt_add(x, y);
}

/**
JS subtraction operator
*/
function $rt_sub(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
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

        if ($ir_is_f64(y))
            return $ir_sub_f64($ir_i32_to_f64(x), y);
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        if ($ir_is_f64(y))
            return $ir_sub_f64(x, y);

        if ($ir_is_i32(y))
            return $ir_sub_f64(x, $ir_i32_to_f64(y));
    }

    return $rt_sub($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized sub for the (int,int) and (float,float) cases
*/
function $rt_subIntFloat(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
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

        if ($ir_is_f64(y))
            return $ir_sub_f64($ir_i32_to_f64(x), y);
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_sub_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_sub_f64(x, y);
    }

    return $rt_sub(x, y);
}

/**
Specialized subtract for the (int,int) case (e.g.: index decrement)
*/
function $rt_subInt(x, y)
{
    // If x,y are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        var r;
        if (r = $ir_sub_i32_ovf(x, y))
        {
            return r;
        }
    }

    return $rt_sub(x, y);
}

/**
JS multiplication operator
*/
function $rt_mul(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
        {
            // If this could produce negative 0
            if (($ir_lt_i32(x, 0) && $ir_eq_i32(y, 0)) || 
                ($ir_eq_i32(x, 0) && $ir_lt_i32(y, 0)))
            {
                var fx = $ir_i32_to_f64(x);
                var fy = $ir_i32_to_f64(y);
                return $ir_mul_f64(fx, fy);
            }

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

        if ($ir_is_f64(y))
            return $ir_mul_f64($ir_i32_to_f64(x), y);
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_mul_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_mul_f64(x, y);
    }

    return $rt_mul($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized add for the (int,int) and (float,float) cases
*/
function $rt_mulIntFloat(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
        {
            // If this could produce negative 0
            if (($ir_lt_i32(x, 0) && $ir_eq_i32(y, 0)) || 
                ($ir_eq_i32(x, 0) && $ir_lt_i32(y, 0)))
            {
                var fx = $ir_i32_to_f64(x);
                var fy = $ir_i32_to_f64(y);
                return $ir_mul_f64(fx, fy);
            }

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

        if ($ir_is_f64(y))
            return $ir_mul_f64($ir_i32_to_f64(x), y);
    }

    // If x is floating-point
    else if ($ir_is_f64(x))
    {
        if ($ir_is_f64(y))
            return $ir_mul_f64(x, y);

        if ($ir_is_i32(y))
            return $ir_mul_f64(x, $ir_i32_to_f64(y));
    }

    return $rt_mul(x, y);
}

/**
JS division operator
*/
function $rt_div(x, y)
{
    // If either value is floating-point or integer
    if (($ir_is_f64(x) || $ir_is_i32(x)) &&
        ($ir_is_f64(y) || $ir_is_i32(y)))
    {
        var fx = $ir_is_f64(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_f64(y)? y:$ir_i32_to_f64(y);

        return $ir_div_f64(fx, fy);
    }

    return $rt_div($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized divide for integers and floats
*/
function $rt_divIntFloat(x, y)
{
    // If either value is floating-point or integer
    if (($ir_is_f64(x) || $ir_is_i32(x)) &&
        ($ir_is_f64(y) || $ir_is_i32(y)))
    {
        var fx = $ir_is_f64(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_f64(y)? y:$ir_i32_to_f64(y);

        return $ir_div_f64(fx, fy);
    }

    return $rt_div(x, y);
}

/**
JS modulo operator
*/
function $rt_mod(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
        {
            if ($ir_eq_i32(y, 0))
                return NaN;

            return $ir_mod_i32(x, y);
        }

        if ($ir_is_f64(y))
            return $ir_mod_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_f64(y))
            return $ir_mod_f64(x, y);

        if ($ir_is_i32(y))
            return $ir_mod_f64(x, $ir_i32_to_f64(y));
    }

    return $rt_mod($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized modulo for the (int,int) case
*/
function $rt_modInt(x, y)
{
    // If x,y are integer
    if ($ir_is_i32(x) && $ir_is_i32(y) && $ir_ne_i32(y, 0))
    {
        return $ir_mod_i32(x, y);
    }

    return $rt_mod(x, y);
}

//=============================================================================
// Bitwise operators
//=============================================================================

function $rt_and(x, y)
{
    // If both values are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        return $ir_and_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_and_i32($rt_toInt32(x), $rt_toInt32(y));
}

function $rt_or(x, y)
{
    // If both values are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        return $ir_or_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_or_i32($rt_toInt32(x), $rt_toInt32(y));
}

function $rt_xor(x, y)
{
    // If both values are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        return $ir_xor_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_xor_i32($rt_toInt32(x), $rt_toInt32(y));
}

function $rt_lsft(x, y)
{
    // If both values are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        return $ir_lsft_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_lsft_i32($rt_toInt32(x), $rt_toUint32(y));
}

function $rt_rsft(x, y)
{
    // If both values are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        return $ir_rsft_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_rsft_i32($rt_toInt32(x), $rt_toUint32(y));
}

function $rt_ursft(x, y)
{
    // If both values are integer
    if ($ir_is_i32(x) && $ir_is_i32(y))
    {
        return $ir_ursft_i32(x, y);
    }

    // Convert the operands to integers
    return $ir_ursft_i32($rt_toInt32(x), $rt_toUint32(y));
}

function $rt_not(x)
{
    if ($ir_is_i32(x))
    {
        return $ir_not_i32(x);
    }

    // Convert the operand to integers
    return $ir_not_i32($rt_toInt32(x));
}

//=============================================================================
// Comparison operators
//=============================================================================

/**
JS less-than operator
*/
function $rt_lt(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_lt_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_lt_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_lt_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_lt_f64(x, y);
    }

    var px = $rt_toPrim(x);
    var py = $rt_toPrim(y);

    // If x is a string
    if ($ir_is_string(px) && $ir_is_string(py))
    {
        return $ir_eq_i32($rt_strcmp(px, py), -1);
    }

    return $rt_lt($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized less-than for the integer and float cases
*/
function $rt_ltIntFloat(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_lt_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_lt_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_lt_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_lt_f64(x, y);
    }

    return $rt_lt(x, y);
}

/**
JS less-than or equal operator
*/
function $rt_le(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_le_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_le_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_le_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_le_f64(x, y);
    }

    var px = $rt_toPrim(x);
    var py = $rt_toPrim(y);

    // If x is a string
    if ($ir_is_string(px) && $ir_is_string(py))
    {
        return $ir_le_i32($rt_strcmp(px, py), 0);
    }

    return $rt_le($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized less-than or equal for the integer and float cases
*/
function $rt_leIntFloat(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_le_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_le_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_le_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_le_f64(x, y);
    }

    return $rt_le(x, y);
}

/**
JS greater-than operator
*/
function $rt_gt(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_gt_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_gt_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_gt_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_gt_f64(x, y);
    }

    var px = $rt_toPrim(x);
    var py = $rt_toPrim(y);

    // If x is a string
    if ($ir_is_string(px) && $ir_is_string(py))
    {
        return $rt_strcmp(px, py) > 0;
    }

    return $rt_gt($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized greater-than for the integer and float cases
*/
function $rt_gtIntFloat(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_gt_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_gt_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_gt_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_gt_f64(x, y);
    }

    return $rt_gt(x, y);
}

/**
JS greater-than-or-equal operator
*/
function $rt_ge(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_ge_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_ge_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_ge_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_ge_f64(x, y);
    }

    var px = $rt_toPrim(x);
    var py = $rt_toPrim(y);

    // If x is a string
    if ($ir_is_string(px) && $ir_is_string(py))
    {
        return $rt_strcmp(px, py) >= 0;
    }

    return $rt_ge($rt_toNumber(x), $rt_toNumber(y));
}

/**
Specialized greater-than-or-equal for the integer and float cases
*/
function $rt_geIntFloat(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_ge_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_ge_f64($ir_i32_to_f64(x), y);
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_ge_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_ge_f64(x, y);
    }

    return $rt_ge(x, y);
}

/**
JS equality (==) comparison operator
*/
function $rt_eq(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_eq_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_eq_f64($ir_i32_to_f64(x), y);

        // 0 != null
        if (x === 0 && y === null)
            return false;
    }

    else if ($ir_is_object(x))
    {
        if ($ir_is_object(y))
            return $ir_eq_refptr(x, y);

        if ($ir_is_refptr(y) || $rt_valIsObj(y))
            return false;
    }

    else if ($ir_is_array(x))
    {
        if ($ir_is_array(y))
            return $ir_eq_refptr(x, y);

        if ($ir_is_refptr(y) || $rt_valIsObj(y))
            return false;
    }

    else if ($ir_is_closure(x))
    {
        if ($ir_is_closure(y))
            return $ir_eq_refptr(x, y);

        if ($ir_is_refptr(y) || $rt_valIsObj(y))
            return false;
    }

    else if ($ir_is_string(x))
    {
        if ($ir_is_string(y))
            return $ir_eq_refptr(x, y);

        // string != null
        if ($ir_is_refptr(y) && $ir_eq_refptr(y, null))
            return false;
    }

    // If x is a references
    else if ($ir_is_refptr(x))
    {
        // If x is null
        if ($ir_eq_refptr(x, null))
        {
            // null == undefined
            if ($ir_is_const(y) && $ir_eq_const(y, $undef))
                return true;

            // null == null
            if ($ir_is_refptr(y) && $ir_eq_refptr(y, null))
                return true;

            return false;
        }
    }

    // If x is a constant
    else if ($ir_is_const(x))
    {
        if ($ir_is_const(y))
            return $ir_eq_const(x, y);

        // undefined == null
        if ($ir_eq_const(x, undefined) && 
            $ir_is_refptr(y) && $ir_eq_refptr(y, null))
            return true;
    }

    // If x is float
    else if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_eq_f64(x, $ir_i32_to_f64(y));

        if ($ir_is_f64(y))
            return $ir_eq_f64(x, y);
    }

    var px = $rt_toPrim(x);
    var py = $rt_toPrim(y);

    // If x is a string
    if ($ir_is_string(px) && $ir_is_string(py))
    {
        return $ir_eq_refptr(px, py);
    }

    return $rt_eq($rt_toNumber(x), $rt_toNumber(y));
}

/**
Optimized equality (==) for integer comparisons
*/
function $rt_eqInt(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_eq_i32(x, y);
    }

    if ($ir_is_f64(x))
    {
        if ($ir_is_i32(y))
            return $ir_eq_f64(x, $ir_i32_to_f64(y));
    }

    return $rt_eq(x, y);
}

/**
Optimized equality (==) for comparisons with null
*/
function $rt_eqNull(x)
{
    if ($ir_is_refptr(x) && $ir_eq_refptr(x, null))
        return true;

    if ($ir_is_const(x) && $ir_eq_const(x, $undef))
        return true;

    return false;
}

/**
JS inequality (!=) comparison operator
*/
function $rt_ne(x, y)
{
    return !$rt_eq(x, y);
}

/**
JS strict equality (===) comparison operator
*/
function $rt_se(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_eq_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_eq_f64($ir_i32_to_f64(x), y);

        return false;
    }

    else if ($ir_is_object(x))
    {
        if ($ir_is_object(y))
            return $ir_eq_refptr(x, y);
        return false;
    }

    else if ($ir_is_array(x))
    {
        if ($ir_is_array(y))
            return $ir_eq_refptr(x, y);
        return false;
    }

    else if ($ir_is_closure(x))
    {
        if ($ir_is_closure(y))
            return $ir_eq_refptr(x, y);
        return false;
    }

    else if ($ir_is_string(x))
    {
        if ($ir_is_string(y))
            return $ir_eq_refptr(x, y);
        return false;
    }

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
    else if ($ir_is_f64(x))
    {
        if ($ir_is_f64(y))
            return $ir_eq_f64(x, y);

        if ($ir_is_i32(y))
            return $ir_eq_f64(x, $ir_i32_to_f64(y));

        return false;
    }

    // If x is a raw pointer
    else if ($ir_is_rawptr(x))
    {
        if ($ir_is_rawptr(y))
            return $ir_eq_rawptr(x, y);

        return false;
    }

    throw TypeError("unsupported types in strict equality comparison");
}

/**
JS strict inequality (!==) comparison operator
*/
function $rt_ns(x, y)
{
    // If x is integer
    if ($ir_is_i32(x))
    {
        if ($ir_is_i32(y))
            return $ir_ne_i32(x, y);

        if ($ir_is_f64(y))
            return $ir_ne_f64($ir_i32_to_f64(x), y);

        return true;
    }

    else if ($ir_is_object(x))
    {
        if ($ir_is_object(y))
            return $ir_ne_refptr(x, y);
        return true;
    }

    else if ($ir_is_array(x))
    {
        if ($ir_is_array(y))
            return $ir_ne_refptr(x, y);
        return true;
    }

    else if ($ir_is_closure(x))
    {
        if ($ir_is_closure(y))
            return $ir_ne_refptr(x, y);
        return true;
    }

    else if ($ir_is_string(x))
    {
        if ($ir_is_string(y))
            return $ir_ne_refptr(x, y);
        return true;
    }

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
    else if ($ir_is_f64(x))
    {
        if ($ir_is_f64(y))
            return $ir_ne_f64(x, y);

        if ($ir_is_i32(y))
            return $ir_ne_f64(x, $ir_i32_to_f64(y));

        return true;
    }

    // If x is a rawptr
    else if($ir_is_rawptr(x))
    {
        if ($ir_is_rawptr(y))
            return $ir_ne_rawptr(x, y);

        return true
    }

    throw TypeError("unsupported types in strict inequality comparison");
}

//=============================================================================
// Object allocation
//=============================================================================

/**
Allocate the "this" object for a constructor call
*/
function $rt_ctorNewThis(clos)
{
    var proto = clos.prototype;
    var thisObj = $rt_newObj(proto);

    return thisObj;
}

/**
Select the return value after a new/constructor call
*/
function $rt_ctorSelectRet(retVal, thisVal)
{
    if ($ir_is_const(retVal) && $ir_eq_const(retVal, $undef))
        return thisVal;

    return retVal;
}

/**
Allocate an empty object
*/
function $rt_newObj(protoPtr)
{
    // Allocate the object
    var objPtr = $rt_obj_alloc($rt_OBJ_MIN_CAP);

    $rt_obj_set_shape(objPtr, $ir_shape_empty());

    $rt_setProto(objPtr, protoPtr);

    return objPtr;
}

/**
Allocate an array
*/
function $rt_newArr(protoPtr, numElems)
{
    // Allocate the array table
    var tblPtr = $rt_arrtbl_alloc(numElems);

    // Allocate the array
    var objPtr = $rt_arr_alloc($rt_OBJ_MIN_CAP);

    // Initialize the array object
    $rt_obj_set_shape(objPtr, $ir_shape_empty());
    $rt_setProto(objPtr, protoPtr);
    $rt_arr_set_tbl(objPtr, tblPtr);
    $rt_arr_set_len(objPtr, numElems);

    //$ir_print_str("Allocated array\n");

    return objPtr;
}

/**
Create a new getter-setter pair object
*/
function $rt_newGetSet(get, set)
{
    // Allocate the object
    var objPtr = $rt_getset_alloc(2);

    $rt_obj_set_shape(objPtr, $ir_shape_empty());

    objPtr.get = get;
    objPtr.set = set;

    return objPtr
}

/**
Get/allocate a regular expresson object
*/
function $rt_getRegexp(link, pattern, flags)
{
    var rePtr = $ir_get_link(link);

    if (rePtr === null)
    {
        rePtr = new $rt_RegExp(pattern, flags);

        $ir_set_link(link, rePtr);
    }

    return rePtr;
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
Set the prototype value for an object
*/
function $rt_setProto(obj, proto)
{
    // Define the prototype as a non-writable, non-enumerable constant
    $ir_shape_def_const(obj, '__proto__', proto, false);
}

/**
Get the prototype value for an object
*/
function $rt_getProto(obj)
{
    return obj.__proto__;
}

/**
Get a property from an object using a string as key
*/
function $rt_objGetProp(obj, propStr)
{
    // Find the defining shape for this property
    // This shifts us to a different version where the obj shape is known
    // Implements a "version cache" with dynamic dispatching
    var defShape = $ir_shape_get_def(obj, propStr);

    // If the property is defined on the object
    if ($ir_ne_rawptr(defShape, $nullptr))
    {
        // Get the property value
        var propVal = $ir_shape_get_prop(obj, defShape);

        // If the property is a getter-setter function
        if ($ir_is_getset(propVal))
        {
            // Call the getter function
            return $ir_call(propVal.get, obj);
        }
        else
        {
            // Property was found, is not a getter
            return propVal;
        }
    }

    // Get the object's prototype
    var proto = $rt_getProto(obj);

    // If the prototype is null, produce undefined
    if ($ir_eq_refptr(proto, null))
        return $undef;

    // Do a recursive lookup on the prototype
    return $rt_objGetProp(
        proto,
        propStr
    );
}

/**
Get a property from a value using a value as a key
*/
function $rt_getProp(base, prop)
{
    // If the base is an object or closure
    if ($ir_is_object(base) || $ir_is_closure(base) || $ir_is_getset(base))
    {
        // If the property is a string
        if ($ir_is_string(prop))
            return $rt_objGetProp(base, prop);

        return $rt_objGetProp(base, $rt_toString(prop));
    }

    // If the base is an array
    if ($ir_is_array(base))
    {
        // If the property is a non-negative integer
        if ($ir_is_i32(prop) && $ir_ge_i32(prop, 0) &&
            $ir_lt_i32(prop, $rt_arr_get_len(base)))
        {
            var tbl = $rt_arr_get_tbl(base);
            var word = $rt_arrtbl_get_word(tbl, prop);
            var type = $rt_arrtbl_get_type(tbl, prop);
            return $ir_make_value(word, type);
        }

        // If the property is a floating-point number
        if ($ir_is_f64(prop))
        {
            var intVal = $rt_toUint32(prop);
            if (intVal === prop)
                return $rt_getProp(base, intVal);
        }

        // If the property is a string
        if ($ir_is_string(prop))
        {
            // If this is the length property
            if ($ir_eq_refptr(prop, 'length'))
                return $rt_arr_get_len(base);

            var propNum = $rt_strToInt(prop);
            if ($ir_is_i32(propNum))
                return $rt_getProp(base, propNum);

            return $rt_objGetProp(base, prop);
        }

        return $rt_objGetProp(base, $rt_toString(prop));
    }

    // If the base is a string
    if ($ir_is_string(base))
    {
        // If the property is a non-negative integer
        if ($ir_is_i32(prop) && $ir_ge_i32(prop, 0) && 
            $ir_lt_i32(prop, $rt_str_get_len(base)))
        {
            var ch = $rt_str_get_data(base, prop);
            var str = $rt_str_alloc(1);
            $rt_str_set_data(str, 0, ch);
            return $ir_get_str(str);
        }

        // If this is the length property
        if ($ir_is_string(prop) && $ir_eq_refptr(prop, 'length'))
            return $rt_str_get_len(base);

        // Recurse on String.prototype
        return $rt_getProp(String.prototype, prop);
    }

    // If the base is a number
    if ($ir_is_i32(base) || $ir_is_f64(base))
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

    if (base === null)
    {
        if ($ir_is_string(prop))
            throw TypeError('null base in read of property "' + prop + '"');
        else
            throw TypeError("null base in property read");
    }

    if (base === $undef)
    {
        if ($ir_is_string(prop))
            throw TypeError('undefined base in read of property "' + prop + '"');
        else
            throw TypeError("undefined base in property read");
    }

    throw TypeError("invalid base in property read");
}

/**
Specialized version of getProp for field accesses where
the base is an object of some kind and the key is a constant string
*/
function $rt_getPropField(base, prop)
{
    // If the base is a simple object
    if ($ir_is_object(base))
    {
        // Find the defining shape for this property
        var defShape = $ir_shape_get_def(base, prop);

        // If the property is defined on the object
        if ($ir_ne_rawptr(defShape, $nullptr))
        {
            // Get the property value
            var propVal = $ir_shape_get_prop(base, defShape);

            // If the value is not a getter-setter function, return it
            if (!$ir_is_getset(propVal))
            {
                // Property was found, is not a getter
                return propVal;
            }
        }
    }

    return $rt_getProp(base, prop);
}

/**
Specialized version of getProp for method accesses where
the base is an object and the key is a constant string
*/
function $rt_getPropMethod(base, prop)
{
    // If the base is an object
    if ($ir_is_object(base))
    {
        // Find the defining shape for this property
        var defShape = $ir_shape_get_def(base, prop);

        // If the property is defined on the object
        if ($ir_ne_rawptr(defShape, $nullptr))
        {
            // Get the property value
            var propVal = $ir_shape_get_prop(base, defShape);

            // If the value is not a getter-setter function, return it
            if (!$ir_is_getset(propVal))
            {
                // Property was found, is not a getter
                return propVal;
            }
        }

        // Get the prototype of the object
        var base = $rt_getProto(base);

        // If the prototype is not null
        if ($ir_is_object(base))
        {
            // Find the defining shape for this property
            var defShape = $ir_shape_get_def(base, prop);

            // If the property is defined on the object
            if ($ir_ne_rawptr(defShape, $nullptr))
            {
                // Get the property value
                var propVal = $ir_shape_get_prop(base, defShape);

                // If the value is not a getter-setter function, return it
                if (!$ir_is_getset(propVal))
                {
                    // Property was found, is not a getter
                    return propVal;
                }
            }
        }
    }

    return $rt_getProp(base, prop);
}

/**
Specialized version of getProp for array elements
*/
function $rt_getPropElem(base, prop)
{
    // If the base is an array and the property is a non-negative integer
    if ($ir_is_array(base) &&
        $ir_is_i32(prop) && $ir_ge_i32(prop, 0) &&
        $ir_lt_i32(prop, $rt_arr_get_len(base)))
    {
        var tbl = $rt_arr_get_tbl(base);
        var word = $rt_arrtbl_get_word(tbl, prop);
        var type = $rt_arrtbl_get_type(tbl, prop);
        return $ir_make_value(word, type);
    }

    return $rt_getProp(base, prop);
}

/**
Specialized version of getProp for "length" property accesses
*/
function $rt_getPropLength(base)
{
    // If the base is an array
    if ($ir_is_array(base))
    {
        return $rt_arr_get_len(base);
    }

    return $rt_getProp(base, "length");
}

/**
Get a property from the global object
*/
function $rt_getGlobal(obj, propStr)
{
    // Find the defining shape for this property
    // This shifts us to a different version where the obj shape is known
    // Implements a "version cache" with dynamic dispatching
    var defShape = $ir_shape_get_def(obj, propStr);

    // If the property is defined on the object
    if ($ir_ne_rawptr(defShape, $nullptr))
    {
        // Get the property value
        var propVal = $ir_shape_get_prop(obj, defShape);

        // If the property is a getter-setter function
        if ($ir_is_getset(propVal))
        {
            // Call the getter function
            return $ir_call(propVal.get, obj);
        }
        else
        {
            // Property was found, is not a getter
            return propVal;
        }
    }

    // Get the object's prototype
    var proto = $rt_getProto(obj);

    // If the prototype is null, the propert is not defined
    if ($ir_eq_refptr(proto, null))
    {
        var errStr = 'global property not defined: "' + propStr + '"';

        if ($ir_get_global_obj().ReferenceError)
            throw ReferenceError(errStr);
        else
            throw errStr;
    }

    // Do a recursive lookup on the prototype
    return $rt_getGlobal(
        proto,
        propStr
    );
}

/**
Inlined version of getGlobal
*/
function $rt_getGlobalInl(propStr)
{
    var obj = $ir_get_global_obj();

    // Find the index for this property
    // This shifts us to a different version where the obj shape is known
    // Implements a "version cache" with dynamic dispatching
    var defShape = $ir_shape_get_def(obj, propStr);

    // If the property is defined on the object
    if ($ir_ne_rawptr(defShape, $nullptr))
    {
        // Get the property value
        var propVal = $ir_shape_get_prop(obj, defShape);

        // If the property is a not getter-setter function, return its value
        if (!$ir_is_getset(propVal))
        {
            return propVal;
        }
    }

    // Do the full global lookup
    return $rt_getGlobal(
        obj,
        propStr
    );
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
    // Allocate the new table without initializing it, for performance
    var newTbl = $rt_arrtbl_alloc(newSize);

    // Copy elements from the old table to the new
    for (var i = 0; $ir_lt_i32(i, curLen); i = $ir_add_i32(i, 1))
    {
        $rt_arrtbl_set_word(newTbl, i, $rt_arrtbl_get_word(curTbl, i));
        $rt_arrtbl_set_type(newTbl, i, $rt_arrtbl_get_type(curTbl, i));
    }

    // Update the table reference in the array
    $rt_arr_set_tbl(arr, newTbl);

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
    if ($ir_ge_i32(index, len))
    {
        // Compute the new length
        var newLen = $ir_add_i32(index, 1);

        // Get the array capacity
        var cap = $rt_arrtbl_get_cap(tbl);

        // If the new length would exceed the capacity
        if ($ir_gt_i32(newLen, cap))
        {
            // Compute the new size to resize to
            var newSize = $ir_mul_i32(cap, 2);
            if ($ir_gt_i32(newLen, newSize))
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
Set an element of an array without bounds checking
*/
function $rt_setArrElemNoCheck(arr, index, val)
{
    // Get the array table
    var tbl = $rt_arr_get_tbl(arr);

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
function $rt_objSetProp(obj, propStr, val)
{
    // Find the index for this property
    // Handles dynamic version dispatching
    // This will not transition the object to a new shape
    var defShape = $ir_shape_get_def(obj, propStr);

    // If the property is a getter-setter function
    if ($ir_shape_is_getset(defShape))
    {
        // Get the accessor pair
        var propVal = $ir_shape_get_prop(obj, defShape);

        // Call the setter function
        $ir_call(propVal.set, obj, val);
    }
    else
    {
        // Hidden inside set_prop, we handle the extended table
        // May also transition the object to another shape if this
        // is a new property or the type written doesn't match what was known
        // If the current shape is unknown, complex logic will be handled in D
        $ir_shape_set_prop(obj, propStr, defShape, val);
    }
}

/**
Set a property on a value using a value as a key
*/
function $rt_setProp(base, prop, val)
{
    //print(prop);
    //print('\n');

    // If the base is an object or closure
    if ($ir_is_object(base) || $ir_is_closure(base) || $ir_is_getset(base))
    {
        // If the property is a string
        if ($ir_is_string(prop))
            return $rt_objSetProp(base, prop, val);

        return $rt_objSetProp(base, $rt_toString(prop), val);
    }

    // If the base is an array
    if ($ir_is_array(base))
    {
        // If the property is a non-negative integer
        if ($ir_is_i32(prop) && $ir_ge_i32(prop, 0))
        {
            return $rt_setArrElem(base, prop, val);
        }

        // If the property is a string
        if ($ir_is_string(prop))
        {
            // If this is the length property
            if ($ir_eq_refptr(prop, 'length'))
            {
                if ($ir_is_i32(val) && $ir_ge_i32(val, 0))
                    return $rt_setArrLen(base, val);

                assert (false, 'invalid array length');
            }

            var propNum = $rt_strToInt(prop);
            if ($ir_is_i32(propNum))
                return $rt_setProp(base, propNum, val);

            return $rt_objSetProp(base, prop, val);
        }

        // If the property is a floating-point number
        if ($ir_is_f64(prop))
        {
            var intVal = $rt_toUint32(prop);
            if (intVal === prop)
                return $rt_setProp(base, intVal, val);
        }

        return $rt_objSetProp(base, $rt_toString(prop), val);
    }

    //print(typeof base);
    //print(base);
    //print(prop);

    throw TypeError("invalid base in property write");
}

/**
Specialized version of setProp for object properties
*/
function $rt_setPropField(base, prop, val)
{
    // If the base is an object or closure and the property is a string
    if (($ir_is_object(base) || $ir_is_closure(base)) && $ir_is_string(prop))
    {
        // Find the index for this property
        var defShape = $ir_shape_get_def(base, prop);

        // If the property is a getter-setter function
        if (!$ir_shape_is_getset(defShape))
        {
            // Set the property value
            $ir_shape_set_prop(base, prop, defShape, val);

            return;
        }
    }

    return $rt_setProp(base, prop, val);
}

/**
Specialized version of setProp for array elements
*/
function $rt_setPropElem(base, prop, val)
{
    // If the base is an array
    if ($ir_is_array(base))
    {
        // If the property is a non-negative integer
        // and is within the array bounds
        if ($ir_is_i32(prop) &&
            $ir_ge_i32(prop, 0) &&
            $ir_lt_i32(prop, $rt_arr_get_len(base)))
        {
            // Get a reference to the array table
            var tbl = $rt_arr_get_tbl(base);

            // Set the element in the array
            $rt_arrtbl_set_word(tbl, prop, $ir_get_word(val));
            $rt_arrtbl_set_type(tbl, prop, $ir_get_type(val));

            return;
        }
    }

    return $rt_setProp(base, prop, val);
}

/**
JS delete operator
*/
function $rt_delProp(base, prop)
{
    // If the base is not an object, do nothing
    if (!$ir_is_object(base) && !ir_is_array(base) && !ir_is_closure(base))
        return true;

    // If the property is not a string
    if (!$ir_is_string(prop))
        throw TypeError('non-string property name');

    // Set the property attributes to deleted
    $ir_shape_set_attrs(base, prop, $rt_ATTR_DELETED | $rt_ATTR_CONFIGURABLE);

    return true;
}

/**
Implementation of the "instanceof" operator
*/
function $rt_instanceof(obj, ctor)
{ 
    if (!$ir_is_closure(ctor))
        throw TypeError('constructor must be function');

    // If the value is not an object
    if (!$rt_valIsObj(obj))
    {
        // Return the false value
        return false;
    }

    // Get the prototype for the constructor function
    var ctorProto = ctor.prototype;

    // Until we went all the way through the prototype chain
    do
    {
        var objProto = $rt_getProto(obj);

        if ($ir_eq_refptr(objProto, ctorProto))
            return true;

        obj = objProto;

    } while ($ir_ne_refptr(obj, null));

    return false;
}

/**
Check if an object has a given property
*/
function $rt_objHasProp(obj, propStr)
{
    // Try to find the defining shape for the property
    var defShape = $ir_shape_get_def(obj, propStr);

    // Check if a defining shape was found
    return $ir_ne_rawptr(defShape, $nullptr);
}

/**
Check if a value has a given property
*/
function $rt_hasOwnProp(base, prop)
{
    // If the base is an object or closure
    if ($ir_is_object(base) || $ir_is_closure(base))
    {
        // If the property is a string
        if ($ir_is_string(prop))
            return $rt_objHasProp(base, prop);

        return $rt_objHasProp(base, $rt_toString(prop));
    }

    // If the base is an array
    if ($ir_is_array(base))
    {
        // If the property is a non-negative integer
        if ($ir_is_i32(prop) && $ir_ge_i32(prop, 0) &&
            $ir_lt_i32(prop, $rt_arr_get_len(base)))
            return true;

        // If the property is not a string, get one
        if (!$ir_is_string(prop))
            prop = $rt_toString(prop);

        // If this is the length property
        if (prop === 'length')
            return true;

        // Check if it's an indexed property the array should have
        var n = $rt_strToInt(prop);
        if ($ir_is_i32(n) &&
            $ir_ge_i32(n, 0) &&
            $ir_lt_i32(n, $rt_arr_get_len(base)))
            return true;

        return $rt_objHasProp(base, prop);
    }

    // If the base is a string
    if ($ir_is_string(base))
    {
        // If the property is an int
        if ($ir_is_i32(prop) && $ir_ge_i32(prop, 0) &&
            $ir_lt_i32(prop, $rt_str_get_len(base)))
           return true;

        // If the property is not a string, get one
        if (!$ir_is_string(prop))
            prop = $rt_toString(prop);

        // If this is the 'length' property
        if (prop === 'length')
            return true;

        // Check if this is a valid index into the string
        var n = $rt_strToInt(prop);
        return (
            $ir_is_i32(n) &&
            $ir_ge_i32(n, 0) &&
            $ir_lt_i32(n, $rt_str_get_len(base))
        );
    }

    // If the base is a number
    if ($ir_is_i32(base) || $ir_is_f64(base))
    {
        return false;
    }

    // If the base is a constant
    if ($ir_is_const(base))
    {
        return false;
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

        obj = $rt_getProto(obj);

    } while ($ir_ne_refptr(obj, null));

    return false;
}

/**
Used to enumerate properties in a for-in loop
*/
function $rt_getPropEnum(obj)
{
    // If the value is not an object or a string
    if (!$rt_valIsObj(obj) && !$ir_is_string(obj))
    {
        // Return the empty enumeration function
        return function ()
        {
            return true;
        };
    }

    var curObj = obj;
    var curShape = $rt_valIsObj(curObj)? $rt_obj_get_shape(curObj):$nullptr;
    var curIdx = 0;

    // Check if a property is shadowed by a prototype's
    function isShadowed(curObj, propName)
    {
        for (;;)
        {
            // Move one down the prototype chain
            curObj = $rt_getProto(curObj);

            // If we reached the bottom of the chain, stop
            if ($ir_eq_refptr(curObj, null))
                return false;

            // If the property exists on this object, it is shadowed
            if ($rt_hasOwnProp(curObj, propName))
                return true;
        }
    }

    // Function to get the next available property
    function nextProp()
    {
        while (true)
        {
            // If we are at the end of the prototype chain, stop
            if (curObj === null)
                return true;

            // If the current object is an object of some kind
            if ($rt_valIsObj(curObj))
            {
                var objShape = $rt_obj_get_shape(curObj);

                // For each property shape
                while ($ir_ne_refptr(curShape, $nullptr))
                {
                    // Get the name for this property
                    var propName = $ir_shape_prop_name(curShape);

                    // Get the attributes for the current shape
                    var propAttrs = $ir_shape_get_attrs(curShape);

                    // Move to the parent shape
                    var propShape = curShape;
                    curShape = $ir_shape_parent(curShape);

                    // If this is not an enumerable property, skip it
                    if ((propAttrs & $rt_ATTR_ENUMERABLE) == 0)
                        continue;

                    // If this is not a valid key in this object, skip it
                    //if ($ir_eq_refptr(keyVal, null))
                    //    continue;

                    // FIXME: not working
                    // If this is not the defining shape for this property, skip it
                    if ($ir_ne_rawptr($ir_shape_get_def(curObj, propName), propShape))
                        continue;

                    // If the property is shadowed, skip it
                    if (isShadowed(curObj, propName))
                        continue;

                    // Return the current key
                    return propName;
                }

                // If the object is an array
                if ($ir_is_array(curObj))
                {
                    if (curIdx < curObj.length)
                    {
                        return curIdx++;
                    }
                }

                // Move up the prototype chain
                curObj = $rt_getProto(curObj);
                curShape = $rt_valIsObj(curObj)? $rt_obj_get_shape(curObj):$nullptr;
                curIdx = 0;
                continue;
            }

            // If the object is a string
            else if ($ir_is_string(curObj))
            {
                if (curIdx < curObj.length)
                {
                    return curIdx++;
                }
                else
                {
                    // Move up the prototype chain
                    curObj = String.prototype;
                    curShape = $rt_valIsObj(curObj)? $rt_obj_get_shape(curObj):$nullptr;
                    curIdx = 0;
                    continue;
                }
            }

            else
            {
                return true;
            }
        }
    }

    return nextProp;
}

