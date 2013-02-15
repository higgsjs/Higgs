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

function test_and(x, y)
{
    return x & y;
}

function test_and3(x)
{
    return x & 3;
}

function test_3and(y)
{
    return 3 & y;
}

function test_or(x, y)
{
    return x | y;
}

function test_or75(x)
{
    return x | 75;
}

function test_75or(x)
{
    return 75 | x;
}

function test_xor(x, y)
{
    return x ^ y;
}

function test_xor101(x)
{
    return x ^ 101;
}

function test_101xor(x)
{
    return 101 ^ x;
}

function test_not(x)
{
    return ~x;
}

function test()
{
    if (test_and(7, 2) !== 2)
        return 1;
    if (test_and3(9) !== 1)
        return 2;
    if (test_3and(9) !== 1)
        return 3;
    if (test_and(-1, 2) !== 2)
        return 4;
    if (test_and(-1, 0xFFFFFFFF) !== -1)
        return 5;

    if (test_or(11, 33) !== 43)
        return 6;
    if (test_or75(42) !== 107)
        return 7;
    if (test_75or(43) !== 107)
        return 8;

    if (test_xor(93, 107) !== 54)
        return 9;
    if (test_xor101(69) !== 32)
        return 10;
    if (test_101xor(69) !== 32)
        return 11;

    if (test_not(1) !== -2)
        return 12;
    if (test_not(-3) !== 2)
        return 13;
    if (test_not(-2147483648) !== 2147483647)
        return 14;

    return 0;
}

