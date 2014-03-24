normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [2];
load('benchmarks/shootout/lists-quick.js');
assert (result === 100);

print = normalPrint;

