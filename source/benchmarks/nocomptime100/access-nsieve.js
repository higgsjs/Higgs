// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// modified by Isaac Gouy

function pad(number,width){
   var s = number.toString();
   var prefixWidth = width - s.length;
   if (prefixWidth>0){
      for (var i=1; i<=prefixWidth; i++) s = " " + s;
   }
   return s;
}

function nsieve(m, isPrime){
   var i, k, count;

   for (i=2; i<=m; i++) { isPrime[i] = true; }
   count = 0;

   for (i=2; i<=m; i++){
      if (isPrime[i]) {
         for (k=i+i; k<=m; k+=i) isPrime[k] = false;
         count++;
      }
   }
   return count;
}

function sieve() {
    for (var i = 1; i <= 3; i++ ) {
        var m = (1<<i)*10000;
        var flags = Array(m+1);
        nsieve(m, flags);
        //var ret = nsieve(m, flags);
    }
    //return ret;
}

benchmarkFun = sieve;

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
timeFun(benchmarkFun, 100);

// Compute the number of iterations needed to get
// at least 1000ms of execution time
while (timeFun(benchmarkFun, numItrs) < 1000)
    numItrs *= 2;

// Timing runs, several iterations
benchTime = timeFun(benchmarkFun, numItrs) / numItrs;

print('num itrs:', numItrs);
print('exec time (ms):', benchTime);

