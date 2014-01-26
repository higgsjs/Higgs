var str = '';

function test()
{
    str += 'a';

    for (var i = 0; i < 3; ++i)
    {
        str += 'b';

        try
        {
            str += 'c';

            try
            {
                str += 'd';
                break;
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

