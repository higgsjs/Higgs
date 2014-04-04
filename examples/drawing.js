(function()
{
    var draw = require('lib/draw');

    var mycanvas = draw.CanvasWindow(50, 50, 500, 500, "Higgs Test");

    var x = 120;
    var y = 120;

    mycanvas.onKeypress(function(canvas, key)
    {
        if (x < 400 && key === "Right")
            x += 20;
        else if (x > 0 && key === "Left")
            x -= 20;
        else if (y < 400 && key === "Down")
            y += 20;
        else if (y > 0 && key === "Up")
            y -= 20;
    });

    mycanvas.onRender(function(canvas)
    {
        canvas.setColor("#FFFFFF");

        canvas.fillRect(0, 0, 500, 500);
        canvas.setColor("#00FF00");
        canvas.fillRect(10, 10, 100, 100);
        canvas.setColor("#FF0000");
        canvas.fillRect(10, 120, 100, 100);
        canvas.setColor(255, 255, 0);
        canvas.fillRect(120, 10, 100, 100);
        canvas.setColor("#00FFFF");
        canvas.fillRect(x, y, 100, 100);
    });

    mycanvas.show();

})();
