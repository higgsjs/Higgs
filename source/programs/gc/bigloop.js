function loop()
{
    $rt_shrinkHeap(200000);

    var o1 = {x:1};

    for (var i = 0; i < 8000; ++i)
    {
        var o2 = {x:2};

        var i1 = 1;

        var o3 = {x:3};

        var i2 = 2;

        var a1 = [1];

        if (i % 2 === 0)
        {
            var o4 = {x:4};
            var a2 = [];
        }
        else
        {
            var o5 = {x:5};
        }

        i1 += 1;

        var o6 = {};

        assert (o2.x === 2, "invalid o2.x");
        assert (o3.x === 3, "invalid o3.x");
        assert (a1.length === 1, "invalid a1.length");
    }

    assert (o1.x === 1, "invalid o1.x");

    return o1;
}

loop();

