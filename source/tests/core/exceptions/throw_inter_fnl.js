var str = '';

function foo()
{
    try
    {
        str += 'b';
        throw 'e';
    }

    finally
    {
        str += 'c';
    }

    str = 'fail';
}

function bar()
{
    try
    {
        str += 'a';
        foo();
        str = 'fail';
    }

    finally
    {
        str += 'd';
    }
}

try
{
    bar();
    str = 'fail';
}

catch (e)
{
    str += e;
}

finally
{
    str += 'f';
}

