load('benchmarks/ostrich/common_rand.js');
load('benchmarks/ostrich/spmv.js');

console = { log: function () {} }
//console = { log: print }

DIM = 500
DENSITY = 2000
STDDEV = 0.01
ITERATIONS = 10

spmvRun(DIM, DENSITY, STDDEV, ITERATIONS);

