function test_ctor()
{
    if (Boolean(true) !== true)
        return 1;

    if (Boolean(5) !== true)
        return 2;

    if (Boolean('a') !== true)
        return 3;

    if (Boolean({}) !== true)
        return 4;

    if (Boolean([]) !== true)
        return 5;

    if (Boolean(false) !== false)
        return 6;

    if (Boolean(null) !== false)
        return 7;

    if (Boolean(undefined) !== false)
        return 8;

    if (Boolean(0) !== false)
        return 9;

    if (Boolean('') !== false)
        return 10;

    if (typeof (new Boolean(true)) !== 'object')
        return 11;

    if (!(new Boolean(false)))
        return 12;

    return 0;
}

function test_toString()
{
    var b = true;
    var bo = new Boolean(true);
    var s = 'true';

    if (b.toString() !== s)
        return 1;

    if (bo.toString() !== s)
        return 2;

    return 0;
}

function test_valueOf()
{
    var b = true;
    var bo = new Boolean(true);

    if (b.valueOf() !== b)
        return 1;

    if (bo.valueOf() !== b)
        return 2;

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

// TODO: convert this test to use assertions &
// exceptions instead of return codes 
assert (test() === 0);

