o = { toString: function () { return null; } };

str = 'foo' + o;

if (str !== 'foonull')
    throw Error('toString is broken');

