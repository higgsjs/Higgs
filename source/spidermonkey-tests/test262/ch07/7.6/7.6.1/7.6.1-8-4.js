/// Copyright (c) 2012 Ecma International.  All rights reserved. 
/// Ecma International makes this code available under the terms and conditions set
/// forth on http://hg.ecmascript.org/tests/test262/raw-file/tip/LICENSE (the 
/// "Use Terms").   Any redistribution of this code must retain the above 
/// copyright and this notice and otherwise comply with the Use Terms.
/**
 * @path ch07/7.6/7.6.1/7.6.1-8-4.js
 * @description Allow reserved words as property names by set function within an object, accessed via indexing: new, var, catch
 */


function testcase() {
        var test0 = 0, test1 = 1, test2 = 2;
        var tokenCodes  = {
            set new(value){
                test0 = value;
            },
            get new(){
                return test0;
            },
            set var(value){
                test1 = value;
            },
            get var(){
                return test1;
            },
            set catch(value){
                test2 = value;
            },
            get catch(){
                return test2;
            }
        }; 
        var arr = [
            'new', 
            'var', 
            'catch'
        ];
        for (var i = 0; i < arr.length; i++) {
            if (tokenCodes[arr[i]] !== i) {
                return false;
            };
        }
        return true;
    }
runTestCase(testcase);
