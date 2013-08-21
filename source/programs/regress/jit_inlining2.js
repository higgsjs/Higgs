function callee()
{
    return 0;
}

function bar()
{
    return 7;
}

function caller()
{
    return callee();
}

for (var i = 0; i < 5000; ++i)
{
    caller();
}

callee = bar;

for (var i = 0; i < 5000; ++i)
{
    if (caller() !== 7)
        assert (false, "inlining broken");
}

