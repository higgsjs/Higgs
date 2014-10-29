function foo(arg)
{
    return arg;
}

function test()
{
    for (var i = 0; i < 1000000; ++i)
    {
        foo.apply(i);
    }
}

test();

