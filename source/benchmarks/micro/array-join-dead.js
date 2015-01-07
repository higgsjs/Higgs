var arr = new Array(50);

for (var i = 0; i < arr.length; ++i)
    arr[i] = 'foo' + i;

for (var i = 0; i < 2000000; ++i)
    arr.join();
