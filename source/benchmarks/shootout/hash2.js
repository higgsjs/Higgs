// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by David Hedbor
// modified by Isaac Gouy

var n = arguments[0];
var hash1 = Object();
var hash2 = Object();
var arr = Array(10000);
var idx;

for (i=0; i<10000; i++) {
  idx = "foo_"+i;
  hash1[idx] = i;
  // Do this here and run loop below one less since += on an undefined
  // entry == NaN.
  hash2[idx] = hash1[idx];
}

for (i = 1; i < n; i++) {
  for(a in hash1) {
    hash2[a] += hash1[a];
  }
}

print(hash1["foo_1"], hash1["foo_9999"],
      hash2["foo_1"], hash2["foo_9999"]);
