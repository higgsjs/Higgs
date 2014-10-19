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

var sampleTime = 0.0;
var benchTime = 0.0;
var numItrs = 0;

// First warmup run
timeFun(benchmarkFun, 1);

// Sample timing run
sampleTime = timeFun(benchmarkFun, 1);

// Compute the number of iterations needed to get at least
// 1000ms of execution time
numItrs = Math.ceil(1000 / (sampleTime + 1));

// If the sample time was less than 1000ms, perform additional warmup
// iterations to make sure advanced JIT optimizations are run
if (sampleTime < 1000)
    timeFun(benchmarkFun, numItrs);

// Timing run
benchTime = timeFun(benchmarkFun, numItrs) / numItrs;

print('sample time: ', sampleTime);
print('num itrs: ', numItrs);
print('benchmark time: ', benchTime);

