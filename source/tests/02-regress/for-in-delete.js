o = {a:1, b:2, c:3}

n = 0

listed = []

for (k in o)
{
    delete o.b;

    listed.push(k);
}

assert(listed.length === 2 && listed.indexOf('b') === -1);

