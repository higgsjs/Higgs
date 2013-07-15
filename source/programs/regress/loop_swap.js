function test()
{
    var a1 = 3;
    var a2 = 7;

    for (var i = 0; i < 2; i = $ir_add_i32(i, 1))
    {
        if ($ir_eq_i32(a1, a2))
            throw Error('values corrupted');

        var t = a1;
        a1 = a2;
        a2 = t;

        //if ($ir_eq_i32(a1, a2))
        //    throw Error('swap failed');
    }
}

test();

