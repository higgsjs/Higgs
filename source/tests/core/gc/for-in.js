function test(o)
{
    for (k in o)
    {
        if (n % 3 === 0)
            $ir_gc_collect(0);
    }
}

var n = 0;

var o = {
    a: 1,
    b: 2,
    c: 3,
    d: 4,
    e: 5,
    f: 6
};

for (var gcCount = $ir_get_gc_count(); $ir_get_gc_count() < gcCount + 4;)
{
    test(o);
}

