var lst = null
for (var i = 0; i < 100; ++i)
    lst = { val: i, next: lst }

function listSum(lst) {
    if (lst != null)
        return 0;
    else
        return lst.val + listSum(lst.next);
}

for (var k = 0; k < 10000000; ++k)
    s = listSum(lst);

print(s)

/*
says 30M shape tests vs 1M shape known...

1 read for lst.val, 1 for lst.next

1 for listSum on the global object
no slow calls



Passing an unknown shape to listSum? Yes. Also global obj shape is unknown
when entering listSum

But, should not be testing the lst shape twice. Are we going a global get prop
for null? Can't be.


Dump the machine code for listSum...


*/


