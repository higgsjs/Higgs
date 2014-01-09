// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by David Hedbor
// modified by Isaac Gouy

var IM = 139968;
var IA = 3877;
var IC = 29573;

var last = 42;

function gen_random(max) { return(max * (last = (last * IA + IC) % IM) / IM); }

function heapsort(n, ra) {
    var l, j, ir, i;
    var rra;

    l = (n >> 1) + 1;
    ir = n;
    for (;;) {
        if (l > 1) {
            rra = ra[--l];
        } else {
            rra = ra[ir];
            ra[ir] = ra[1];
            if (--ir == 1) {
                ra[1] = rra;
                return;
            }
        }
        i = l;
        j = l << 1;
        while (j <= ir) {
            if (j < ir && ra[j] < ra[j+1]) { ++j; }
            if (rra < ra[j]) {
                ra[i] = ra[j];
                j += (i = j);
            } else {
                j = ir + 1;
            }
        }
        ra[i] = rra;
    }
}


var n = arguments[0];
var ary, i;
    
// create an array of N random floats
ary = Array(n+1);
for (i=1; i<=n; i++) {
  ary[i] = gen_random(1.0);
}
heapsort(n, ary);
print(ary[n].toFixed(10));
