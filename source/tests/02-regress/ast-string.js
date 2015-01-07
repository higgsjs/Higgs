function fib(n)
{
    if (n < 2)
        return n;

    return fib(n-1) + fib(n-2);
}

var str = fib.toString();
assert (str.length > 0);
assert (str.indexOf('fib') !== 0);
assert (str.indexOf('n') !== 0);

fib(2);

var str = fib.toString();
assert (str.length > 0);

