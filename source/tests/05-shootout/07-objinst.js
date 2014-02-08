normalPrint = print;
silentPrint = function () {};

print = silentPrint;

arguments = [10];
load('benchmarks/shootout/objinst.js');

print = normalPrint;

