var stdio = require('lib/stdio');
var test_str = "This is only a test.";

// tmpname
var tmpName = stdio.tmpname();
assert (typeof tmpName === "string" && tmpName.length > 0);

// open/write
var myFile = stdio.fopen(tmpName, "w+");
myFile.write(test_str);

assert(myFile.read() === test_str, "read/write ok");

myFile.close();

// readFile()
assert (stdio.readFile(tmpName) === test_str, "readFile ok");
