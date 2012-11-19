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

/**
Get the string representation of a value
*/
function $rt_toString(v)
{
    var type = typeof v;

    if (type === "undefined")
        return "undefined";

    if (type === "boolean")
        return v? "true":"false";

    if (type === "string")
        return v;

    if (type === "number")
        return "number value, TODO!";

    if (type === "object")
        return v? v.toString():"null";

    if (type === "function" || type === "array")
        return v.toString();

    return "unhandled type in toString";
}

/**
JS typeof operator
*/
function $rt_typeof(v)
{
    // TODO
}

/**
JS addition operator
*/
function $rt_add(x, y)
{
    // If both values are integer
    if ($ir_is_int(x) && $ir_is_int(y))
    {
        var r;
        if (r = $ir_add_i32_ovf(x, y))
        {
            return r;
        }
        else
        {
            var fx = $ir_i32_to_f64(x);
            var fy = $ir_i32_to_f64(y);
            return $ir_add_f64(fx, fy);
        }
    }

    // If either value is floating-point or integer
    else if (
        ($ir_is_float(x) || $ir_is_int(x)) &&
        ($ir_is_float(y) || $ir_is_int(y)))
    {
        var fx = $ir_is_float(x)? x:$ir_i32_to_f64(x);
        var fy = $ir_is_float(y)? y:$ir_i32_to_f64(y);

        return $ir_add_f64(fx, fy);
    }

    // Evaluate the string value of both arguments
    var sx = $rt_toString(x);
    var sy = $rt_toString(y);


    // TODO: need $rt_strcat



    /*
    auto l0 = str_get_len(s0);
    auto l1 = str_get_len(s1);

    auto sO = str_alloc(interp, l0+l1);

    for (size_t i = 0; i < l0; ++i)
        str_set_data(sO, i, str_get_data(s0, i));
    for (size_t i = 0; i < l1; ++i)
        str_set_data(sO, l0+i, str_get_data(s1, i));

    compStrHash(sO);
    sO = getTableStr(interp, sO);

    interp.setSlot(
        instr.outSlot, 
        Word.ptrv(sO),
        Type.STRING
    );
    */
}

/**
JS subtraction operator
*/
function $rt_sub(x, y)
{
    // TODO

}

