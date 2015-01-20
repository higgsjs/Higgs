Int8Array = Array;
Uint32Array = Array;
console = { log: function () {} };

DIM = 50000
DENSITY = 2000
STDDEV = 0.01
ITERATIONS = 100
spmvRun(DIM, DENSITY, STDDEV, ITERATIONS);
