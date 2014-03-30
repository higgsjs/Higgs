function foo()
{
}

function base64ToString()
{
    var leftbits = 0;
    var leftdata = 0;

    for (var i = 0; i < 5; i++)
    {
        leftbits += 6;

        foo();

        leftdata &= (1 << leftbits);

        if (leftbits >= 255 || leftbits < 0)
            throw Error('invalid result');
    }
}

base64ToString();

