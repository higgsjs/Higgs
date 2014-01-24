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

function lshift_test(x,y)
{
    return x << y;
}

function lshift_test2(x)
{
    return x << 3;
}

function rshift_test(x,y)
{
    return x >> y;
}

function rshift_test2(x)
{
    return x >> 2;
}

function rshift_test3(x)
{
    return x >> 1;
}

function urshift_test(x,y)
{
    return x >>> y;
}

function urshift_test2(x)
{
    return x >>> 30;
}

function shift_out_bits(n, k)
{
    return (n >> k) << k;
}

function test()
{
    if (lshift_test(2,3) !== 16)
        return 1;
    if (lshift_test(0xFFFFFFFF, 1) !== -2)
        return 2; 
    if (lshift_test2(2) !== 16)
        return 3;
 
    if (rshift_test(8,2) !== 2)
        return 4;
    if (rshift_test(0xFFFFFFFF, 1) !== -1)
        return 5;
    if (rshift_test2(8) !== 2)
        return 5;
    if (rshift_test(-2, 1) !== -1)
        return 6;
    if (rshift_test3(-2) !== -1)
        return 8;

    if (urshift_test(-2, 30) !== 3)
        return 9;
    if (urshift_test(0xFFFFFFFF, 1) !== 0x7FFFFFFF)
        return 11;
    if (urshift_test2(-2) !== 3)
        return 10;

    if (shift_out_bits(15, 2) !== 12)
        return 12;

    return 0;
}

