var str = '';

function test()
{
    str += 'a';

    for (var i = 0; i < 2; ++i)
    {
        str += 'b';

        try
        {
            str += 'c';

            try
            {
                str += 'd';
                continue;
            }
            catch (e)
            {
                str = 'fail';
            }
            finally
            {
                str += 'e';
            }

            str = 'fail';
        }

        catch (e)
        {
            str = 'fail';
        }

        finally
        {
            str += 'f';
        }

        str = 'fail';
    }

    str += 'g';
}

