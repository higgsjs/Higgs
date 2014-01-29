function Ctor()
{
    var o = {};

    o.x = 1;

    return o;
}

for (var i = 0; i < 5000; ++i)
{
    var o = new Ctor();

    if (typeof o !== 'object')
        print('not object');
}

