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
15.6.1 The Boolean function/constructor
new Boolean([ value ])
Boolean([ value ])
*/
function Boolean(value)
{
    // If this is a constructor call (new Boolean)
    if ($rt_isGlobalObj(this) === false)
    {
        // Convert the value to a boolean
        var boolVal = $rt_toBool(value);

        // If the value is not a boolean, return it directly
        if (typeof boolVal !== 'boolean')
            return boolVal;

        // Store the value in the new object
        // TODO: this should be a hidden/internal property
        this.value = boolVal;
    }
    else
    {
        // Convert the value to a boolean
        return $rt_toBool(value);
    }
}

//-----------------------------------------------------------------------------

/**
15.6.4.2 Number.prototype.toString ()
*/
Boolean.prototype.toString = function ()
{
    var b;

    if (typeof this === 'boolean')
        b = this;
    else if (this instanceof Boolean)
        b = this.value;
    else
        throw new TypeError('expected boolean');

    return b? 'true':'false';
};

/**
15.6.4.3 Number.prototype.valueOf ()
*/
Boolean.prototype.valueOf = function ()
{
    var b;

    if (typeof this === 'boolean')
        b = this;
    else if (this instanceof Boolean)
        b =  this.value;
    else
        throw new TypeError('expected boolean');

    return b? true:false;
};

