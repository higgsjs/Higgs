function test()
{
    function foo(o)
    {
        return o.x;
    }

    var o = { x:1 };

    for (var i = 0; i < 1000000; ++i)
    {
        o.x = 1;

        foo(o);
    }
}

test();
