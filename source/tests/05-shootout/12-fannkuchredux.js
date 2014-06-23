normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [8];
load('benchmarks/shootout/fannkuchredux.js');

print = normalPrint;

assert (pf[0] === 1616);

