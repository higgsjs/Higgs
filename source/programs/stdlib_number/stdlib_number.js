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

    return 0;
}

