function test()
{
    var sum = 0;

    for (var i = 0; i < 100000000; ++i)
    {
        sum += Math.sin(1.5 * i);
    }

    return sum;
}

test();
