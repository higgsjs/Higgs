function test()
{
    var o = {a: 1, b: 2, c: 3, d:4, e:5, f:6}

    // c should not be counted in the sum
    Object.defineProperty(o, 'c', {enumerable:false});

    var sum = 0;
    for (var k in o)
        sum += o[k];

    assert (sum === 18);
}

test();
