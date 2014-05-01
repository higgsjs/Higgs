function ctor()
{
    this.a = 777;
}

function test()
{
    $rt_shrinkHeap(20007);

    var gcCount = $ir_get_gc_count();

    var s = 0;

    while ($ir_get_gc_count() < gcCount + 4)
    {
        var o = new ctor();
        s += o.a;
    }

    return s;
}

test();

