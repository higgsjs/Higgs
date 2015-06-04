var list = null;
for (var i = 0; i < 10; ++i)
    if (i % 2 == 0)
        list = { val:i, next:list };
    else
        list = { val:i, flag:true, next:list};

function sumList(lst) {
  for (var i = 0; i < 500000000; ++i) {
    var sum = 0;
    for (var n = lst; n != null; n = n.next)
      if (n.flag)
        sum += n.val * 10;
      else
        sum += n.val;
    }

    return sum;
}

sumList(list);

