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

