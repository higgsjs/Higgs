function foo(VM1, V0, V1, VN)
{
    for (var i = 0; i < 5000; i++)
    {
        assert (  VM1 < V0      , '-1 < 0');
        assert (!(V0 < VM1)     , '0 < -1');
        assert (!(VM1 < VM1)    , '-1 < -1');
        assert (!(VN < V0)      , 'NaN < 0');
        assert (!(VN < VM1)     , 'NaN < -1');
        assert (!(VN < VN)      , 'NaN < NaN');

        assert (  VM1 <= V0     , '-1 <= 0');
        assert (  VM1 <= VM1    , '-1 <= -1');
        assert (!(VN <= V0)     , 'NaN <= 0');
        assert (!(VN <= VM1)    , 'NaN <= -1');
        assert (!(VN <= VN)     , 'NaN <= NaN');

        assert (  V1 > V0       , '1 > 0');
        assert (  V0 > VM1      , '0 > -1');
        assert (  V1 > VM1      , '1 > -1');
        assert (!(VM1 > V0)     , '-1 > 0');
        assert (!(VM1 > VM1)    , '-1 > -1');
        assert (!(V0 > V0)      , '0 > 0');
        assert (!(VN > V0)      , 'NaN > 0');
        assert (!(VN > VN)      , 'NaN > NaN');

        assert (  VM1 >= VM1    , '-1 >= -1');
        assert (  V0 >= V0      , '0 >= 0');
        assert (  V1 >= V1      , '1 >= 1');
        assert (  V1 >= V0      , '1 >= 0');
        assert (  V0 >= VM1     , '0 >= -1');
        assert (  V1 >= VM1     , '1 >= -1');
        assert (  V1 >= V0      , '1 >= 0');
        assert (!(VM1 >= V0)    , '-1 >= 0');
        assert (!(VN >= V0)     , 'NaN >= 0');
        assert (!(VN >= VN)     , 'NaN >= NaN');

        assert (  V0 === V0     , 'V0 === V0');
        assert (  V1 === V1     , 'V1 === V1');
        assert (!(V1 === V0)    , 'V1 === V0');
        assert (!(VN === VN)    ,'NaN === NaN');

        assert (  VN !== V1     , 'NaN !== 1');
        assert (  VN !== VN     , 'NaN !== NaN');
        assert (  V1 !== V0     , '1 !== 0');
        assert (!(V1 !== V1)    , '1 !== 1');
    }
}

foo(-1.0, 0.0, 1.0, NaN);

function assert(b, t)
{
    if (!b)
        print('error:' + t);
}

