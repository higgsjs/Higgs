var cat = 'abcd'
var numItrs = 10000;

var str = '';
for (var i = 0; i < numItrs; ++i)
    str += cat;

assert (str.length === numItrs * cat.length);

