load('benchmarks/ostrich/common_rand.js');
load('benchmarks/ostrich/pagerank.js');

console = { log: function () {} }

NB_PAGES = 500
NB_ITERATIONS = 10
THRESHOLD = 0.00000001
DIVISOR = 100000

runPageRank(NB_PAGES, NB_ITERATIONS, THRESHOLD, DIVISOR)

