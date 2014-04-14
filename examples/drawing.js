(function()
{
    var draw = require('lib/draw');

    var window = draw.Window(50, 50, 500, 500, "Higgs Test");

    var x = 170;
    var y = 170;

    window.onKeypress(function(canvas, key)
    {
        if (x < 450 && key === "Right")
            x += 10;
        else if (x > 50 && key === "Left")
            x -= 10;
        else if (y < 450 && key === "Down")
            y += 10;
        else if (y > 50 && key === "Up")
            y -= 10;
    });

    window.onRender(function(canvas)
    {
        canvas.clear("#FFFFFF");

        canvas.setColor("#00FF00");
        canvas.fillRect(10, 10, 100, 100);
        canvas.setColor("#FF0000");
        canvas.fillRect(10, 120, 100, 100);
        canvas.setColor(255, 255, 0);
        canvas.fillRect(120, 10, 100, 100);
        canvas.setColor("#00FFFF");
        canvas.fillCircle(x, y, 50);

        canvas.setColor("#000000");
        canvas.drawText(50, 300, "Hello World");
    });

    window.show();

})();
