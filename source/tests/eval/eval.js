assert (
    eval("1") === 1,
    "eval of const failed"
);

eval("r = 1");
assert (
    r == 1,
    "eval of global def failed"
);

assert (
    typeof eval("function (x) {}") == "function",
    "eval of function expression failed"
);

assert (
    eval("1;2") === 2,
    "eval of const with two expression failed"
);

var testVal = 100;

assert(
    eval("var i=0;testVal;") === testVal,
    "eval returning global variable"
);
