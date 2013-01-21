var FREE_SIZE = 500000;

var ARR_LEN = 20000;

var numArrs = 2 * $ir_div_i32(FREE_SIZE, 9 * ARR_LEN);

$rt_shrinkHeap(FREE_SIZE);

println('num arrs: ' + numArrs);

for (var i = 0; i < numArrs; ++i)
{
    println('allocating');

    var arr = [];
    arr.length = ARR_LEN;

    println('allocated');
}

