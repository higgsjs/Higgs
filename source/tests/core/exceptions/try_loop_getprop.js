str = 'a';

o = { a:5 };

try
{
    str += 'b';

    for (var i = 0; i < 20000; ++i)
    {
        if (i === 19000)
            o = null;

        p = o.a;
    }

    str += 'k';
}

catch (e)
{
    str += 'c';
}

str += 'd';

