// Copyright (c) 2004 by Arthur Langereis (arthur_ext at domain xfinitegames, tld com

// 1 op = 6 ANDs, 3 SHRs, 3 SHLs, 4 assigns, 2 ADDs
// O(1)
function fast3bitlookup(b) {
var c, bi3b = 0xE994; // 0b1110 1001 1001 0100; // 3 2 2 1  2 1 1 0
c  = 3 & (bi3b >> ((b << 1) & 14));
c += 3 & (bi3b >> ((b >> 2) & 14));
c += 3 & (bi3b >> ((b >> 5) & 6));
return c;

/*
lir4,0xE994; 9 instructions, no memory access, minimal register dependence, 6 shifts, 2 adds, 1 inline assign
rlwinm r5,r3,1,28,30
rlwinm r6,r3,30,28,30
rlwinm r7,r3,27,29,30
rlwnm r8,r4,r5,30,31
rlwnm r9,r4,r6,30,31
rlwnm r10,r4,r7,30,31
add r3,r8,r9
add r3,r3,r10
*/
}

function TimeFunc(func) {
var x, y, t;
for(var x=0; x<500; x++)
for(var y=0; y<256; y++) func(y);
}

function benchmarkFun()
{
    TimeFunc(fast3bitlookup);
}

load('benchmarks/nocomptime/timebenchmark.js');

