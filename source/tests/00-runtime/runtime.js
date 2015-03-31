require('lib/test');

function test_$rt_toObject()
{
    assertThrows(function () {
        $rt_toObject(null);
    });

    assertThrows(function () {
        $rt_toObject(undefined);
    });

    assert($rt_toObject(true) instanceof Boolean);
    assert($rt_toObject(3) instanceof Number);
    assert($rt_toObject('abc') instanceof String);

    var o = {};
    assert($rt_toObject(o) === o);
    var a = [];
    assert($rt_toObject(a) === a);
}

test_$rt_toObject();
