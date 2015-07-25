function test()
{
    function fun(x, y)
    {
        for (var i = 0; i < 0; ++i)
        {
        }

        return x + y;
    }

    for (var i = 0; $ir_lt_i32(i, 200000000); i = $ir_add_i32(i, 1))
    {
        fun(i, 1);
    }
}

test();

