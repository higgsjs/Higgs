function foo()
{
    throw "Error!";
}

function test()
{
    try
    {
        foo();
    }

    catch (e)
    {
        if (e === "Error!")
            return 0;
    }

    return 1;
}

