var o = {a:1, b:2, c:3, d:4}

var n = 0;
for (k in o)
{
    if (k === 'a')
        continue;

    n++;
}

assert (n === 3);

var b = Object.create(o);
b.x = 3;

var n = 0;
for (k in b)
{
    if (k === 'x')
        continue;

    n++;
}

assert (n === 4);
