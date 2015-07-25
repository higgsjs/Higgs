int fun(x, y)
{
    asm(""); // Don't inline me, bro!

    int i;
    for (i = 0; i < 0; ++i)
    {
    }

    return x + y;
}

void main()
{
    int i;
    for (i = 0; i < 200000000; i++)
    {
        fun(i, 1);
    }
}

