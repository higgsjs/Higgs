function test()
{
    for (var i = 0; i < 3; ++i)
    {
        try
        {
            try
            {
                print('inner try');
                continue;
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
    }
}

