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

/**
15.3.2 ECMAScript function constructor
*/
function Function()
{
    // TODO: support for new Function(...)
}

// Set the function prototype object
Function.prototype = $ir_get_fun_proto();

Function.prototype.length = 0;

//-----------------------------------------------------------------------------

/**
15.3.4.2 Function.prototype.toString ()
*/
Function.prototype.toString = function ()
{
    // Return the function AST as a string
    return $ir_get_ast_str(this);
};

/**
Get a string representation of the IR for this function
Note: this method is not part of ECMAScript
*/
Function.prototype.irString = function ()
{
    return $ir_get_ir_str(this);
}

/**
Get a string representation of the machine code for this function
Note: this method is not part of ECMAScript
*/
Function.prototype.asmString = function ()
{
    return $ir_get_asm_str(this);
}

/**
15.3.4.3 Function.prototype.apply (thisArg, argArray)
*/
Function.prototype.apply = function (thisArg, argArray)
{
    if (typeof this !== 'function')
        throw new TypeError('apply on non-function');

    if (argArray === null || argArray === undefined)
        argArray = [];

    if (!$rt_valIsLayout(argArray, $rt_LAYOUT_ARR))
        throw new TypeError('invalid arguments array');

    // Get the arguments table from the array
    var argTable = $rt_arr_get_tbl(argArray);

    // Get the number of arguments
    var numArgs = argArray.length;

    // Perform the call using the apply instruction
    var retVal = $ir_call_apply(this, thisArg, argTable, numArgs);

    return retVal;
};

/**
15.3.4.4 Function.prototype.call (thisArg [, arg1 [, arg2, … ]])
*/
Function.prototype.call = function (thisArg)
{
    // If the this argument is null or undefined,
    // make it the global object
    if (thisArg === null || thisArg === undefined)
        thisArg = $ir_get_global_obj();

    var argArray = [];
    for (var i = 1; i < $argc; ++i)
        argArray.push($ir_get_arg(i));

    var retVal = this.apply(thisArg, argArray);

    return retVal;
};

/**
15.3.4.5 Function.prototype.bind (thisArg [, arg1 [, arg2, … ]])
*/
Function.prototype.bind = function(thisArg)
{
    if (typeof this !== 'function')
        throw new TypeError('bind on non-function');

    var unbound = this;
    var boundArguments = arguments.length > 1 ?
        [].slice.call(arguments, 1) : [];

    function bound() {
        var target = this instanceof bound ? this : thisArg;

        var fullArguments = boundArguments.length > 0 ?
            boundArguments.concat(arguments) : arguments;

        return unbound.apply(target, fullArguments);
    }

    bound.prototype = unbound.prototype;
    return bound;
};
