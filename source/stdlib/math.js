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
Implementation of ECMAScript 5 math library routines.

@author
Maxime Chevalier-Boisvert

@copyright
Copyright (c) 2010-2012 Tachyon Javascript Engine, All Rights Reserved
*/

/**
Math object (see ECMAScript 5 18.8)
*/
var Math = {};

/*
15.8.1.1 E
*/
Math.E = 2.7182818284590452354;

/**
15.8.1.2 LN10
*/
Math.LN10 = 2.302585092994046;

/**
15.8.1.3 LN2
*/
Math.LN2 = 0.6931471805599453;

/**
15.8.1.4 LOG2E
*/
Math.LOG2E = 1.4426950408889634;

/**
15.8.1.5 LOG10E
*/
Math.LOG10E = 0.4342944819032518;

/**
15.8.1.6 PI
*/
Math.PI = 3.1415926535897932;

/**
15.8.1.7 SQRT1_2
*/
Math.SQRT1_2 = 0.7071067811865476;

/**
15.8.1.8 SQRT2
*/
Math.SQRT2 = 1.4142135623730951;

/**
15.8.2.1 abs (x)
Returns the absolute value of x; the result has the same magnitude as x
but has positive sign.

• If x is NaN, the result is NaN.
• If x is −0, the result is +0.
• If x is −∞, the result is +∞.
*/
Math.abs = function (x)
{
    if (x < 0)
        return -x;
    else
        return x;
};

/**
15.8.2.6 ceil (x)
Returns the smallest (closest to −∞) Number value that is not less than x
and is equal to a mathematical integer. If x is already an integer, the
result is x.

• If x is NaN, the result is NaN.
• If x is +0, the result is +0.
• If x is −0, the result is −0.
• If x is +∞, the result is +∞.
• If x is −∞, the result is −∞.
• If x is less than 0 but greater than -1, the result is −0.

The value of Math.ceil(x) is the same as the value of -Math.floor(-x).
*/
Math.ceil = function (x)
{
    // TODO: requires F64 to/from I64 conversion for truncation

    // For integers, the value is unchanged
    return x;
};

/**
15.8.2.9 floor (x)
Returns the greatest (closest to +∞) Number value that is not greater than x 
and is equal to a mathematical integer. If x is already an integer, the result
is x.

• If x is NaN, the result is NaN.
• If x is +0, the result is +0.
• If x is −0, the result is −0.
• If x is +∞, the result is +∞.
• If x is −∞, the result is −∞.
• If x is greater than 0 but less than 1, the result is +0.

NOTE: The value of Math.floor(x) is the same as the value of -Math.ceil(-x).
*/
Math.floor = function (x)
{
    return -Math.ceil(-x);
};

/**
15.8.2.11 max ([value1 [, value2 [, … ]]])
Given zero or more arguments, calls ToNumber on each of the arguments and 
returns the largest of the resulting values.

• If no arguments are given, the result is −∞.
• If any value is NaN, the result is NaN.
• The comparison of values to determine the largest value is done as in
  11.8.5 except that +0 is considered to be larger than −0.

The length property of the max method is 2.
*/
Math.max = function ()
{
    // TODO: use -Infinity?
    // Only return -Inf if no values present!

    var m = MIN_FIXNUM;

    for (var i = 0; i < arguments.length; ++i)
        if (arguments[i] > m)
            m = arguments[i];

    return m;
};

/**
15.8.2.12 min ([ value1 [, value2 [, … ]]])
Given zero or more arguments, calls ToNumber on each of the arguments and
returns the smallest of the resulting values.

• If no arguments are given, the result is +∞.
• If any value is NaN, the result is NaN.
• The comparison of values to determine the smallest value is done as in
  11.8.5 except that +0 is considered to be larger than −0.

The length property of the min method is 2.
*/
Math.min = function ()
{
    // TODO: use Infinity?

    var m = MAX_FIXNUM;

    for (var i = 0; i < arguments.length; ++i)
        if (arguments[i] < m)
            m = arguments[i];

    return m;
};

