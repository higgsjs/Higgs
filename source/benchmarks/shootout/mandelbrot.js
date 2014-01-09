/* The Computer Language Benchmarks Game
   http://shootout.alioth.debian.org/
   contributed by Thomas GODART (based on Greg Buchholz's C program)
   modified by TA
*/
var i, x, y,
    bit_num = 0,
    byte_acc = 0,
    iter = 50,
    limit = 4,
    Zr, Zi, Cr, Ci, Tr, Ti,
    d = +arguments[0];

print("P4\n" + d + " " + d + "\n");

for (y = 0; y < d; y += 1) {
  for (x = 0; x < d; x += 1) {
    Zr = 0,
    Zi = 0,
    Tr =0,
    Ti =0,
    Cr = 2 * x / d - 1.5,
    Ci = 2 * y / d - 1;

    for (i = 0; i < iter && Tr + Ti <= limit; i += 1) {
      Zi = 2 * Zr * Zi + Ci,
      Zr = Tr - Ti + Cr,
      Tr = Zr * Zr,
      Ti = Zi * Zi;
    }

    byte_acc <<= 1;

    if (Tr + Ti <= limit) {
      byte_acc |=  1;
    }

    bit_num += 1;

    if (bit_num === 8) {
      print(String.fromCharCode(byte_acc));
      byte_acc = 0,
      bit_num = 0;
    } else if (x === d - 1) {
      byte_acc <<= 8 - d % 8;
      print(String.fromCharCode(byte_acc));
      byte_acc = 0,
      bit_num = 0;
    }
  }
}
