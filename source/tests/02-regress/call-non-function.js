try
{
    var foo = undefined;
    foo();
}
catch (e)
{
    var exc = e;
}

assert (
    exc !== undefined
);
assert (
    exc instanceof TypeError,
    'exception is not a TypeError (typeof is ' + typeof exc + ')'
);
assert (
    exc.toString().indexOf('foo') !== -1,
    'error string does not specify function name for function call'
);

try
{
    var o = { bar: undefined };
    o.bar();
}
catch (e)
{
    var exc = e;
}

assert (
    exc !== undefined
);
assert (
    exc instanceof TypeError,
    'exception is not a TypeError (typeof is ' + typeof exc + ')'
);
assert (
    exc.toString().indexOf('bar') !== -1,
    'error string does not specify function name for method call'
);

