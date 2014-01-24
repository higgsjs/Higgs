// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by Ian Osgood 

var last = 42;
var A = 3877;
var C = 29573;
var M = 139968;

function rand(max) {
  last = (last * A + C) % M;
  return max * last / M;
}

var n = arguments[0];
for (var i=1; i<n; i++) rand(100);
print(rand(100).toFixed(9));
