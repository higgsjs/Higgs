normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [4];
load('benchmarks/shootout/matrix.js');
assert(mm[0][0] === 270165);
assert(mm[4][4] === 1856025);

print = normalPrint;

