function test(arr)
{
    for (var i = 0; i < arr.length; ++i)
    {
        arr[i];
    }
}

arr = [];
arr.length = 40000;
for (var i = 0; i < arr.length; ++i)
    arr[i] = i;

for (var i = 0; i < 40000; ++i)
    test(arr);

