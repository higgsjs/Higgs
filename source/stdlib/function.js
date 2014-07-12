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
    var argList = [];
    var body = '';

    if ($argc > 0)
        body = String($ir_get_arg($argc - 1));

    for (var i = 0; i < $argc - 1; ++i)
    {
        var param = String($ir_get_arg(i));

        // We're supposed to throw a SyntaxError if the parameters don't
        // form a valid FormalParameterList here, but I have no idea if
        // this can be verified from here, so instead just making sure
        // we'll generate a valid function and leaving that check to
        // eval
        if (param.indexOf(')') !== -1)
            throw new SyntaxError('Unexpected ) in formal parameter ' + param);

        argList.push(param);
    }

    // We're supposed to throw a syntax error if the body isn't a valid
    // FunctionBody as well, but here there isn't any straight-forward
    // way of checking that, which would allow people to do things like:
    //
    // new Function('a', 'b', '}; nastyStuff(); function(){')
    //
    // So we'll just check if the brackets are balanced and leave all
    // the real parsing job to the internal parser. This will just
    // guarantee that we can't "break" from the function declaration
    // regardless of the given FunctionBody.
    if (!isValidFunctionBody(body))
        throw new SyntaxError('Invalid function body');

    var fn = 'function(' + argList.join(', ') + '){\n' + body + '\n}';
    return $ir_eval_str(fn);

    function isValidFunctionBody(body) 
    {
        var i = 0;
        var brackets = 0;
        while (i < body.length)
        {
            var current = body.charAt(i);
            switch (current)
            {
                case '"':
                case "'":
                    i = skipString(body, current, i + 1);
                    break;
                case '/':
                    var lookAhead = body.charAt(i + 1)
                    if (lookAhead == '/')
                        i = skipLineComment(body, i + 2);
                    else if (lookAhead == '*')
                        i = skipBlockComment(body, i + 2);
                    break;
                case '{':
                    ++brackets;
                    ++i;
                    break;
                case '}':
                    --brackets;
                    if (brackets < 0)
                        throw new SyntaxError('Unexpected }');
                    ++i;
                    break;
                default:
                    ++i;
            }
        }

        return brackets === 0;
    }

    function skipString(body, quote, i)
    {
        while (i < body.length) {
            var current = body.charAt(i);
            switch (current)
            {
                case quote:
                    return i + 1;
                case '\\':
                    ++i;
                    break;
                case '\r':
                case '\n':
                    throw new SyntaxError('Unterminated string literal');
            }
            ++i;
        }

        throw new SyntaxError('Unterminated string literal');
    }

    function skipLineComment(body, i)
    {
        while (i < body.length) {
            var current = body.charAt(i);
            if (current === '\n' || current === '\r')
                return i + 1;
            ++i;
        }

        return i;
    }

    function skipBlockComment(body, i)
    {
        while (i < body.length)
        {
            var current   = body.charAt(i);
            var lookAhead = body.charAt(i + 1);
            if (current === '*' && lookAhead === '/')
                return i + 2;
            ++i;
        }

        throw new SyntaxError('Unterminated block comment');
    }
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
    if (!$ir_is_closure(this))
        throw new TypeError('apply on non-function');

    if (argArray === null || argArray === undefined)
        argArray = [];

    if (!$ir_is_array(argArray))
        throw new TypeError('invalid arguments array');

    // If the this argument is null or undefined,
    // make it the global object
    if (thisArg === null || thisArg === undefined)
        thisArg = $ir_get_global_obj();

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
    var bound;
    if (arguments.length > 1)
    {
        var args = [].slice.call(arguments, 1);
        bound = function()
        {
            var target = this instanceof bound ? this : thisArg;
            return unbound.apply(target, args.concat(arguments));
        };
    }
    else
    {
        bound = function()
        {
            var target = this instanceof bound ? this : thisArg;
            return unbound.apply(target, arguments);
        };
    }

    bound.prototype = unbound.prototype;
    return bound;
};

// Make the Function.prototype properties non-enumerable
for (p in Function.prototype)
{
    Object.defineProperty(
        Function.prototype,
        p,
        {enumerable:false, writable:true, configurable:true }
    );
}

