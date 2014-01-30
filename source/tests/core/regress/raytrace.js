function Scene()
{
}

Scene.prototype.blocked = function()
{
    for (i = 0; i < 5; i++) 
    {
        //print($ir_get_type(i));
    }

    if (typeof i !== 'number')
        throw Error("i is not integer");
}

function raytraceScene()
{
    var scene = new Scene();

    for (var i = 0; i < 5000; ++i)
        scene.blocked();
}

raytraceScene();

