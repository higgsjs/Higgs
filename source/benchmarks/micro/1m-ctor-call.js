function Pair(car, cdr)
{
    this.car = car;
    this.cdr = cdr;
}

function test()
{
    for (var i = 0; i < 1000000; ++i)
    {
        var o = new Pair(1, 2);
    }
}

test();

