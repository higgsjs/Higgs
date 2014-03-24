normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [1];
load('benchmarks/shootout/hash2.js');

print = normalPrint;

