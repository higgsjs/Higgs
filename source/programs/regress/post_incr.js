var c = 0;

function f()
{
    c = c + 1;
    return 0;
}

var a = [0];

var v1 = a[f()]++;
var v2 = a[f()]++;

if (v1 !== 0)
    throw Error("v1 should be 0");
if (v2 !== 1)
    throw Error("v2 should be 1");
if (a[0] !== 2)
    throw Error("a[0] should be 2");
if (c !== 2)
    throw Error("c should be 2");

