var list = null;

for (var i = 0; i < 10; ++i)
    list = { val: i, next: list };

function sumList(l)
{
    for (var i = 0; i < 500000000; ++i)
    {
        var sum = 0;
        for (var node = l; node != null; node = node.next)
            sum += node.val;
    }

    return sum;
}

sumList(list);

