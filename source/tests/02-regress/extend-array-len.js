// Allocate a large array to extend the heap
a = new Array(100000);

gcCount = $ir_get_gc_count();

a = [];
for (var i = 0; i < 100000; ++i)
    a.length = i;

assert ($ir_get_gc_count() < gcCount + 2);




