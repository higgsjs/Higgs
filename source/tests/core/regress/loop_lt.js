for (var i = 0; i < 5000; ++i)
{
    var r = 5 < 10;
}

assert (
    i === 5000,
    'incorrect i value'
);

assert (
    r === true,
    'incorrect r value: ' + r
);

