var g;

function with_glob_obj()
{
    g = 3;

    var o = { g:5 };

    with (o)
    {
        g++;
    }

    if (g != 3)
        return 1;

    if (o.g != 6)
        return 2;

    return 0;
}

function with_glob_glob()
{
    g = 3;

    var o = { h:5 };

    with (o)
    {
        g++;
    }

    if (g != 4)
        return 1;

    if (o.h != 5)
        return 2;

    return 0;
}

function with_loc_obj()
{
    var g = 3;

    var o = { g:5 };

    with (o)
    {
        g++;
    }

    if (g != 3)
        return 1;

    if (o.g != 6)
        return 2;

    return 0;
}

function with_loc_loc()
{
    var g = 3;

    var o = { h:5 };

    with (o)
    {
        g++;
    }

    if (g != 4)
        return 1;

    if (o.h != 5)
        return 2;

    return 0;
}

function with_new_var()
{
    var o = {};

    with (o)
    {
        g = 1337;
    }

    if (g != 1337)
        return 1;

    if (o.g != o.undefVar)
        return 2;

    return 0;
}

function test()
{
    var r = with_glob_obj();
    if (r != 0)
        return 100 + r;

    var r = with_glob_glob();
    if (r != 0)
        return 200 + r;

    var r = with_loc_obj();
    if (r != 0)
        return 300 + r;

    var r = with_loc_loc();
    if (r != 0)
        return 400 + r;

    var r = with_new_var();
    if (r != 0)
        return 500 + r;

    return 0;
}

