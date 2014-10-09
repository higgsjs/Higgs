var g = 0;
function f() { g++ };
function x() {} [f(), f()]
assert (g === 2);
assert (typeof x === 'function', 'function not defined');

delete foo;
eval('function foo() {}');
assert (typeof foo === 'function')

