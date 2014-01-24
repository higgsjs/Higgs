function bif(v1, v2, v3, v4, v5, v6, v7)
{
    v1.x += 1;

    $ir_gc_collect(0);

    v1.y.v += v7.v;

    v1.sum = v2 + v3 + v4 + v5.length;

    return v1;
}

function bar(v1, v2, v3, v4, v5, v6, v7)
{
    return bif(v1, v2, v3, v4, v5, v6, v7);
}

function foo(v1)
{
    var ofoo = { v: 2 };

    $ir_gc_collect(0);

    return bar(v1, 1, 2, 3, 'fooo', 5, ofoo);
}

function test()
{
    var o = { x:1, y: { v:3 } };

    var r = foo(o);

    if (o !== r)
        return 1;

    if (typeof o !== 'object')
        return 2;

    if (r.x !== 2)
        return 3;

    if (r.y.v !== 5)
        return 4;

    if (r.sum !== 10)
        return 5;

    return 0;
}

