var o = {}

// Extend the object
o.x = 1;
o.y = 2;
o.z = 3;
o.w = 4;

// Trigger a collection
$ir_gc_collect(0);

assert (
    o.x == 1 &&
    o.y == 2 &&
    o.z == 3 &&
    o.w == 4
);

