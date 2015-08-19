function makeTree(depth)
{
    if (depth == 0)
        return null;

    return {
        left: makeTree(depth-1),
        right: makeTree(depth-1),
        num: depth
    };
}

function treeSum(node)
{
    var sum = node.num;

    if (node.left != null)
        sum += treeSum(node.left);
    if (node.right != null)
        sum += treeSum(node.right);

    return sum;
}

function test()
{
    var root = makeTree(5);

    // 10M iterations
    for (var i = 0; i < 100000000; ++i)
    {
        treeSum(root);
    }
}

test();
