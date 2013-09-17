Higgs
=====

Higgs JavaScript Virtual Machine

An interpreter and JIT compiler for JavaScript targetting x86-64 platforms.

**Requirements:**

- D compiler (DMD recommended)
- POSIX compliant OS (Linux, Unix, MacOS X)
- x86 64-bit CPU (if using the JIT compiler)
- Python 2.7 (if regenerating object layouts or instruction encodings)

**Quickstart:**

*Get the source:*
 
`git clone https://github.com/maximecb/Higgs.git && cd Higgs/source`

*Compile a binary:*
 
`make all`
generates a binary `higgs` in the source directory.

*Install (optional):*
 
`make install` 
copies the `higgs` binary to `/usr/bin` and the runtime files to `/etc/higgs`.

*Cleanup:*

`make clean`
will remove any binaries in the source directory.

*You may wish to run the unit tests:*
 
`make test`
generates a binary `test-higgs` and tests its proper functioning.

For further info, see the `makefile`.

**Usage:**

`higgs` will start Higgs and give you a REPL (read-eval-print loop).

To execute one or more files, pass them to `higgs`:

`higgs file1.js file2.js`

The `--e` option accepts a string to execute:

`higgs --e "var x = 4; x = x + 5; print(x)"`

The `--repl` option will start a REPL after evaluating a string and/or files:

`higgs --repl file1.js` will evaluate `file1.js` and then start a REPL.

`higgs file1.js` will evaluate `file1.js` and then exit.

The `--jit_disable` option will disable the JIT compiler and rely solely on the interpreter.

The `--jit_dumpasm` option will dump the assembler code generated by the JIT to the console.

**Notes:**
 - You may wish to use `rlwrap` for a better REPL experience.

Libraries
=====

**console:**

Higgs has a library to to allow you to pretty-print objects/data to stdout.

*Importing:*

```JS
// To us use the console functions you must import the console module:
var console = require('lib/console');
```

*Functions:*

```JS
// To pretty-print
console.log("foo");
console.log({ foo: "bar"});
// If you pass multiple arguments, they will be printed on the same line separated by tabs
console.log(1, 2, 3);
```
**stdlib:**

The stdlib library provides wrappers for common functions in the C stdlib.

*Importing:*

```JS
// First import the stdlib module:
var stdlib = require('lib/stdlib');
```

The following functions are provided:

```JS
// Allocate memory with malloc
var mem = stdlib.malloc(32);

// Resize/reallocate memory
mem = stdlib.realloc(64);

// Free memory
c.free(mem);

// Get an environmental variable
var name = stdlib.getenv("LOGNAME");

// Execute a command
stdlib.system("ls -a");

// There is also popen, which will return a file-like object
var output = stdlib.popen("ls -a", "r");
print(output.read());

// Exit with return code
stdlib.exit(0);
```

**csv:**

The csv library provides basic support for manipulating comma-separated value (CSV) files.

*Importing:*

```JS
// First import the csv module:
var csv = require('lib/csv');
```

*Writing CSV files:*

```JS
// Create a new CSV spreadsheet object
sheet = new csv.CSV();

// Data can be added to the spread sheet row by row
sheet.addRow(['name', 'age', 'sex']);
sheet.addRow(['Alice', '19', 'F']);
sheet.addRow(['Bob', '22', 'M']);
sheet.addRow(['Kirby', '1', 'N/A']);

// You can set individual cell values directly using the setCell method
// This will change Alice's name to Anna:
sheet.setCell(1, 0, 'Anna');

// Rows can also be directly addressed with the setRow method
// This replaces the last row:
sheet.setRow(3, ['John', '35', 'M']);

// Write the data to a CSV file
sheet.writeFile('data.csv');

```

*Reading CSV files:*

```JS
// Read a spreadsheet from a CSV file
sheet = csv.readFile('data.csv');

// Prints 4
print(sheet.getNumRows());

// Prints 'John'
print(sheet.getCell(3, 0));
```


**stdio:**

Higgs has a library to provide common I/O functionality. It is a wrapper around the C I/O functions found in [the stdio library](http://www.cplusplus.com/reference/cstdio/).

*Importing:*
```JS
// To use the I/O functions you must first import the stdio module:
var io = require('lib/stdio');
```

*File operations:*
```JS

// The stdio module provides some common file operations

// Delete a file, returns true if successful or false otherwise
io.remove('test.txt');

// Rename a file, returns true if successful or false otherwise
io.rename('foo.txt', 'bar.txt');

// Get a temporary file, returns a File object on success or throws error on failure
var myfile = io.tmpfile();

// Get a unique name, returns a string containing the name on success or throws error on failure
var name = io.tmpname();

// Open a file, returns a File object on success or throws error on failure
// open foo.txt for reading
var foo = io.fopen("foo.txt", "r");
```

*File objects:*
```JS
// Some functions like fopen return an instance of File:
var myfile = io.fopen("foo.txt", "w+");

// File objects provide methods for reading, writing, etc

// Get a character, will return "" for EOF
var c = myfile.getc();

// Read a line, including newline
var line = myfile.readLine();

// You can also specify a maximum length to read
// the next read will get the remainder of the line (if any)
var first_ten_chars = myfile.readLine(10);
var remainder = myfile.readLine();

// Read the next x chars
var ten_chars = myfile.read(10);

// Read the entire file
var test = myfile.read();

// There are functions for reading binary data:
var answer = file.readUint8();
var steps = file.readInt8();
var spartans = file.readUint16();
var years = file.readInt16();
var jnumber = file.readUint32();
var population = file.readFloat64();

// Write a char to the file, returns true if successful or false otherwise
myfile.putc("H");

// Write a string to the file, returns true if successful or false otherwise
myfile.write("Hello World.");

// There are functions for writing binary data:
file.writeUint8(42);
file.writeInt8(8);
file.writeUint16(300);
file.writeInt16(100);
file.writeUint32(8675309);
file.writeFloat64(1.536);

// Flush a file, returns true if successful or false otherwise
myfile.flush();

// Returns true if the next character is EOF
myfile.EOF();

// Returns the current position in the file
myfile.tell();

// Rewind to beginning of file
myfile.rewind();

// Seek to 10th character
myfile.seek(10);

// Seek 2 characters ahead
myfile.seek(2, io.SEEK_CUR);

// When finished with a file close() will close it and free some resources
myfile.close();
```
*The stdin/stdout/stderr streams:*
```JS
// The stdio module provides File objects for stdin/stdout/stderr

// Get a char from stdin
io.stdin.getc();

// Write to stdout
io.stdout.write("Hello!");

// Write to stderr
io.stderr.write("Hello!");
```


**Notes:**
 - There is currently no support in stdio for wchar functions.
 - Functions in the stdio library must be called in the context of the stdio module.
`var fopen = io.fopen` will not work.

