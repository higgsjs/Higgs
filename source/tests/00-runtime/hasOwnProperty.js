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

