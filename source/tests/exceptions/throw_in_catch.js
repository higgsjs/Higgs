var str = '';

try
{
    str += 'a';

    try
    {
        str += 'b';
        throw 'c';
    }
    catch (e)
    {
        str += e;
        throw 'e';
    }
    finally
    {
        str += 'd';
    }
}
catch (e)
{
    str += e;
}
finally
{
    str += 'f';
}

str += 'g';

