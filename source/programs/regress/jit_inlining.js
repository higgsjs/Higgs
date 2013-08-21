function sub()
{
    return 7;
}

function theCat(str1, str2)
{
    sub();

    for (var i = 0; $ir_lt_i32(i, 6); i = $ir_add_i32(i, 1))
    {
    }

    return i;
}

function theAdd(x, y)
{
    return theCat(x, y);
}

for (var i = 0; i < 5000; ++i)
{
    if (theAdd(0, 0) !== 6)
        assert (false, "inlining broken");
}

