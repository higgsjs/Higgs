function Node(v)
{
    this.value = v;
    this.edges = [];
}

function addEdge(n)
{
    //iir.trace_print('entering addEdge');

    this.edges.push(n);
}
Node.prototype.addEdge = addEdge;

function remEdge(n)
{
    //iir.trace_print('remEdge');    

    var idx = this.edges.indexOf(n);

    //iir.trace_print('splicing');

    if (idx !== -1)
        this.edges.splice(idx, 1);
    else
        error('edge missing');

    //iir.trace_print('leaving remEdge');
}
Node.prototype.remEdge = remEdge;

function graphSum(root)
{
    //iir.trace_print('entering graphSum');

    var visited = [];

    var sum = 0;

    function visit(n)
    {
        //iir.trace_print('entering visit');

        if (visited.indexOf(n) !== -1)
            return;

        //iir.trace_print('calling push');

        visited.push(n);

        //iir.trace_print('called push');

        sum += n.value;

        for (var i = 0; i < n.edges.length; ++i)
            visit(n.edges[i]);

        //iir.trace_print('leaving visit');
    }
    
    visit(root);

    //iir.trace_print('leaving graphSum');

    return sum;
}

function test()
{
    // Shrink the heap for testing
    $rt_shrinkHeap(500000);

    var gcCount = $ir_get_gc_count();

    var root = new Node(1);
    var a = new Node(2);
    var b = new Node(3);

    root.addEdge(a);
    a.addEdge(b);
    b.addEdge(root);

    if (graphSum(root) !== 6)
        return 1;

    while ($ir_get_gc_count() < gcCount + 2)
    {
        //iir.trace_print('creating new node');

        var oa = root.edges[0];
        var na = new Node(oa.value);

        //iir.trace_print('patching edges');

        root.remEdge(oa);
        root.addEdge(na);
        na.addEdge(b);

        //iir.trace_print('in-loop sum');

        if (graphSum(root) !== 6)
            return 2;
    }

    //iir.trace_print('final sum');

    if (graphSum(root) !== 6)
        return 3;

    return 0;
}

