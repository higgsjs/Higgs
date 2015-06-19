/*
var list = null;
for (var i = 0; i < 10; ++i)
    if (i % 2 == 0)
        list = { val:false, next:list };
    else
        list = { val:i, next:list };

function listOp(lst) {
  for (var i = 0; i < 500000000; ++i)
    for (var n = lst; n != null; n = n.next)
        if (n.val)
            n.val = n.val + 1;
        else
            n.val = 1;
}

listOp(list);
*/

/*
var list = null;
for (var i = 0; i < 10; ++i)
    if (i % 2 == 0)
        list = { val: 0.5, next: list };
    else
        list = { val: i, next: list };

function listOp(lst) {
  for (var i = 0; i < 500000000; ++i)
    for (var n = lst; n != null; n = n.next)
        if (n.val >= 1)
            n.val = n.val + 1;
        else
            n.val = 1;
}

listOp(list);
*/


