int fib(int n)
{
    asm(""); // Don't inline me, bro!

    if (n < 2)
        return n;

    return fib(n-1) + fib(n-2);
}

void main()
{
    fib(40);
}

