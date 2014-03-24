normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [10];
load('benchmarks/shootout/nestedloop.js');
assert(x === 1000000);

print = normalPrint;

