function foo(x)
{
    return x + x + x + x + x + x;
}

x = 5 + 2;
//y = 5.2 + 3.1;
//z = 5.2 + 1;
//z = 1 + 5.2;

for (var i = 0; i < 5000; ++i)
    foo(1);
