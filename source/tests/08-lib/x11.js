try
{
    var x11 = require('lib/x11');

    assert (typeof x11.XOpenDisplay === 'function');
}

catch (e)
{
    if (!(e instanceof ReferenceError))
        throw e;

    print('X11 library not installed');
}

