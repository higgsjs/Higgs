// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by David Hedbor
// modified by Isaac Gouy

var n = arguments[0];
var x=0;
var a=n;

// Using while() is faster than for()
while(a--) {
   var b=n; while(b--) {
      var c=n; while(c--) {
         var d=n; while(d--) {
            var e=n; while(e--) {
               var f=n; while(f--) {
                  x++;
               }
            }
         }
      }
   }
}
print(x);