function callbackfn(x)
{
}

function foo()
{
    argArray = [0];

    $ir_gc_collect(0);

    argArray[0] = $ir_get_arg(0);

    var argTable = $rt_getArrTbl(argArray);

    $ir_call_apply(callbackfn, null, argTable, 1);
};

foo({});

