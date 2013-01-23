function bar(o1, o2)
{
    $ir_gc_collect(0);

    return o1.v + o2.v;
}

function foo()
{
    var a = {v:1};
    var b = {v:2};
    var c = {v:3};

    var r = bar.apply(null, [a, b]);

    return r + c.v;
}

function test()
{
    var r = foo();
    if (r !== 6)
        return 1;

    return 0;
}

