stdlib = require('lib/stdlib');

// malloc & free
mem = stdlib.malloc(32); 
assert (typeof mem === 'rawptr' && mem !== $nullptr);
stdlib.free(mem);

// popen
var output = stdlib.popen("ls", "r");
var str = output.read();
assert (typeof str === 'string');

