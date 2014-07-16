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
var s1 = new Set();

assert(s1.length === 0);

s1.add(1);
assert(s1.has(1));
assert(s1.length === 1);

assert(!s1.has(2));
s1.add(2);
assert(s1.has(2));
assert(s1.length === 2);

s1.rem(1);
assert(!s1.has(1));
assert(s1.length === 1);

var s2 = s1.copy();
assert(s1.length === s2.length);
assert(s2.diff(s1).length === 0);

var s3 = new Set().addArray([1,2,3]); 
assert(s3.length === 3);
assert(s3.has(1));
assert(s3.has(2));
assert(s3.has(3));

var s4 = s3.copy().diff(s1);
assert(s4.length === 2);
assert(s4.has(1));
assert(s4.has(3));
assert(!s4.has(2));

var s5 = s3.copy().remArray([1,2,3]);
assert(s5.length === 0);
assert(!s5.has(1));
assert(!s5.has(2));
assert(!s5.has(3));

var s6 = s3.copy().union(new Set().addArray([4,5,6]));
assert(s6.length === 6);
assert(s6.has(1));
assert(s6.has(2));
assert(s6.has(3));
assert(s6.has(4));
assert(s6.has(5));
assert(s6.has(6));

var s7 = s3.copy().intr(new Set().addArray([2,3,4]));
assert(s7.length === 2);
assert(!s7.has(1));
assert(s7.has(2));
assert(s7.has(3));
assert(!s7.has(4));

assert(s3.equal(s3.copy()));

assert(s3.copy().clear().length === 0);
*/

