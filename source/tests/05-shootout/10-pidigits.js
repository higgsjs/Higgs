normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [5];
load('benchmarks/shootout/pidigits.js');

print = normalPrint;

assert (result.trim() === '31415');

