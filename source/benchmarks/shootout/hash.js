// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by David Hedbor
// modified by Isaac Gouy

var i, c = 0;
var n = arguments[0];

var X = new Object();
for (i=1; i<=n; i++) {
   X[i.toString(16)] = i;
}
for (i=n; i>0; i--) {
  if (X[i.toString()]) c++;
}
print(c);

