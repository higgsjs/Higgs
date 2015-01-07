function foo(str)
{
    for (var i = 0; i < 7; i++)
    {
        // Floating-point values from Math.floor make it into substring
        var pos = Math.floor(Math.random() * 9);
        str.substring(0, pos);
    }
}

foo('ppppppppp');
foo('qqqqqqqqq');

$ir_gc_collect(0);
