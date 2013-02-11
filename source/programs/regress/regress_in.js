C = function () {};

a = new C();
b = new C();

a.x = 0;
a.y = 1;
b.x = 0;

if ('y' in b)
    throw Error('in operator is broken');

