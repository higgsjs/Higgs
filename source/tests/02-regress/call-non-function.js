function verifyErr(context)
{
    assert (
        exc !== undefined
    );
    assert (
        exc instanceof TypeError,
        context + ': exception is not a TypeError (typeof is ' + typeof exc + ')'
    );
    assert (
        exc.toString().indexOf('foo') !== -1,
        context + ': error string does not specify function name'
    );
}

// === Global call in try block ===

try
{
    var foo = undefined;
    foo();
}
catch (e)
{
    var exc = e;
}

verifyErr('global call in try block');

// === Method call in try block ===

try
{
    var o = { foo: undefined };
    o.foo();
}
catch (e)
{
    var exc = e;
}
verifyErr('method call in try block');

// === Global call in function ===

var foo = undefined;
function throws()
{
    foo();
}

try
{
    throws();
}
catch (e)
{
    var exc = e;
}

verifyErr('global call in function');

// === Method call in function ===

function throws()
{
    var o = { foo: undefined };
    o.foo();
}

try
{
    throws();
}
catch (e)
{
    var exc = e;
}

verifyErr('method call in function');

