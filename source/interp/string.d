/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012, Maxime Chevalier-Boisvert. All rights reserved.
*
*  This software is licensed under the following license (Modified BSD
*  License):
*
*  Redistribution and use in source and binary forms, with or without
*  modification, are permitted provided that the following conditions are
*  met:
*   1. Redistributions of source code must retain the above copyright
*      notice, this list of conditions and the following disclaimer.
*   2. Redistributions in binary form must reproduce the above copyright
*      notice, this list of conditions and the following disclaimer in the
*      documentation and/or other materials provided with the distribution.
*   3. The name of the author may not be used to endorse or promote
*      products derived from this software without specific prior written
*      permission.
*
*  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
*  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
*  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
*  NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
*  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
*  NOT LIMITED TO PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
*  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
*  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
*  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
*  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
*****************************************************************************/

module interp.string;

import std.stdio;
import std.string;
import interp.interp;
import interp.layout;

immutable size_t STR_TBL_INIT_SIZE = 101;
immutable size_t STR_TBL_MAX_LOAD_NUM = 3;
immutable size_t STR_TBL_MAX_LOAD_DENOM = 5;

int compStrHash(wstring str)
{
    /*
    // TODO: operate on multiple characters at a time, look at Murmur hash

    var hashCode = 0;

    for (var i = 0; i < val.length; ++i)
    {
        var ch = val.charCodeAt(i);
        hashCode = (((hashCode << 8) + ch) & 536870911) % 426870919;
    }

    return hashCode;
    */

    return 0;
}

void allocStrTable(Interp* interp)
{
    // TODO
}

void extStrTable(/*curTbl, curSize, numStrings*/)
{
    // TODO
}

void streq(/*str1, str2*/)
{
    // TODO
}

refptr getString(Interp*, wchar* buffer, size_t len)
{
    // TODO
    return null;
}

