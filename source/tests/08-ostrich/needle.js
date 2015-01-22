load('benchmarks/ostrich/common_rand.js');
load('benchmarks/ostrich/needle.js');

console = { log: function () {} }

DIMENSIONS = 64
PENALTY = 1
runNeedle(DIMENSIONS, PENALTY)

