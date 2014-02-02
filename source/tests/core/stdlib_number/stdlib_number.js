function test_ctor()
{
    if (Number(1) !== 1)
        return 1;

    if (Number('2') !== 2)
        return 2;

    if (typeof (new Number(1)) !== 'object')
        return 3;

    return 0;
}

function test_toString()
{
    var n = 1337;
    var no = new Number(1337);
    var s = '1337';

    if (n.toString() !== s)
        return 1;

    if (no.toString() !== s)
        return 2;

    if (no.toString(16) !== '539')
        return 3;

    if (no.toString(8) !== '2471')
        return 4;

    if (no.toString(2) !== '10100111001')
        return 5;

    if (no.toString('2') !== '10100111001')
        return 6;

    if (no.toString('010') !== s)
        return 7;

    var f = 12.234;
    if (f.toString() !== '12.234')
        return 8;

    //TODO: Fix toString for floats to handle redix
    // if (f.toString(16) !== 'c.3be76c8b43958')
    //     return 8;

    // if (f.toString(8) !== '14.16763554426416254')
    //     return 8;

    return 0;
}

function test_valueOf()
{
    var n = 1337;
    var no = new Number(1337);

    if (n.valueOf() !== n)
        return 1;

    if (no.valueOf() !== n)
        return 2;

    return 0;
}

function test_toFixed()
{
    if ((200).toFixed() !== "200")
        return 1;

    if ((0.5).toFixed() !== "1")
        return 2;

    if ((2.45).toFixed(1) !== "2.5")
        return 3;

    if ((53.6236854143).toFixed(9) != "53.623685414")
        return 4;

    if ((-2.45).toFixed(1) !== "-2.5")
        return 6;

    if ((0).toFixed(2) !== "0.00")
        return 7;

    if ((1).toFixed(5) !== "1.00000")
        return 8;

    if ((123456789).toFixed({}) !== "123456789")
        return 9;

    if ((1E+22).toFixed(2) !== "1E+22")
        return 10;

    // Note: technically wrong answers, but consistent with other engines
    if ((12345678901234567).toFixed(2) !== "12345678901234568.00")
        return 11;

    if ((123456789012345678).toFixed(2) !== "123456789012345680.00")
        return 12;

    if ((123456789012345678).toFixed(20) !== "123456789012345680.00000000000000000000")
        return 13;

    return 0;
}

function test()
{
    var r = test_ctor();
    if (r !== 0)
        return 100 + r;

    var r = test_toString();
    if (r !== 0)
        return 200 + r;

    var r = test_valueOf();
    if (r !== 0)
        return 300 + r;

    r = test_toFixed();
    if (r !== 0)
        return 400 + r;

    return 0;
}
