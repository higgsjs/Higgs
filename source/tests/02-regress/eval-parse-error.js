var b = 0;

try
{
    eval(",");
    b++;
}

catch (e)
{
    b++;
}

assert (b === 1, "eval did not throw error");

