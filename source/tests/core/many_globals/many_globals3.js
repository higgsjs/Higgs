var globalObj = this;

assert (
    globalObj !== null &&
    typeof globalObj === 'object',
    'invalid global object'
);

for (var i = 0; i < 5000; ++i)
{
    var vName = 'glob' + i;
    globalObj[vName] = i;
}

var theGlob = 777;

assert (
    theGlob === 777,
    'invalid global value'    
);

assert (
    this === globalObj,
    'global obj comparison failed'
);

