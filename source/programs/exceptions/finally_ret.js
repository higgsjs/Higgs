function test()
{
    try
    {
        try
        {
            print('inner try');
            return;
        }
        catch (e)
        {
        }
        finally
        {
            print('finally 1');
        }
    }

    catch (e)
    {
    }

    finally
    {
        print('finally 2');
    }

    print('after outer try');
}

