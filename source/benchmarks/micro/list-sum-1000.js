var lst = null
for (var i = 0; i < 1000; ++i)
    lst = { val: i, next: lst }

function listSum(lst) {
    if (lst == null)
        return 0;
    else
        return lst.val + listSum(lst.next);
}

// 5M
for (var k = 0; k < 5000000; ++k)
    s = listSum(lst);

//print(s)

