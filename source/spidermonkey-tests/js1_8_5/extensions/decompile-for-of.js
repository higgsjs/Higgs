// The decompiler can handle the implicit call to @@iterator in a for-of loop.

var x;
function check(code) {
    var s = "no exception thrown";
    try {
        eval(code);
    } catch (exc) {
        s = exc.message;
    }

    var ITERATOR = JS_HAS_SYMBOLS ? "Symbol.iterator" : "'@@iterator'";
    assertEq(s, `x[${ITERATOR}] is not a function`);
}

x = {};
check("for (var v of x) throw fit;");
check("[...x]");
check("Math.hypot(...x)");

x[std_iterator] = "potato";
check("for (var v of x) throw fit;");

x[std_iterator] = {};
check("for (var v of x) throw fit;");

if (typeof reportCompare === "function")
    reportCompare(0, 0, "ok");
