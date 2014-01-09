var run = function() 
{
    var g = function ()
    {
        var g5 = function () {};
        var g4 = function () {};
        var g2 = function () {};
        var g3 = function () {};
        var g1 = function () {};

        g1();
        g2();
        g3();
        g4();
        g5();
    }

    var a = function ()
    {
        var f5 = function () {};
        var f4 = function () {};    
        var f2 = function () {};
        var f1 = function () {};
        var f3 = function () {};

        f1();
        f2();
        f3();
        f4();
        f5();
    }

    var e = function ()
    {
        var e3 = function () {};
        var e2 = function () {};
        var e1 = function () {};
        var e4 = function () {};

        e1();
        e2();
        e3();
        e4();
    }

    var d = function ()
    {
        var f5 = function () {};
        var f4 = function () {};    
        var f2 = function () {};
        var f1 = function () {};
        var f3 = function () {};

        f1();
        f2();
        f3();
        f4();
        f5();
    }

    var b = function ()
    {
        var f4 = function () {};    
        var f2 = function () {};
        var f1 = function () {};
        var f3 = function () {};
        var f5 = function () {};

        f1();
        f2();
        f3();
        f4();
        f5();
    }

    var f = function ()
    {
        var f2 = function () {};
        var f3 = function () {};
        var f1 = function () {};
        var f4 = function () {};
        var f5 = function () {};
        var f6 = function () {};
        var f7 = function () {};

        f1();
        f2();
        f3();
        f4();
        f5();
        f6();
        f7();
    }

    var c = function ()
    {
        var f4 = function () {};    
        var f2 = function () {};
        var f3 = function () {};
        var f1 = function () {};
        var f5 = function () {};

        f1();
        f2();
        f3();
        f4();
        f5();
    }

    a();
    b();
    c();
    d();
    e();
    e();
    f();
    g();
}

for (var i = 0; i < 5; ++i)
{
    run();

    $ir_gc_collect(0);
}

