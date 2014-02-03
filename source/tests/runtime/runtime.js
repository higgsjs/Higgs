/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013, Maxime Chevalier-Boisvert. All rights reserved.
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

(function(){

    var test = require('lib/test');

    /**
    Test .hasOwnProperty() (see issue #57)
    */

    var my_str = "012";
    var my_arr = [0, 1, 2];
    my_arr.foo = "bar";
    var oneOb = { toString: function(){ return '1'; } };

    // These cases aren't actually covered by the code in $rt_hasOwnProp,
    // but should fail during property lookup
    assertThrows(function()
    {
        (null).hasOwnProperty('foo');
    });

    assertThrows(function()
    {
        (undefined).hasOwnProperty('foo');
    });

    // $rt_hasOwnProp will cover these cases:

    // Has own property checks for consts/nums/etc should always be false
    assertFalse((false).hasOwnProperty('foo'), "false has no own props");
    assertFalse((true).hasOwnProperty('foo'), "true has no own props");
    assertFalse((1).hasOwnProperty('foo'), "1 has no own props");
    assertFalse((1.0).hasOwnProperty('foo'), "1.0 has no own props");

    // Strings/Arrays should have a 'length' own property
    assertTrue(my_str.hasOwnProperty('length'), "str has own prop 'length'");
    assertTrue(my_arr.hasOwnProperty('length'), "arr has own prop 'length'");

    // They can also have numeric own properties
    assertTrue(my_str.hasOwnProperty('1'), "my_str has own prop '1'");
    assertTrue(my_str.hasOwnProperty(1), "my_str has own prop 1");
    assertTrue(my_str.hasOwnProperty(oneOb), "my_str has own prop 1 (oneOb)");
    assertTrue(my_arr.hasOwnProperty('1'), "my_arr has own prop '1'");
    assertTrue(my_arr.hasOwnProperty(1), "my_arr has own prop 1");
    assertTrue(my_arr.hasOwnProperty(oneOb), "my_arr has own prop 1 (oneOb)");

    assertFalse(my_str.hasOwnProperty('6'), "my_str has now own prop '6'");
    assertFalse(my_str.hasOwnProperty(6), "my_str has own prop 6");
    assertFalse(my_arr.hasOwnProperty('6'), "my_arr has own prop '6'");
    assertFalse(my_arr.hasOwnProperty(6), "my_arr has own prop 6");

})();

