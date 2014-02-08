function blah()
{
    while (true)
    {
        if (true)
            break;

        while (true)
        {
        }
    }
}

// Generate the IR without calling the function
blah.irString();

