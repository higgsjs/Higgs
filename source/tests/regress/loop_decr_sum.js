function foobar(x) 
{
    var n = 0;
    for (var i = 1000; i > 123; i--)
        n = n + i;
    return n;
}

var sum = foobar();

assert (
    sum === 492874,
    'invalid sum'
);

