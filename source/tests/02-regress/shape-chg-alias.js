function foo(a, b)
{
    if (!$ir_is_int32(b.x))
        throw Error('missing property b.x');

    a.y = 2;

    if (!$ir_is_int32(b.y))
        throw Error('incorrect handling of object aliasing');
}

o = { x: 1 };

foo(o, o);

