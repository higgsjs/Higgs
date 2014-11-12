function test(o)
{
    for (k in o)
    {

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

$rt_shrinkHeap(500000);

var gcCount = $ir_get_gc_count();

while ($ir_get_gc_count() < gcCount + 2)
{
    test(o);
}

