var str = '';

try
{
    str += 'a';

    throw 'b';

    str += 'x';
}

catch (e)
{
    str += e;
}

finally
{
    str += 'c';
}

