f = null;

str = '';

try
{
    str += 'a';

    f();

    str = 'fail';
}

catch (e)
{
    str += 'b';
}

str += 'c';

