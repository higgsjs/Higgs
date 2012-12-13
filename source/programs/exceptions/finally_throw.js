function foo()
{
    try
    {
        try
        {
            throw 'hi';
        }
        catch (e)
        {
            print('catch 1');
        }
        finally
        {
            print('finally 1');
        }
    }

    catch (e)
    {
        print('catch 2');
    }

    finally
    {
        print('finally 2');
    }
}

