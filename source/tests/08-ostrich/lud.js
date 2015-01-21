load('benchmarks/ostrich/common_rand.js');
load('benchmarks/ostrich/lud.js');

Int32Array = Array;
Float32Array = Array;
Float64Array = Array;
console = { log: function () {} }

SIZE = 32
ludRun(SIZE)

