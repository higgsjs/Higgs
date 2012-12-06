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

/**
@fileOverview
Implementation of ECMAScript 5 Function methods and prototype.

@author
Maxime Chevalier-Boisvert

@copyright
Copyright (c) 2010-2011 Tachyon Javascript Engine, All Rights Reserved
*/

/**
15.3.2 The function constructor
*/
function Function()
{
    // TODO
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
Get a string representation of the IR
Note: this method is not part of standard JS
*/
Function.prototype.irString = function ()
{
    return $ir_get_ir_str(this);
}

/**
15.3.4.3 Function.prototype.apply (thisArg, argArray)
*/
Function.prototype.apply = function (thisArg, argArray)
{
    if (boxIsFunc(this) === false)
        typeError('apply on non-function');

    if (argArray === null || argArray === UNDEFINED)
        argArray = [];

    if (boxIsArray(argArray) === false)
        typeError('invalid arguments array');

    // Get the function pointer for the function
    var funcPtr = get_clos_funcptr(this);

    // Get the arguments table from the array
    var argTable = unboxRef(get_arr_arr(argArray));

    // Get the number of arguments
    var numArgs = iir.icast(IRType.pint, get_arr_len(argArray));

    // Perform the call using the apply instruction
    var retVal = iir.call_apply(funcPtr, this, thisArg, argTable, numArgs);

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
        thisArg = getGlobalObj();

    var argArray = [];
    for (var i = 1; i < arguments.length; ++i)
        argArray.push(arguments[i]);

    var retVal = this.apply(thisArg, argArray);

    return retVal;
};

