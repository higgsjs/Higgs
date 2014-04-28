function test()
{
    var o = { x: 5 };

    for (var i = 0; $ir_lt_i32(i, 10000000); i = $ir_add_i32(i, 1))
    {
        o.x;
    }
}

//print(test.irString());

test();
