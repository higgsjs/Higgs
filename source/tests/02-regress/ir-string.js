function fib(n)
{
    if (n < 2)
        return n;

    return fib(n-1) + fib(n-2);
}

var str = fib.irString();
assert (str.length > 0);

fib(2);

