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

function test()
{
    var map = new Map();

    var keyList = [];
    var valList = [];

    for (var i = 0; i < 50; ++i)
    {
        keyList.push('k' + i);
        valList.push(i);
    }

    for (var i = 0; i < 50; ++i)
    {
        keyList.push(i);
        valList.push('v' + i);
    }

    /*
    print('num items: ' + map.length);
    print('num slots: ' + map.numSlots);
    print('array length: ' + map.array.length);
    */

    for (var i = 0; i < keyList.length; ++i)
    {
        /*
        print('key: ' + keyList[i]);
        print('val: ' + valList[i]);
        print('hash: ' + defHashFunc(keyList[i]));
        */

        map.set(keyList[i], valList[i]);
    }

    /*
    print('getting items');
    */

    for (var i = 0; i < keyList.length; ++i)
    {
        if (!map.has(keyList[i]))
            return 1;

        var val = map.get(keyList[i]);

        /*
        print('key: ' + keyList[i]);
        print('val: ' + valList[i]);
        print('got: ' + val);
        */

        if (val !== valList[i])
            return 2;
    }

    ITR_LOOP:
    for (var itr = map.getItr(); itr.valid(); itr.next())
    {
        var cur = itr.get();

        for (var i = 0; i < keyList.length; ++i)
        {
            if (keyList[i] === cur.key)
            {
                if (valList[i] !== cur.value)
                    return 3;

                continue ITR_LOOP;
            }
        }

        return 4;
    }

    for (var i = 0, c = 0; i < keyList.length; ++i, ++c)
    {
        if (c % 3 === 0)
        {
            map.delete(keyList[i]);

            keyList.splice(i, 1);
            valList.splice(i, 1);

            --i;
        }
    }

    for (var i = 0; i < keyList.length; ++i)
    {
        if (!map.has(keyList[i]))
            return 5;

        var val = map.get(keyList[i]);

        if (val !== valList[i])
            return 6;
    }

    return 0;
}

