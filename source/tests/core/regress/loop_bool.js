function foo()
{
    var thebool1 = true;
    var thebool2 = thebool1 && true;

    assert (
        thebool2 === true,
        'boolean is not true'
    );
}

for (var i = 0; i < 20000; ++i)
    foo();

