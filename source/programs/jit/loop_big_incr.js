function foo()
{
    // Loop to 2B
    for (var i = 0; i < 2000000000; ++i)
    {
    }

    return i;
}

assert (
    foo() === 2000000000,
    'final loop increment value incorrect'
);

