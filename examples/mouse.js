// This HiggsJS example program demonstrates how to use the mouse functions.

var draw = require('lib/draw');
    
var window = draw.Window(50, 50, 500, 500, "mouse example");
    
// Two global variables for storing the xy coordinates
var drawX;
var drawY;

window.onClick(function(canvas, mouseX, mouseY)
{
    // Put all mouse click logic here.
    print("click: " + mouseX + " : " + mouseY);
});

// Update new mouse coordinates when moved
window.onMouseMove(function(canvas, mouseX, mouseY)
{
    // Put all mouse movement logic here.
    drawX = mouseX;
    drawY = mouseY        
});

window.onRender(function(canvas)
{        
    canvas.clear("#FFFFFF");

    // Black dot at current mouse cordinates.
    canvas.setColor("#000000");
    canvas.fillCircle(drawX, drawY, 5);
    
    // Intersecting lines aligned with mouse pointer.    
    canvas.drawLine(0, drawY, 500, drawY);
    canvas.drawLine(drawX, 0, drawX, 500);
    
    // Print mouse coordinates to canvas.
    canvas.setFont("courier", 16);
    canvas.drawText(drawX - 150, drawY, " X: " + drawX);
    canvas.drawText(drawX + 50, drawY, " Y: " + drawY);
});

window.show();
