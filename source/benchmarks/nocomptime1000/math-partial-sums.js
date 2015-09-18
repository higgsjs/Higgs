// The Computer Language Shootout
// http://shootout.alioth.debian.org/
// contributed by Isaac Gouy

function partial(n){
    var a1 = a2 = a3 = a4 = a5 = a6 = a7 = a8 = a9 = 0.0;
    var twothirds = 2.0/3.0;
    var alt = -1.0;
    var k2 = k3 = sk = ck = 0.0;
    
    for (var k = 1; k <= n; k++){
        k2 = k*k;
        k3 = k2*k;
        sk = Math.sin(k);
        ck = Math.cos(k);
        alt = -alt;
        
        a1 += Math.pow(twothirds,k-1);
        a2 += Math.pow(k,-0.5);
        a3 += 1.0/(k*(k+1.0));
        a4 += 1.0/(k3 * sk*sk);
        a5 += 1.0/(k3 * ck*ck);
        a6 += 1.0/k;
        a7 += 1.0/k2;
        a8 += alt/k;
        a9 += alt/(2*k -1);
    }
}

function benchmarkFun()
{
    for (var i = 1024; i <= 16384; i *= 2) {
        partial(i);
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

    return (endTime - startTime) / numItrs;
}

if (typeof benchmarkFun != 'function')
    throw Error('benchmarkFun not defined!');

// Benchmarking time (to be measured)
var benchTime = 0.0;

// Number of timing iterations
var numItrs = 100;

// Perform 1000 warmup iterations
timeFun(benchmarkFun, 1000);

// Time the benchmark over 100 iterations
benchTime = timeFun(benchmarkFun, numItrs);

print('num itrs:', numItrs);
print('exec time (ms):', benchTime);

