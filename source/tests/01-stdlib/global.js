function cmpEps(a, b)
{
    var error = 10e-10;
    return Math.abs(a -b) < error;
}

function test_parseFloat()
{
    if (!cmpEps(parseFloat("3.14"), 3.14 ))
        return 1;
    if (!cmpEps(parseFloat("-3.14"), -3.14))
        return 2;
    if (!cmpEps(parseFloat("314e-2"), 3.14))
        return 3;
    if (!cmpEps(parseFloat("+314e-2"), 3.14))
        return 4;
    if (!cmpEps(parseFloat("-314e-2"), -3.14))
        return 5;
    if (!cmpEps(parseFloat("0.0314E+2"), 3.14))
        return 6;
    if (!cmpEps(parseFloat("3.14more non-digit characters"), 3.14))
        return 7;
    if (!cmpEps(parseFloat("0x12343"), 0))
        return 8;
    if (!cmpEps(parseFloat(" 0"), 0))
        return 9;
    // if (!isNaN(parseFloat(" ")))
    //     return 10;
    // if (!isNaN(parseFloat()))
    //     return 11;

    return 0;
}

function test()
{
    var r = test_parseFloat();
    if (r != 0)
        return 100 + r;

    return 0;
}

// TODO: convert this test to use assertions &
// exceptions instead of return codes
assert (test() === 0);
