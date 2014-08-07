function test(arr)
{
    for (var i = 0; i < arr.length; ++i)
    {
        arr[i];
    }
}

arr = [];
arr.length = 10000;
for (var i = 0; i < arr.length; ++i)
    arr[i] = i;

for (var i = 0; i < 10000; ++i)
    test(arr);

