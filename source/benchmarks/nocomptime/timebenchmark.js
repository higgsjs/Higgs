// By performing warmup runs, we abstract out compilation time, standard
// library and runtime initialization time, as well as part of the benchmark
// initialization time (global function definitions). We cannot remove garbage
// collection time from the final timing run, however.

function timeFun(fun)
{
    var startTime = (new Date()).getTime();

    fun();

    var endTime = (new Date()).getTime();

    return endTime - startTime;
}

if (typeof benchmarkFun != 'function')
    throw Error('benchmarkFun not defined!');

// Warmup runs
var w0 = timeFun(benchmarkFun);
var w1 = timeFun(benchmarkFun);

// Timing run
var t = timeFun(benchmarkFun);

print('warmup 0: ', w0);
print('warmup 1: ', w1);
print('time: ', t);

