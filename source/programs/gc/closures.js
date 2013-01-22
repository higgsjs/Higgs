function closTest(freeSpace)
{
    $rt_shrinkHeap(freeSpace);

    var gcCount = $ir_get_gc_count();

    var a = 0;

    while ($ir_get_gc_count() < gcCount + 1)
    {
        clos = function () { a++; }

        clos();
    }

    if (typeof a !== 'number')
        return 1;

    if (!(a > 0))
        return 2;

    return 0;
}

function test()
{
    if (closTest(25000) !== 0)
        return 1;

    if (closTest(17000) !== 0)
        return 2;

    if (closTest(15000) !== 0)
        return 3;

    return 0;
}

