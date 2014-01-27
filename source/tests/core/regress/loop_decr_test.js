function foo()
{
}

function test()
{
    var arr = [48, 48, 56, 48];
    var size = 4;
    var value = 0;
    var idx = 0;

    // Problem with tmp alloc for size getting corrupted
    // by return value of foo()
    // Thanks to zimbabao for finding this problem
    while (size-- > 0)
    {
        foo();
        value += arr[idx];
        idx++;
    }

    //print(value);
    //print(size)
    //print(idx);

    return value;
}

var r = test();
assert (
    r === 200,
    "invalid sum: " + r + ", expected 200"
);

