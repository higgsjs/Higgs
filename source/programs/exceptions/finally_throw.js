var str = '';

function test()
{
    str += 'a';

    try
    {
        str += 'b';

        try
        {
            str += 'c';
            throw 'd';
        }
        catch (e)
        {
            str += e;

            try 
            {
                str += 'e';
                throw 'f';
            }
            catch (e)
            {
                str += e;
                throw 'i';
            }
            finally
            {
                str += 'g';
            }

            str = 'fail';
        }
        finally
        {
            str += 'h';
        }

        str = 'fail';
    }

    catch (e)
    {
        str += e;
    }

    finally
    {
        str += 'j';
    }

    str += 'k';
}

