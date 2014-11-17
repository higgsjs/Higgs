// |reftest| skip-if(!this.hasOwnProperty("SIMD"))
var BUGNUMBER = 996076;
var float32x4 = SIMD.float32x4;
var int32x4 = SIMD.int32x4;

var summary = 'int32x4 equal';

function test() {
  print(BUGNUMBER + ": " + summary);

  var a = int32x4(1, 20, 30, 40);
  var b = int32x4(10, 20, 30, 4);
  var c = SIMD.int32x4.equal(a, b);
  assertEq(c.x, 0);
  assertEq(c.y, -1);
  assertEq(c.z, -1);
  assertEq(c.w, 0);

  if (typeof reportCompare === "function")
    reportCompare(true, true);
}

test();

