normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [10];
load('benchmarks/shootout/random.js');
assert(last === 75056);

print = normalPrint;

