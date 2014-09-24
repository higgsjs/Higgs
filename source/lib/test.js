/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2014, Maxime Chevalier-Boisvert. All rights reserved.
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
Assert functions for basic unit/regression tests.
*/
(function(exports)
{
    var global = this;

    /**
    Check that two values are the same
    */
    function isSameVal(val1, val2)
    {
        //check for +0 and -0
        if (val1 === 0 && val2 === 0)
            return (1 / val1) === (1 / val2);

        // Check for NaN
        if (val1 !== val1 && val2 !== val2)
            return true;

        return val1 === val2;
    }

    /**
    Assert two values are equal
    */
    global.assertEq = function(val, expected, msg)
    {
        if(!isSameVal(val, expected))
            throw new Error("Assertion failed: got '" + val + "' expected '" + expected + "'" +
                                (msg ? " : " + msg : ""));
    };

    /**
    Assert two values are not equal
    */
    global.assertNotEq = function(val, different, msg)
    {
        if(isSameVal(val, different))
            throw new Error("Assertion failed: got '" + val + "' expected something else " +
                                (msg ? " : " + msg : ""));
    };

    /**
    Assert a function throws an error when called
    */
    global.assertThrows = function(fun, msg)
    {
        var thrown = false;

        try
        {
            fun();
        }
        catch (e) 
        {
            thrown = true;
        }

        if (!thrown)
            throw new Error("Assertion failed: function did not throw exception" +
                                (msg ? " : " + msg : ""));
    };

    /**
    Check that two arrays contain the same values
    */
    global.assertEqArray = function(arr1, arr2, msg)
    {
        var i = arr1.length;
        var len = arr2.length;

        if (i !== len)
            throw new Error("Assertion failed: expected equal arrays but lengths not the same" +
                                (msg ? " : " + msg : ""));

        while (i--)
            if (!isSameVal(arr1[i], arr2[i]))
                throw new Error("Assertion failed: expected equal arrays mismatch at index " + i +
                                    (msg ? " : " + msg : ""));
    };

    /**
    Assert a value is truthy
    */
    global.assertTrue = function(val, msg)
    {
        if (!val)
            throw new Error("Assertion failed: expected truthy value got '" + val +"'" +
                                (msg ? " : " + msg : ""));
    };

    /**
    Assert a value is false
    */
    global.assertFalse = function(val, msg)
    {
        if (val)
            throw new Error("Assertion failed: expected falsey value, got: '" + val + "'" +
                                (msg ? " : " + msg : ""));
    };

    exports.isSameVal = isSameVal;

})(exports);

