function bar()
{
}

function foo()
{
    bar();
}

for (var i = 0; i < 5000; ++i)
{
    foo();
}

bar = 3;

try
{
    foo();
}
catch (e)
{
}

bar = {};

try
{
    foo();
}
catch (e)
{
}

