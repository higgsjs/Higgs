function foo()
{
    throw TypeError('foo' + 'bar');
}

try
{
    foo()
}
catch (e)
{
    var str = String(e);

    assert (str.indexOf('TypeError') != -1);
    assert (str.indexOf('foobar') != -1);
}

