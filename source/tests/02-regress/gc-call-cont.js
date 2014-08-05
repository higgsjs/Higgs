gcCount = $ir_get_gc_count();

longStr = 'a'
catStr = 'b';

while ($ir_get_gc_count() < gcCount + 10)
{
    $rt_shrinkHeap(10000);

    for (i = 0; i < 100; ++i)
        eval(' o = {}; o.' + longStr + ' = "' + longStr + '"');

    $rt_shrinkHeap(2000000);

    longStr += catStr;
    catStr += 'b';

    //print(longStr.length);
}

