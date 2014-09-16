function test()
{
    // Loop to 2B
    // Note: i is a global variable
    for (i = 0; i < 2000000000; ++i)
    {
    }
}

test();

/*
assert (
    i === 2000000000,
    'final loop increment value incorrect'
);
*/
