function fib(n)
{
    if (n < 2)
        return n;

    return fib(n-1) + fib(n-2);
}

fib(2);

var str = fib.asmString();
assert (str.length > 0);

fib(2);

