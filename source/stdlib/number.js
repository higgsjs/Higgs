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
 *  Copyright (c) 2012-2013, Universite de Montreal
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
Implementation of ECMAScript 5 Number methods and prototype.

@author
Maxime Chevalier-Boisvert
*/

/**
15.7.1 The Number function/constructor
new Number([ value ])
Number([ value ])
*/
function Number(value)
{
    // If this is a constructor call (new Number)
    if ($rt_isGlobalObj(this) === false)
    {
        // Convert the value to a number
        var numVal = $rt_toNumber(value);

        // If the value is not a number, return it directly
        if (isNaN(numVal))
            return numVal;

        // Store the value in the new object
        // TODO: this should be a hidden/internal property
        this.value = numVal;
    }
    else
    {
        // Convert the value to a number
        return $rt_toNumber(value);
    }
}

//-----------------------------------------------------------------------------

// TODO
// 15.7.3.2 Number.MAX_VALUE
// 15.7.3.3 Number.MIN_VALUE
// 15.7.3.4 Number.NaN
// 15.7.3.5 Number.NEGATIVE_INFINITY
// 15.7.3.6 Number.POSITIVE_INFINITY

/**
Internal function to get the number value of a number or number object
*/
function getNumVal(num)
{
    if (num instanceof Number)
        return num.value;

    return num;
}

/**
15.7.4.2 Number.prototype.toString ([ radix ])
*/
Number.prototype.toString = function (radix)
{
    var num = getNumVal(this);

    //FIXME: for now, ignoring the radix

    return $rt_toString(num);
};

/**
15.7.4.4 Number.prototype.valueOf ( )
*/
Number.prototype.valueOf = function ()
{
    return getNumVal(this);
};

/**
15.7.4.5 Number.prototype.toFixed (fractionDigits)
*/
Number.prototype.toFixed = function(fractionDigits)
{
    var m;

    // toInteger (fractionDigits)
    var f = $rt_toNumber(fractionDigits);
    if (isNaN(f))
        f = 0;
    else if ($ir_is_f64(f))
        f = (f > 0 ? 1 : - 1) * $ir_floor_f64((f > 0 ? f : -f));

    if (f < 0 || f > 20)
        throw new RangeError("toFixed argument out of range.");

    var x = getNumVal(this);
    if (isNaN(x))
        return "NaN";

    var s = "";
    if (x < 0)
    {
        s = "-";
        x = -x;
    }

    if (x >= 1e+21)
    {
        m = $rt_toString(x);
    }
    else
    {
        var tenf = 1;
        for(i = 0; i < f; i++)
            tenf *= 10;

        var n = x * tenf;
        if ($ir_is_f64(n))
            n = $ir_floor_f64(n);

        var delta = 0 - (n / tenf - x);
        delta = (delta > 0) ? delta : -delta;
        var delta2;
        while (true)
        {
            delta2 = 0 - ((n + 1) / tenf - x);
            delta2 = (delta2 > 0) ? delta2 : -delta2;
            if (delta2 > delta)
                break;
            n += 1;
            delta = delta2;
        }

        if (n === 0)
            m = "0";
        else
            m = $rt_toString(n);

        if (f !== 0)
        {
            var k = $rt_str_get_len(m);
            if (k <= f)
            {
                var end = f + 1 - k;
                var padding = $rt_str_alloc(end);
                for (var i = 0; i < end; i++)
                    $rt_str_set_data(padding, i, 48);

                m = $rt_strcat($ir_get_str(padding), m);
                k = f + 1;
            }
            var a = m.substring(0, k - f);
            var b = m.substring(k - f);
            m = $rt_strcat(a, $rt_strcat('.', b));
        }
    }

    return $rt_strcat(s, m);
};

