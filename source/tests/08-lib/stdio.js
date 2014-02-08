stdio = require('lib/stdio');

tmpName = stdio.tmpname();
assert (typeof tmpName === "string" && tmpName.length > 0);

