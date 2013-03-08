function foo(a, b, c)
{
    assert ($argc === 3, 'incorrect argc');
}

for (var i = 0; i < 20000; ++i)
    foo(7, 7, 7);

