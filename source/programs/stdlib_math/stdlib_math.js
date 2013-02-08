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

/*
For now, since we only have integer support, only the integer behavior of the
library is tested.
*/

function test_abs()
{
    if (Math.abs(0) !== 0)
        return 1;
    if (Math.abs(1) !== 1)
        return 2;
    if (Math.abs(-1) !== 1)
        return 3;
    if (Math.abs(5) !== 5)
        return 3;
    if (Math.abs(-5) !== 5)
        return 3;

    return 0;
}

function test_ceil()
{
    if (Math.ceil(0) !== 0)
        return 1;
    if (Math.ceil(3) !== 3)
        return 2;
    if (Math.ceil(-3) !== -3)
        return 3;

    return 0;
}

function test_floor()
{
    if (Math.floor(0) !== 0)
        return 1;
    if (Math.floor(3) !== 3)
        return 2;
    if (Math.floor(-3) !== -3)
        return 3;

    return 0;
}

function test_round()
{
    if (Math.round(0) !== 0)
        return 1;
    if (Math.round(1) !== 1)
        return 2;
    if (Math.round(1.1) !== 1)
        return 3;
    if (Math.round(1.5) !== 2)
        return 4;
    if (Math.round(-1.6) !== -2)
        return 5;

    return 0;
}

function test_max()
{
    if (Math.max(0, 1) !== 1)
        return 1;
    if (Math.max(-5, 2) !== 2)
        return 2;
    if (Math.max(1, 2, 9, 3, 4) !== 9)
        return 3;
    if (Math.max(-8, -9, -3, -5, -7) !== -3)
        return 4;

    return 0;
}

function test_min()
{
    if (Math.min(0, 1) !== 0)
        return 1;
    if (Math.min(-5, 2) !== -5)
        return 2;
    if (Math.min(1, 2, 9, -3, 4) !== -3)
        return 3;
    if (Math.min(-8, -9, -3, -5, -11, -7) !== -11)
        return 4;

    return 0;
}

function test_pow()
{
    if (Math.pow(0, 0) !== 1)
        return 1;
    if (Math.pow(1, 0) !== 1)
        return 2;
    if (Math.pow(1, 2) !== 1)
        return 3;
    if (Math.pow(2, 2) !== 4)
        return 4;
    if (Math.pow(3, 9) !== 19683)
        return 5;

    return 0;
}

function test()
{
    var r = test_abs();
    if (r !== 0)
        return 100 + r;

    var r = test_ceil();
    if (r !== 0)
        return 200 + r;

    var r = test_floor();
    if (r !== 0)
        return 300 + r;

    var r = test_round();
    if (r !== 0)
        return 400 + r;

    var r = test_max();
    if (r !== 0)
        return 500 + r;

    var r = test_min();
    if (r !== 0)
        return 600 + r;

    var r = test_pow();
    if (r !== 0)
        return 700 + r;

    return 0;
}

