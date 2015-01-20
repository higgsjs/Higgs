if (typeof performance === "undefined") {
    performance = Date;
}

var MIN_NODES      = 20;
var MAX_NODES      = 1<<31;
var MIN_EDGES      = 2;
var MAX_INIT_EDGES = 4;
var MIN_WEIGHT     = 1;
var MAX_WEIGHT     = 1;

function node(starting, no_of_edges) {
    return {
        "starting": starting,
        "no_of_edges": no_of_edges
    };
}


function edge(dest, weight) {
    return {
        "dest": dest,
        "weight": weight
    };
}

function BFSGraph(no_of_nodes, verbose) {
    if (verbose === undefined) {
        verbose = false;
    }
    var expected_no_of_nodes = 3000000;
    var expected_total_cost = 26321966;
    var t1 = performance.now();
    var inits = InitializeGraph(no_of_nodes);
    var h_graph_nodes = inits.h_graph_nodes;
    var h_graph_mask = inits.h_graph_mask;
    var h_updating_graph_mask = inits.h_updating_graph_mask;
    var h_graph_visited = inits.h_graph_visited;
    var h_cost = inits.h_cost;
    var h_graph_edges = inits.h_graph_edges;
    var t2 = performance.now();
    var init_time = t2 - t1;

    var k = 0;
    var stop;

    t1 = performance.now();
    do {
        stop = false;

        for(var tid = 0; tid < no_of_nodes; ++tid) {
            if (h_graph_mask[tid]) {
                h_graph_mask[tid] = false;
                for ( var i = h_graph_nodes[tid].starting
                      ; i < (h_graph_nodes[tid].no_of_edges + h_graph_nodes[tid].starting)
                      ; ++i) {
                    var id = h_graph_edges[i];
                    if (!h_graph_visited[id]) {
                        h_cost[id] = h_cost[tid] + 1;
                        h_updating_graph_mask[id] = true;
                    }
                }
            }
        }

        for (var tid = 0; tid < no_of_nodes; ++tid) {
            if (h_updating_graph_mask[tid]) {
                h_graph_mask[tid] = true;
                h_graph_visited[tid] = true;
                stop = true;
                h_updating_graph_mask[tid] = false;
            }
        }
        ++k;
    }
    while(stop);
    t2 = performance.now();
    var traversal_time = t2 - t1;

    var total_cost = 0;
    for (var i=0; i<no_of_nodes; ++i) {
        total_cost += h_cost[i];
    }
    if (no_of_nodes == expected_no_of_nodes) {
        if (total_cost != expected_total_cost) {
            throw new Error("ERROR: the total cost obtained for '" + no_of_nodes + "' nodes is '" + total_cost + "' while the expected cost is '" + expected_total_cost + "'");
        }
    } else {
        console.log("WARNING: no self-checking step for '" + no_of_nodes + "' nodes, only valid for '" + expected_no_of_nodes + "' nodes");
    }

    console.log("Init time     : " + (init_time/1000) + " s");
    console.log("Traversal time: " + (traversal_time/1000) + " s");

    if (verbose) {
        for (var i = 0; i < no_of_nodes; ++i) {
            console.log(i + ") cost: " + h_cost[i]);
        }
    }

    return { status: 1,
             options: "BFSGraph(" + no_of_nodes + ")",
             time: traversal_time / 1000 };
}





function InitializeGraph(no_of_nodes) {
    var h_graph_nodes = new Array(no_of_nodes);
    var h_graph_mask = new Uint8Array(no_of_nodes);
    var h_updating_graph_mask = new Uint8Array(no_of_nodes);
    var h_graph_visited = new Uint8Array(no_of_nodes);
    var h_cost = new Uint32Array(no_of_nodes);

    var source = 0;
    var graph = new Array(no_of_nodes);
    for (var i = 0; i < no_of_nodes; ++i) {
        graph[i] = [];
    }

    for (var i = 0; i < no_of_nodes; ++i) {
        var no_of_edges = Math.abs(Math.commonRandom() % ( MAX_INIT_EDGES - MIN_EDGES + 1 )) + MIN_EDGES;
        for (var j = 0; j < no_of_edges; ++j) {
            var node_id = Math.abs(Math.commonRandom() % no_of_nodes);
            var weight = Math.abs(Math.commonRandom() % ( MAX_WEIGHT - MIN_WEIGHT + 1 )) + MIN_WEIGHT;

            graph[i].push(edge(node_id, weight));
            graph[node_id].push(edge(i, weight));
        }
    }

    var total_edges = 0;
    for (var i = 0; i < no_of_nodes; ++i) {
        var no_of_edges = graph[i].length;
        h_graph_nodes[i] = node(total_edges, no_of_edges);
        h_graph_mask[i] = false;
        h_updating_graph_mask[i] = false;
        h_graph_visited[i] = false;

        total_edges += no_of_edges;
    }

    h_graph_mask[source] = true;
    h_graph_visited[source] = true;

    var h_graph_edges = new Array(total_edges);

    var k = 0;
    for (var i = 0; i < no_of_nodes; ++i) {
        for (var j = 0; j < graph[i].length; ++j) {
            h_graph_edges[k] = graph[i][j].dest;
            ++k;
        }
    }

    for (var i = 0; i < no_of_nodes; ++i) {
        h_cost[i] = -1;
    }
    h_cost[source] = 0;

    return {
        h_graph_nodes: h_graph_nodes,
        h_graph_mask: h_graph_mask,
        h_updating_graph_mask: h_updating_graph_mask,
        h_graph_visited: h_graph_visited,
        h_cost: h_cost,
        h_graph_edges: h_graph_edges
    }
}
