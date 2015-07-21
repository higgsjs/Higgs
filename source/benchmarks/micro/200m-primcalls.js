function $rt_prim(x, y)
{
    for (var i = 0; i < 0; ++i)
    {
    }
}

function test()
{
    for (var i = 0; $ir_lt_i32(i, 200000000); i = $ir_add_i32(i, 1))
    {
        $rt_prim(i, 1);
    }
}

test();

