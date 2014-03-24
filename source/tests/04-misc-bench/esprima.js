load('benchmarks/esprima/esprima.js');

//
// Basic test
//

var ast = esprima.parse('var answer = 42');
//print(JSON.stringify(ast));

assert (typeof ast === 'object');
assert (ast.type === 'Program');
assert (ast.body[0].declarations[0].init.value === 42)

//
// Test 1
// - source locations, 
// - function declaration
// - function arguments ******* bugz
// - if/else
// - unary/binary operators
// - conditional operator
// - for loop
// - function calls
// - integer, string, boolean literals
// - object literal ****** bugz
// - array literal
//

var srcData = require('lib/stdio').readFile('benchmarks/esprima/test1.js');
var ast = esprima.parse(srcData, { loc:true });
//print(JSON.stringify(ast));

//
// Self-parse test, esprima parsing esprima
//

var srcData = require('lib/stdio').readFile('benchmarks/esprima/esprima.js');
var ast = esprima.parse(srcData);

