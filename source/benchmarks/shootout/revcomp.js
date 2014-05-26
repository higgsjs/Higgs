/* The Computer Language Benchmarks Game
   http://shootout.alioth.debian.org/

   contributed by Jos Hirth
*/

var line, out, reverseFormat, complement;

complement = {
   y: 'R',
   v: 'B',
   w: 'W',
   t: 'A',
   u: 'A',
   r: 'Y',
   s: 'S',
   n: 'N',
   m: 'K',
   k: 'M',
   h: 'D',
   g: 'C',
   d: 'H',
   b: 'V',
   c: 'G',
   a: 'T',
   Y: 'R',
   V: 'B',
   W: 'W',
   T: 'A',
   U: 'A',
   R: 'Y',
   S: 'S',
   N: 'N',
   M: 'K',
   K: 'M',
   H: 'D',
   G: 'C',
   D: 'H',
   B: 'V',
   C: 'G',
   A: 'T'
};

reverseFormat = function (a, complement) {
   var i, l, line, c = 1, out;
   out = '';
   for (l = a.length; l--;) {
      line = a[l];
      for (i = line.length; i--; c++) {
         out += complement[line[i]];
         if (c === 60) {
            print(out);
            out = '';
            c = 0;
         }
      }
   }
   if (out.length) {
      print(out);
   }
};

out = [];
while ((line = readline())) {
   if (line[0] !== '>') {
      out.push(line);
   } else {
      reverseFormat(out, complement);
      out = [];
      print(line);
   }
}

reverseFormat(out, complement);
