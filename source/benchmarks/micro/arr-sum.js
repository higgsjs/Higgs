function arrSum(arr)
{
    var sum = 0;

    for (var i = 0; i < arr.length; ++i)
        sum += arr[i];

    return sum;
}

var arr = new Array(1000000);

for (var i = 0; i < arr.length; ++i)
{
    arr[i] = 1;
}

for (var i = 0; i < 100; ++i)
{
    arrSum(arr);
}

