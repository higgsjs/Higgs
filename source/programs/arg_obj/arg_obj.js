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

function foo1(a0, a1, a2)
{
    return (
        arguments[0] +
        arguments[1] +
        arguments[2]
    );

    return 0;
}

function foo2(a0, a1, a2, a4, a5, a6)
{
    return (
        arguments[0] +
        arguments[1] +
        arguments[2]
    );
}

function foo3(x)
{
    return arguments.length;
}

function foo4()
{
    return (
        arguments.length + 
        arguments[0] + 
        arguments[1] +
        arguments[2] + 
        arguments[3] + 
        arguments[4] + 
        arguments[5] + 
        arguments[6] + 
        arguments[7] +
        arguments[8] + 
        arguments[9]
    );
}

function foo5(x, y, z, w, q, s)
{
    return (
        arguments.length + 
        arguments[0] + 
        arguments[1] +
        arguments[2] + 
        arguments[3] + 
        arguments[4] + 
        arguments[5] + 
        arguments[6] + 
        arguments[7] +
        arguments[8] + 
        arguments[9]
    );
}

function foo6()
{
    if (typeof this !== 'object')
        return 1;

    return arguments[0];
}

function test()
{
    if (foo1(1,2,3) !== 6)
        return 100;
    if (foo1(1,2,3,7) !== 6)
        return 101;
    if (foo1(1,2,3,7,7) !== 6)
        return 102;

    if (foo2(1,2,3) !== 6)
        return 200;
    if (foo2(1,2,3,7) !== 6)
        return 201;
    if (foo2(1,2,3,7,7) !== 6)
        return 202;

    if (foo3() !== 0)
        return 300;
    if (foo3(1) !== 1)
        return 301;
    if (foo3(7,7) !== 2)
        return 302;
    if (foo3(7,7,7) !== 3)
        return 303;
    if (foo3(7,7,7,7) !== 4)
        return 304;
    if (foo3(7,7,7,7,7) !== 5)
        return 305;
   
    if (foo4(0,1,2,3,4,5,6,7,8,9) !== 55)
        return 400;

    if (foo5(0,1,2,3,4,5,6,7,8,9) !== 55)
        return 500;

    var o = { foo6: foo6 };
    if (o.foo6(1337) !== 1337)
        return 600;

    return 0;
}

