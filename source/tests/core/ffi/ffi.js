// Test higgs FFI functions
var result = {};
var higgs = $ir_load_lib("");
var limit = 100;
var iters = 100;

// testVoidFun
var voidFun = $ir_get_sym(higgs, "testVoidFun");
result = $ir_call_ffi(voidFun, "void");
assert ( result == undefined, "Failed testVoidFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(voidFun, "void");
    assert ( result == undefined, "Failed testVoidFun");
}
assert ( result == undefined, "Failed testVoidFun loop");

// testShortFun
var shortFun = $ir_get_sym(higgs, "testShortFun");
result = $ir_call_ffi(shortFun, "i16");
assert (result == 2, "Failed testShortFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(shortFun, "i16");
    assert (result == 2, "Failed testShortFun");
}
assert (result == 2, "Failed testShortFun");

// testIntFun
var intFun = $ir_get_sym(higgs, "testIntFun");
result = $ir_call_ffi(intFun, "i32");
assert (result == 5, "Failed testIntFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(intFun, "i32");
    assert (result == 5, "Failed testIntFun");
}
assert (result == 5, "Failed testIntFun");

// testDoubleFun
var doubleFun = $ir_get_sym(higgs, "testDoubleFun");
result = $ir_call_ffi(doubleFun, "f64");
assert (result == 5.5, "Failed testDoubleFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(doubleFun, "f64");
    assert (result == 5.5, "Failed testDoubleFun");
}
assert (result == 5.5, "Failed testDoubleFun");

// testIntAddFun
var intAddFun = $ir_get_sym(higgs, "testIntAddFun");
result = $ir_call_ffi(intAddFun, "i32,i32,i32", 6, 4);
assert (result == 10, "Failed testIntAddFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(intAddFun, "i32,i32,i32", 6, 4);
    assert (result == 10, "Failed testIntAddFun");
}
assert (result == 10, "Failed testIntAddFun");

// testDoubleAddFun
var doubleAddFun = $ir_get_sym(higgs, "testDoubleAddFun");
result = $ir_call_ffi(doubleAddFun, "f64,f64,f64", 4.5, 5.5);
assert (result == 10, "Failed testDoubleAddFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(doubleAddFun, "f64,f64,f64", 4.5, 5.5);
    assert (result == 10, "Failed testDoubleAddFun");
}
assert (result == 10, "Failed testDoubleAddFun");

// testIntArgsFun
var intArgsFun = $ir_get_sym(higgs, "testIntArgsFun");
result = $ir_call_ffi(intArgsFun, "i32,i32,i32,i32,i32,i32,i32,i32",
                        1, 1, 1, 1, 1, 2, 3);
assert (result == 4, "Failed testIntArgsFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(intArgsFun, "i32,i32,i32,i32,i32,i32,i32,i32",
                            1, 1, 1, 1, 1, 2, 3);
    assert (result == 4, "Failed testIntArgsFun loop");
}
assert (result == 4, "Failed testIntArgsFun after loop");

// testDoubleArgsFun
var doubleArgsFun = $ir_get_sym(higgs, "testDoubleArgsFun");
result = $ir_call_ffi(doubleArgsFun, "f64,f64,f64,f64,f64,f64,f64,f64",
                        1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 3.0);
assert (result == 4.0, "Failed testDoubleArgsFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(doubleArgsFun, "f64,f64,f64,f64,f64,f64,f64,f64",
                            1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 3.0);
    assert (result == 4.0, "Failed testDoubleArgsFun");
}
assert (result == 4.0, "Failed testDoubleArgsFun");

// testPtrFun
var ptrFun = $ir_get_sym(higgs, "testPtrFun");
result = $ir_call_ffi(ptrFun, "*");
result = $ir_call_ffi(result, "i32,i32,i32", 6, 4);
assert (result == 10, "Failed testPtrFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(ptrFun, "*");
    result = $ir_call_ffi(result, "i32,i32,i32", 6, 4);
    assert (result == 10, "Failed testPtrFun");
}
assert (result == 10, "Failed testPtrFun");

// testPtrArgFun
var ptrArgFun = $ir_get_sym(higgs, "testPtrArgFun");
result = $ir_call_ffi(ptrArgFun, "*,*", intAddFun);
result = $ir_call_ffi(result, "i32,i32,i32", 6, 4);
assert (result == 10, "Failed testPtrArgFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(ptrArgFun, "*,*", intAddFun);
    result = $ir_call_ffi(result, "i32,i32,i32", 6, 4);
    assert (result == 10, "Failed testPtrArgFun");
}
assert (result == 10, "Failed testPtrArgFun");

// testMixedArgsFun
var mixedArgsFun = $ir_get_sym(higgs, "testMixedArgsFun");
result = $ir_call_ffi(mixedArgsFun, "f64,i32,f64,i32,f64,i32,f64,i32",
                        1, 1.0, 1, 1.0, 1, 2.0, 3);
assert (result == 4.0, "Failed testDoubleArgsFun");

limit = iters;
while (limit--)
{
    result = $ir_call_ffi(doubleArgsFun, "f64,f64,f64,f64,f64,f64,f64,f64",
                            1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 3.0);
    assert (result == 4.0, "Failed testDoubleArgsFun");
}
assert (result == 4.0, "Failed testDoubleArgsFun");


// Close
$ir_close_lib(higgs);
