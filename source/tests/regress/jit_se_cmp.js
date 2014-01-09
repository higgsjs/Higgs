function test()
{
    (null < 0);

    if (null == 0)
        assert(false, 'null == 0 produces true');
}

//print(test.irString());

for (var i = 0; i < 12000; ++i)
    test();

