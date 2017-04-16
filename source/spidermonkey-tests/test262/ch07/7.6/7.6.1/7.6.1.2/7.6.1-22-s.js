/// Copyright (c) 2012 Ecma International.  All rights reserved. 
/// Ecma International makes this code available under the terms and conditions set
/// forth on http://hg.ecmascript.org/tests/test262/raw-file/tip/LICENSE (the 
/// "Use Terms").   Any redistribution of this code must retain the above 
/// copyright and this notice and otherwise comply with the Use Terms.
/**
 * @path ch07/7.6/7.6.1/7.6.1.2/7.6.1-22-s.js
 * @description 7.6 - SyntaxError expected: reserved words used as Identifier Names in UTF8: inte\u0072face (interface)
 * @onlyStrict
 */




function testcase() {
        "use strict";

        try {
            eval("var inte\u0072face = 123;");
            return false;
        } catch (e) {
            return e instanceof SyntaxError;
        }
}
runTestCase(testcase);