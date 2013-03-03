function foo()
{
}

for (var i = 0; i < 5000; ++i)
{
    o = new foo();

    assert (typeof o === 'object', 'o is not object');
}

function bar()
{
    return 3;
}

for (var i = 0; i < 5000; ++i)
{
    r = new bar();

    assert (r === 3, 'r is not 3');
}

