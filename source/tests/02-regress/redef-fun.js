/*

This test verifies that global function redefinition works properly. It also
exposes potential aliasing issues between the global "this" value and the
global object.

*/

this.foo = function () { return 1; }

assert (foo() === 1);

this.foo = function () { return 2; }

assert (foo() === 2);

