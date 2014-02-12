function cmpEps(a, b)
{
    var error = 10e-10;
    return Math.abs(a -b) < error;
}

assert (cmpEps(parseFloat("3.14"), 3.14 ));
assert (cmpEps(parseFloat("-3.14"), -3.14));
assert (cmpEps(parseFloat("314e-2"), 3.14));
assert (cmpEps(parseFloat("+314e-2"), 3.14));
assert (cmpEps(parseFloat("-314e-2"), -3.14));
assert (cmpEps(parseFloat("0.0314E+2"), 3.14));
assert (cmpEps(parseFloat("3.14more non-digit characters"), 3.14));
assert (cmpEps(parseFloat("0x12343"), 0));
assert (cmpEps(parseFloat(" 0"), 0));
assert (isNaN(parseFloat(" ")));
assert (isNaN(parseFloat()));

