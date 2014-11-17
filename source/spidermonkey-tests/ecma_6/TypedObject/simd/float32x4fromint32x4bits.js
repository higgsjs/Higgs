// |reftest| skip-if(!this.hasOwnProperty("SIMD"))
var BUGNUMBER = 946042;
var float32x4 = SIMD.float32x4;
var int32x4 = SIMD.int32x4;

var summary = 'float32x4 fromInt32x4Bits';

function test() {
  print(BUGNUMBER + ": " + summary);

  var INT32_MAX = Math.pow(2, 31) - 1;
  var INT32_MIN = -Math.pow(2, 31);

  var a = int32x4(100, 200, 300, 400);
  var c = SIMD.float32x4.fromInt32x4Bits(a);
  assertEq(c.x, 1.401298464324817e-43);
  assertEq(c.y, 2.802596928649634e-43);
  assertEq(c.z, 4.203895392974451e-43);
  assertEq(c.w, 5.605193857299268e-43);

  var d = int32x4(INT32_MIN, INT32_MAX, 0, 0);
  var f = float32x4.fromInt32x4Bits(d);
  assertEq(f.x, -0);
  assertEq(f.y, NaN);
  assertEq(f.z, 0);
  assertEq(f.w, 0);

  if (typeof reportCompare === "function")
    reportCompare(true, true);
}

test();

