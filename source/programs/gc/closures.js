function test()
{
    var FREE_SIZE = 5000;

    var numClos = 2 * $ir_div_i32(FREE_SIZE, $rt_clos_comp_size(0, 0));

    $rt_shrinkHeap(FREE_SIZE);

    //println('num clos: ' + numClos);

    var a = 0;

    for (var i = 0; i < numClos; ++i)
    {
        //println('itr');

        clos = function () { a++; }

        clos();
    }

    if (a !== numClos)
        return 1;

    return 0;
}

