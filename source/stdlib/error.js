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
 *  Copyright (c) 2012, Universite de Montreal
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
Implementation of JavaScript native error classes.

@author
Maxime Chevalier-Boisvert

@copyright
Copyright (c) 2012 Maxime Chevalier-Boisvert, All Rights Reserved
*/

/**
Function to create an error constructor function
*/
function makeErrorCtor(errorName, protoParent)
{
    // Get the global this value
    var globalThis = this;

    // Error constructor function
    function ErrorCtor(message)
    {
        if (this === globalThis)
            var newObj = new ErrorCtor(message);
        else
            var newObj = this;    

        if (message !== undefined)
            this.message = message.toString();

        return newObj;
    }

    // FIXME
    // Create the prototype object for this error constructor
    //ErrorCtor.prototype = Object.create(protoParent);

    // Set the error name in the error prototype object
    ErrorCtor.prototype.name = errorName;

    // The default error message is the empty string
    ErrorCtor.prototype.message = '';

    // Set the prototype constructor to the error constructor
    ErrorCtor.prototype.constructor = ErrorCtor;

    // Return the new error constructor function
    return ErrorCtor;
}

/**
Constructor function for error objects
*/
var Error = makeErrorCtor(
    'Error',
    $ir_get_obj_proto()
);

/**
ToString function of the error prototype object
*/
Error.prototype.toString = function ()
{
    if (this.message === undefined)
        return undefined;

    var name = (this.name === undefined)? 'Error':this.name;

    return name + ': ' + this.message;
};

/*
@class RangeError
@description
15.11.6.2 RangeError
Indicates a numeric value has exceeded the allowable range. 
*/
var RangeError = makeErrorCtor(
    'RangeError',
    Error.prototype
);

/*
@class ReferenceError
@description
15.11.6.3 ReferenceError
Indicate that an invalid reference value has been detected.
*/
var ReferenceError = makeErrorCtor(
    'ReferenceError',
    Error.prototype
);

/**
@class SyntaxError
@description
15.11.6.4 SyntaxError
Indicates that a parsing error has occurred.
*/
var SyntaxError = makeErrorCtor(
    'SyntaxError',
    Error.prototype
);

/**
@class TypeError
@description
15.11.6.5 TypeError
Indicates the actual type of an operand is different than the expected type.
*/
var TypeError = makeErrorCtor(
    'TypeError',
    Error.prototype
);

/**
@class URIError
@description
15.11.6.6 URIError
Indicates that one of the global URI handling functions was used in a way
that is incompatible with its definition.
*/
var URIError = makeErrorCtor(
    'URIError',
    Error.prototype
);

