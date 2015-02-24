function bif()
{
    return { x: 777 };
}

function test()
{
    var o = bif();

    $ir_gc_collect(0);

    assert (typeof o === 'object');
    assert (o.x === 777);
}

