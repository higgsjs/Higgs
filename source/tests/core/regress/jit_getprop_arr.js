var arr = [0];

for (var i = 0; i < 10000; ++i)
{
    var sne = $rt_getProp(arr, 0);

    if (sne !== 0)
        throw Error('wrong value from getProp');
}

