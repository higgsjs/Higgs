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

var stdio = require('lib/stdio');
var srcFile = stdio.fopen('benchmarks/esprima/test1.js', 'r');
var srcData = srcFile.read();
srcFile.close();
var ast = esprima.parse(srcFile, { loc:true });
//print(JSON.stringify(ast));

//
// Self-parse test, esprima parsing esprima
//

var stdio = require('lib/stdio');
var srcFile = stdio.fopen('benchmarks/esprima/esprima.js', 'r');
var srcData = srcFile.read();
srcFile.close();
var ast = esprima.parse(srcFile);

