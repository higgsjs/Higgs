normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [10];
load('benchmarks/shootout/hash.js');
assert(c === 9);

print = normalPrint;

