// Copyright (c) 2004 by Arthur Langereis (arthur_ext at domain xfinitegames, tld com)


// 1 op = 2 assigns, 16 compare/branches, 8 ANDs, (0-8) ADDs, 8 SHLs
// O(n)
function bitsinbyte(b) {
var m = 1, c = 0;
while(m<0x100) {
if(b & m) c++;
m <<= 1;
}
return c;
}

function TimeFunc(func) {
var x, y, t;
for(var x=0; x<350; x++)
for(var y=0; y<256; y++) func(y);
}

function benchmarkFun()
{
    TimeFunc(bitsinbyte);
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

