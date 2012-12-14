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
            return (str += 'd');
        }
        catch (e)
        {
            str = 'fail';
        }
        finally
        {
            str += 'e';
        }
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

// foo returns 'abcd'

// str should be 'abcdef'

