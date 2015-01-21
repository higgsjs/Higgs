load('benchmarks/ostrich/common_rand.js');
load('benchmarks/ostrich/bfs.js');

Int32Array = Array;
Uint8Array = Array;
Uint32Array = Array;
Float32Array = Array;
Float64Array = Array;
console = { log: function () {} }

NB_NODES = 20000
BFSGraph(NB_NODES)

