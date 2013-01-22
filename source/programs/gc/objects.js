function test()
{
    $rt_shrinkHeap(40000);

    var gcCount = $ir_get_gc_count();

    var p = { k: 1 };

    while ($ir_get_gc_count() < gcCount + 2)
    {
        var o = { v: 2 };
    }

    if (p.k !== 1)
        return 1;

    if (o.v !== 2)
        return 2;

    return 0;
}

