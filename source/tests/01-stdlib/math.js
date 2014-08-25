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

/*
For now, since we only have integer support, only the integer behavior of the
library is tested.
*/

function test_abs()
{
    assert (Math.abs(0) === 0)

    assert (Math.abs(1) === 1)

    assert (Math.abs(-1) === 1)

    assert (Math.abs(5) === 5)

    assert (Math.abs(-5) === 5)
}

function test_ceil()
{
    assert (Math.ceil(0) === 0)

    assert (Math.ceil(3) === 3)

    assert (Math.ceil(-3) === -3)
}

function test_floor()
{
    assert (Math.floor(0) === 0)

    assert (Math.floor(3) === 3)

    assert (Math.floor(-3) === -3)
}

function test_round()
{
    assert (Math.round(0) === 0);

    assert (Math.round(1) === 1);

    assert (Math.round(1.1) === 1);

    assert (Math.round(1.5) === 2);

    assert (Math.round(-1.6) === -2);
}

function test_max()
{
    assert (Math.max() === -Infinity);

    assert (Math.max(1) === 1);

    assert (Math.max(0, 1) === 1)

    assert (Math.max(-5, 2) === 2)

    assert (Math.max(1, 2, 9, 3, 4) === 9)

    assert (Math.max(-8, -9, -3, -5, -7) === -3)
}

function test_min()
{
    assert (Math.min() === Infinity);

    assert (Math.min(1) === 1);

    assert (Math.min(0, 1) === 0)

    assert (Math.min(-5, 2) === -5)

    assert (Math.min(1, 2, 9, -3, 4) === -3)

    assert (Math.min(-8, -9, -3, -5, -11, -7) === -11)
}

function test_pow()
{
    assert (Math.pow(0, 0) === 1)

    assert (Math.pow(1, 0) === 1)

    assert (Math.pow(1, 2) === 1)

    assert (Math.pow(2, 2) === 4)

    assert (Math.pow(3, 9) === 19683)
}

function test_tan()
{
    assert (Math.tan(0) === 0);

    assert (Math.tan(Math.PI) < 1e-3);

    assert (Math.tan(Math.PI/4) - 1 < 1e-3);
}

test_abs();

test_ceil();

test_floor();

test_round();

test_max();

test_min();

test_pow();

test_tan();

