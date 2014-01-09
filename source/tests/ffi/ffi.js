// Test higgs FFI functions
var result = {};
var higgs = $ir_load_lib("");
var limit = 100;
var iters = 100;

// testVoidFun
var voidFun = $ir_get_sym(higgs, "testVoidFun");
result = $ir_call_ffi(null, voidFun, "void");
assert ( result == undefined, "Failed testVoidFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, voidFun, "void");
    assert ( result == undefined, "Failed testVoidFun");
}
assert ( result == undefined, "Failed testVoidFun");

// testIntFun
var intFun = $ir_get_sym(higgs, "testIntFun");
result = $ir_call_ffi(null, intFun, "i32");
assert (result == 5, "Failed testIntFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, intFun, "i32");
    assert (result == 5, "Failed testIntFun");
}
assert (result == 5, "Failed testIntFun");

// testDoubleFun
var doubleFun = $ir_get_sym(higgs, "testDoubleFun");
result = $ir_call_ffi(null, doubleFun, "f64");
assert (result == 5.5, "Failed testDoubleFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, doubleFun, "f64");
    assert (result == 5.5, "Failed testDoubleFun");
}
assert (result == 5.5, "Failed testDoubleFun");

// testIntAddFun
var intAddFun = $ir_get_sym(higgs, "testIntAddFun");
result = $ir_call_ffi(null, intAddFun, "i32,i32,i32", 6, 4);
assert (result == 10, "Failed testIntAddFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, intAddFun, "i32,i32,i32", 6, 4);
    assert (result == 10, "Failed testIntAddFun");
}
assert (result == 10, "Failed testIntAddFun");

// testDoubleAddFun
var doubleAddFun = $ir_get_sym(higgs, "testDoubleAddFun");
result = $ir_call_ffi(null, doubleAddFun, "f64,f64,f64", 4.5, 5.5);
assert (result == 10, "Failed testDoubleAddFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, doubleAddFun, "f64,f64,f64", 4.5, 5.5);
    assert (result == 10, "Failed testDoubleAddFun");
}
assert (result == 10, "Failed testDoubleAddFun");

// testIntArgsFun
var intArgsFun = $ir_get_sym(higgs, "testIntArgsFun");
result = $ir_call_ffi(null, intArgsFun, "i32,i32,i32,i32,i32,i32,i32,i32",
                        1, 1, 1, 1, 1, 2, 3);
assert (result == 4, "Failed testIntArgsFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, intArgsFun, "i32,i32,i32,i32,i32,i32,i32,i32",
                            1, 1, 1, 1, 1, 2, 3);
    assert (result == 4, "Failed testIntArgsFun");
}
assert (result == 4, "Failed testIntArgsFun");

// testDoubleArgsFun
var doubleArgsFun = $ir_get_sym(higgs, "testDoubleArgsFun");
result = $ir_call_ffi(null, doubleArgsFun, "f64,f64,f64,f64,f64,f64,f64,f64",
                        1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 3.0);
assert (result == 4.0, "Failed testDoubleArgsFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, doubleArgsFun, "f64,f64,f64,f64,f64,f64,f64,f64",
                            1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 3.0);
    assert (result == 4.0, "Failed testDoubleArgsFun");
}
assert (result == 4.0, "Failed testDoubleArgsFun");

// testPtrFun
var ptrFun = $ir_get_sym(higgs, "testPtrFun");
result = $ir_call_ffi(null, ptrFun, "*");
result = $ir_call_ffi(null, result, "i32,i32,i32", 6, 4);
assert (result == 10, "Failed testPtrFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, ptrFun, "*");
    result = $ir_call_ffi(null, result, "i32,i32,i32", 6, 4);
    assert (result == 10, "Failed testPtrFun");
}
assert (result == 10, "Failed testPtrFun");

// testMixedArgsFun
var mixedArgsFun = $ir_get_sym(higgs, "testMixedArgsFun");
result = $ir_call_ffi(null, mixedArgsFun, "f64,i32,f64,i32,f64,i32,f64,i32",
                        1, 1.0, 1, 1.0, 1, 2.0, 3);
assert (result == 4.0, "Failed testDoubleArgsFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(null, doubleArgsFun, "f64,f64,f64,f64,f64,f64,f64,f64",
                            1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 3.0);
    assert (result == 4.0, "Failed testDoubleArgsFun");
}
assert (result == 4.0, "Failed testDoubleArgsFun");


// Close
$ir_close_lib(higgs);