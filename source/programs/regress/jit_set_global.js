function test()
{
    var s = 'a';

    for (var i = 0; i < 5000; ++i)
    {
        var v = s + 1;
        ret = v;
    }
}

//print(test.irString());

var ret;

test();

$ir_gc_collect(0);
