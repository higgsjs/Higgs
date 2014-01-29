var str = '';

try
{
    str += 'a';

    try
    {
        str += 'b';
    }
    finally
    {
        str += 'c';
        throw 'd';
    }
}
catch (e)
{
    str += e;
}
finally
{
    str += 'e';
}

str += 'f';

