normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [5];
load('benchmarks/shootout/strcat.js');

print = normalPrint;

assert (str.length === 30);

