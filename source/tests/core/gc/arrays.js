var ARR_LEN = 5000;

$rt_shrinkHeap(500000);

var gcCount = $ir_get_gc_count();

//println('num arrs: ' + numArrs);

while ($ir_get_gc_count() < gcCount + 2)
{
    //println('allocating');

    var arr = [];
    arr.length = ARR_LEN;

    //println('allocated');
}

