rnd = require('lib/random');

for (var i = 0; i < 100; ++i)
{
    var int = rnd.int(-1, 5);
    assert (int >= -1 && int < 5);

    var idx = rnd.index(10);
    assert (idx >= 0 && idx < 10);

    var float = rnd.float();
    assert (float >= 0 && float <= 1);

    var float = rnd.float(1, 10);
    assert (float >= 1 && float <= 10);

    var normal = rnd.normal(0, 1);
    assert (typeof normal === 'number');

    var elem = rnd.elem([1, 2, 3]);
    assert (elem === 1 || elem === 2 || elem === 3);

    var arg = rnd.arg('well', 'hello', 'there');
    assert (arg === 'well' || arg === 'hello' || arg === 'there');
}

