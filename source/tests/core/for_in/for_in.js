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
 *  Copyright (c) 2011-2014, Universite de Montreal
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

function validate(propNames, valid)
{
    if (valid.length !== propNames.length)
        return false;

    VALID_LOOP:
    for (var i = 0; i < valid.length; ++i)
    {
        var v = valid[i];

        for (var j = 0; j < propNames.length; ++j)
        {
            var p = propNames[j];

            if (v === p)
                continue VALID_LOOP;
        }

        // Property not found
        return false;
    }

    return true;
}

function test()
{
    // o is an array which also has the keys 'x' and 'y'
    var o = [3,4,5];
    o.x = 1;
    o.y = 2;

    // keys we expect to find in o
    var expected = [0,1,2,'x','y'];

    // check that we find the expected properties
    // Note: the code is written in a convoluted style to avoid
    // needing to use the stdlib Array functions, runtime only.
    var propNames = [];
    for (k1 in o)
        propNames[propNames.length] = k1;
    if (validate(propNames, expected) !== true)
        return 1;

    // check a second time
    var propNames = [];
    for (var k2 in o)
        propNames[propNames.length] = k2;
    if (validate(propNames, expected) !== true)
        return 2;

    return 0;
}

