function foo()
{
    var s = 0;

    for (var i = 0; i < arguments.length; ++i)
         s += arguments[i].v;

    return s;
}

function test()
{
    var o = {x:3};

    var r = foo({v:1}, {v:5}, {v:7}, {v:8}, {v:9}, {v:10}, {v:11});

    r += o.x;

    if (r !== 54)
        return 1;

    return 0;
}

