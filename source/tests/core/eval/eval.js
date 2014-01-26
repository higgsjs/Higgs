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

