/// Copyright (c) 2012 Ecma International.  All rights reserved. 
/// Ecma International makes this code available under the terms and conditions set
/// forth on http://hg.ecmascript.org/tests/test262/raw-file/tip/LICENSE (the 
/// "Use Terms").   Any redistribution of this code must retain the above 
/// copyright and this notice and otherwise comply with the Use Terms.
/**
 * @path ch11/11.4/11.4.1/11.4.1-5-a-10-s.js
 * @description Strict Mode - SyntaxError is thrown when deleting a variable of type Array
 * @onlyStrict
 */


function testcase() {
        "use strict";
        var arrObj = [1,2,3];

        try {
            eval("delete arrObj;");
            return false;
        } catch (e) {
            return e instanceof SyntaxError;
        }
    }
runTestCase(testcase);
