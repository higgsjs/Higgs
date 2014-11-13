var o = {a:1, b:2, c:3, d:4}

var n = 0;

for (k in o)
{
    if (k === 'a')
        continue;

    n++;
}

assert (n === 3);

