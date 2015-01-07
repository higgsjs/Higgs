/**
@fileOverview
Loads an image file and draws it on a canvas

usage: higgs load-image.js -- <path-to-pbm-image>

@author
Maxime Chevalier-Boisvert
*/

var draw = require('lib/draw');
var img = require('lib/image');
var stdlib = require('lib/stdlib');

var image = img.readPBM(arguments[0]);

var window = draw.Window(50, 50, image.width, image.height, 'load-image');

window.onKeypress(function(canvas, key)
{
    // Press any key to exit
    stdlib.exit(0);
});

var startTime = (new Date()).getTime();

window.canvas.drawImage(0, 0, image);

var endTime = (new Date()).getTime();

print('draw time:', endTime - startTime, 'ms');

window.show();

