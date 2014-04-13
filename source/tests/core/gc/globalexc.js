function foo()
{
    return _foo_;
}

function test()
{
    $rt_shrinkHeap(40000);

    var gcCount = $ir_get_gc_count();

    delete _foo_;

    var c = 0;

    while ($ir_get_gc_count() < gcCount + 2)
    {
        try
        {
            foo();
        }
        catch (e)
        {
            c++;
        }
    }

    assert (c > 0);
}

test();