/**
15.8.2.13 pow (x, y)
Returns an implementation-dependent approximation to the result of raising 
x to the power y.

• If y is NaN, the result is NaN.
• If y is +0, the result is 1, even if x is NaN.
• If y is −0, the result is 1, even if x is NaN.
• If x is NaN and y is nonzero, the result is NaN.
• If abs(x)>1 and y is +∞, the result is +∞.
• If abs(x)>1 and y is −∞, the result is +0.
• If abs(x)==1 and y is +∞, the result is NaN.
• If abs(x)==1 and y is −∞, the result is NaN.
• If abs(x)<1 and y is +∞, the result is +0.
• If abs(x)<1 and y is −∞, the result is +∞.
• If x is +∞ and y>0, the result is +∞.
• If x is +∞ and y<0, the result is +0.
• If x is −∞ and y>0 and y is an odd integer, the result is −∞.
• If x is −∞ and y>0 and y is not an odd integer, the result is +∞.
• If x is −∞ and y<0 and y is an odd integer, the result is −0. 162 © Ecma International 2009
• If x is −∞ and y<0 and y is not an odd integer, the result is +0.
• If x is +0 and y>0, the result is +0.
• If x is +0 and y<0, the result is +∞.
• If x is −0 and y>0 and y is an odd integer, the result is −0.
• If x is −0 and y>0 and y is not an odd integer, the result is +0.
• If x is −0 and y<0 and y is an odd integer, the result is −∞.
• If x is −0 and y<0 and y is not an odd integer, the result is +∞.
• If x<0 and x is finite and y is finite and y is not an integer, the result is NaN.
*/
Math.pow = function (x, y)
{
    // If both values are non-negative integers
    if ($ir_is_int(x) && $ir_is_int(y) && $ir_ge_i32(x, 0) && $ir_ge_i32(y, 0))
    {
        // If the power is 0, the result is 1
        if ($ir_if_true($ir_eq_i32(y, 0)))
            return 1;

        var power = y;
        var current = x;
        var acc = 1;

        for (;;)
        {
            /*
            println('power  : ' + power);
            println('cur: ' + current);
            println('acc: ' + acc);
            */

            // Multiply the result by the current exponent
            if ($ir_if_true($ir_ne_i32($ir_and_i32(power, 1), 0)))
            {
                if (acc = $ir_mul_i32_ovf(acc, current))
                {
                }
                else
                {
                    /*
                    println('acc integer overflow in Math.pow');
                    println('power  : ' + power);
                    println('cur: ' + current);
                    println('acc: ' + acc);
                    */

                    // Continue the calculation with floating-point numbers
                    var accf = $ir_i32_to_f64(acc);
                    var curf = $ir_i32_to_f64(current);
                    var powf = $ir_i32_to_f64(power);
                    return Math.pow(
                        $ir_mul_f64(accf, curf),
                        powf
                    );
                }
            }

            // Right shift the power by 1
            power = $ir_rsft_i32(power, 1);

            // If the power is now 0, we are done
            if ($ir_if_true($ir_eq_i32(power, 0)))
                return acc;

            // Multiply the current exponent by itself
            if (current = $ir_mul_i32_ovf(current, current))
            {
            }
            else
            {
                /*
                println('current integer overflow in Math.pow');
                println('power  : ' + power);
                println('cur: ' + current);
                println('acc: ' + acc);
                */

                // Continue the calculation with floating-point numbers
                var xf = $ir_i32_to_f64(x);
                var yf = $ir_i32_to_f64(y);
                return Math.pow(
                    xf,
                    yf
                );
            }
        }
    }

    assert(false, 'floating-point support unimplemented');
};

/*
15.8.2.7 cos (x)
Returns an implementation-dependent approximation to the cosine of x. The
argument is expressed in radians.

• If x is NaN, the result is NaN.
• If x is +0, the result is 1.
• If x is −0, the result is 1.
• If x is +∞, the result is NaN.
• If x is −∞, the result is NaN.
*/
Math.cos = function (x)
{
    if ($ir_is_int(x) === true)
        x = $ir_i32_to_f64(x);
    else if ($ir_is_float(x) === false)
        return NaN;

    return $ir_cos_f64(x);
};

/*
15.8.2.16 sin (x)
Returns an implementation-dependent approximation to the sine of x. The
argument is expressed in radians.

• If x is NaN, the result is NaN.
• If x is +0, the result is +0.
• If x is −0, the result is −0.
• If x is +∞ or −∞, the result is NaN.
*/
Math.sin = function (x)
{
    if ($ir_is_int(x) === true)
        x = $ir_i32_to_f64(x);
    else if ($ir_is_float(x) === false)
        return NaN;

    return $ir_sin_f64(x);
};

/*
15.8.2.17 sqrt (x)
Returns an implementation-dependent approximation to the square root of x.

• If x is NaN, the result is NaN.
• If x is less than 0, the result is NaN.
• If x is +0, the result is +0.
• If x is −0, the result is −0.
• If x is +∞, the result is +∞.
*/
Math.sqrt = function (x)
{
    if ($ir_is_int(x) === true)
        x = $ir_i32_to_f64(x);
    else if ($ir_is_float(x) === false)
        return NaN;

    return $ir_sqrt_f64(x);
};

/*
15.8.2.8 exp (x)
Returns an implementation-dependent approximation to the exponential
function of x (e raised to the power of x, where e is the base of the
natural logarithms).

• If x is NaN, the result is NaN.
• If x is +0, the result is 1.
• If x is −0, the result is 1.
• If x is +∞, the result is +∞.
• If x is −∞, the result is +0.
*/
Math.exp = function (x)
{
    // TODO: implement this function
    return noFPSupport('Math.exp');
};

/*
15.8.2.10 log (x)
Returns an implementation-dependent approximation to the natural
logarithm of x.

• If x is NaN, the result is NaN.
• If x is less than 0, the result is NaN.
• If x is +0 or −0, the result is −∞.
• If x is 1, the result is +0.
• If x is +∞, the result is +∞.
*/
Math.log = function (x)
{
    // TODO: implement this function
    return noFPSupport('Math.log');
};

/*
15.8.2.14 random ()
Returns a Number value with positive sign, greater than or equal to 0 but
less than 1, chosen randomly or pseudo randomly with approximately
uniform distribution over that range, using an implementation-dependent
algorithm or strategy. This function takes no arguments.
*/
Math.random = function ()
{
    // TODO: implement this function
    return noFPSupport('Math.random');
};

