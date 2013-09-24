function foo(limit)
{
    if ($ir_is_i32(limit))
    {
        for (var j = 0; j < limit; ++j)
        {
        }
    }
}

//print(foo.irString());

foo(50000);

