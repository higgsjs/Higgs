/* The Great Computer Language Shootout
   http://shootout.alioth.debian.org/
   contributed by Isaac Gouy */

function TreeNode(left,right,item){
   this.left = left;
   this.right = right;
   this.item = item;
}

TreeNode.prototype.itemCheck = function(){
   if (this.left==null) return this.item;
   else return this.item + this.left.itemCheck() - this.right.itemCheck();
}

function bottomUpTree(item,depth){
   if (depth>0){
      return new TreeNode(
          bottomUpTree(2*item-1, depth-1)
         ,bottomUpTree(2*item, depth-1)
         ,item
      );
   }
   else {
      return new TreeNode(null,null,item);
   }
}

function benchmarkFun()
{
    for ( var n = 4; n <= 7; n += 1 ) {
        var minDepth = 4;
        var maxDepth = Math.max(minDepth + 2, n);
        var stretchDepth = maxDepth + 1;
        
        var check = bottomUpTree(0,stretchDepth).itemCheck();
        
        var longLivedTree = bottomUpTree(0,maxDepth);
        for (var depth=minDepth; depth<=maxDepth; depth+=2){
            var iterations = 1 << (maxDepth - depth + minDepth);

            check = 0;
            for (var i=1; i<=iterations; i++){
                check += bottomUpTree(i,depth).itemCheck();
                check += bottomUpTree(-i,depth).itemCheck();
            }
        }

        ret = longLivedTree.itemCheck();
    }
}


// By performing warmup runs, we abstract out compilation time, standard
// library and runtime initialization time, as well as part of the benchmark
// initialization time (global function definitions). We cannot remove garbage
// collection time from the final timing run, however.

function timeFun(fun, numItrs)
{
    var startTime = (new Date()).getTime();

    for (var i = 0; i < numItrs; ++i)
        fun();

    var endTime = (new Date()).getTime();

    return endTime - startTime;
}

if (typeof benchmarkFun != 'function')
    throw Error('benchmarkFun not defined!');

// Benchmarking time (to be measured)
var benchTime = 0.0;

// Number of timing iterations, minimum 10
var numItrs = 10;

// Warmup iterations
timeFun(benchmarkFun, 1);

// Compute the number of iterations needed to get
// at least 1000ms of execution time
while (timeFun(benchmarkFun, numItrs) < 1000)
    numItrs *= 2;

// Timing runs, several iterations
benchTime = timeFun(benchmarkFun, numItrs) / numItrs;

print('num itrs:', numItrs);
print('exec time (ms):', benchTime);

