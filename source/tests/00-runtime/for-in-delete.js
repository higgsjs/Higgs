o = {a:1, b:2, c:3};

listed = [];

for (k in o)
{
    delete o.b;

    listed.push(k);
}

assert(listed.length === 2, 'incorrect number of listed properties: ' + listed.length);
assert(listed.indexOf('b') === -1, 'b property listed');

