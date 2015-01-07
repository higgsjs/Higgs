function test(o)
{
    for (var i = 0; i < 1000000; ++i)
    {
        // Note: k is a global variable
        for (k in o)
        {

        }
    }
}

var o = {
    a: 1,
    b: 2,
    c: 3,
    d: 4,
    e: 5,
    f: 6
};

test(o);
