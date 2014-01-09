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

function test_add(x, y)
{
    return x + y;
}

function test_add3(x)
{
    return x + 3;
}

function test_3add(x)
{
    return 3 + x;
}

function test_sub(x, y)
{
    return x - y;
}

function test_sub3(x)
{
    return x - 3;
}

function test_3sub(x)
{
    return 3 - x;
}

function test_mul(x, y)
{
    return x * y;
}

function test_mul3(x)
{
    return x * 3;
}

function test_3mul(x)
{
    return 3 * x;
}

function test_div(x, y)
{
    return x / y;
}

function test_div3(x)
{
    return x / 3;
}

function test_9div(x)
{
    return 9 / x;
}

function test_mod(x, y)
{
    return x % y;
}

function test_mod3(x)
{
    return x % 3;
}

function test_3mod(x)
{
    return 3 % x;
}

function test()
{
    if (test_add(1, 3) !== 4)
        return 1;
    if (test_add(3, -2) !== 1)
        return 2;
    if (test_add3(3) !== 6)
        return 3;
    if (test_3add(2) !== 5)
        return 4;

    if (test_sub(3, 2) !== 1)
        return 5;
    if (test_sub3(7) !== 4)
        return 6;
    if (test_3sub(1) !== 2)
        return 7;

    if (test_mul(3, -2) !== -6)
        return 8;
    if (test_mul(5, 2) !== 10)
        return 9;
    if (test_mul3(4) !== 12)
        return 10;
    if (test_3mul(5) !== 15)
        return 11;

    if (test_div(6, 3) !== 2)
        return 12;
    if (test_div(6, -3) !== -2)
        return 13;
    if (test_div(5, 3) === 1)
        return 14;
    if (test_div(-5, 3) === -1)
        return 15;
    if (test_div(5, 4) === 1)
        return 16;
    if (test_div(5, 2) === 2)
        return 17;
    if (test_div(5, -2) === -2)
        return 18;
    if (test_div3(9) !== 3)
        return 19;
    if (test_9div(3) !== 3)
        return 20;

    if (test_mod(5, 3) !== 2)
        return 21;
    if (test_mod(-5, 3) !== -2)
        return 22;
    if (test_mod(5, -2) !== 1)
        return 23;
    if (test_mod3(5) !== 2)
        return 24;
    if (test_3mod(2) !== 1)
        return 25;

    return 0;
}

