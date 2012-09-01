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
    if (isGlobalObj(this) === false)
    {
        // Convert the value to a number
        var numVal = boxToNumber(value);

        // If the value is not a number, return it directly
        if (typeof numVal !== 'number')
            return numVal;

        // Store the value in the new object
        // TODO: this should be a hidden/internal property
        this.value = numVal;
    }
    else
    {
        // Convert the value to a number
        return boxToNumber(value);
    }
}

// Set the number prototype object
Number.prototype = get_ctx_numproto(iir.get_ctx());

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
    if (boxIsInt(num))
    {
        return num;
    }
    else if (boxIsObj(num))
    {
        return num.value;
    }
}

/**
15.7.4.2 Number.prototype.toString ([ radix ])
*/
Number.prototype.toString = function (radix)
{
    var num = getNumVal(this);

    //FIXME: for now, ignoring the radix

    return boxToString(num);
};

/**
15.7.4.4 Number.prototype.valueOf ( )
*/
Number.prototype.valueOf = function ()
{
    return getNumVal(this);
};

