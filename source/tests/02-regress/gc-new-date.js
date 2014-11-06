$rt_shrinkHeap(20007);

var gcCount = $ir_get_gc_count();

while ($ir_get_gc_count() < gcCount + 4)
{
    d = new Date();
}

