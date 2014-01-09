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

//print('redefining callee');

callee = bar;

//print('looping with new callee');

for (var i = 0; i < 5000; ++i)
{
    if (caller() !== 7)
        assert (false, "inlining broken");
}

//print('done looping');

