stdlib = require('lib/stdlib');

mem = stdlib.malloc(32); 
assert (typeof mem === 'rawptr' && mem !== $nullptr);
stdlib.free(mem);

