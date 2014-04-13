stdio = require('lib/stdio');
imglib = require('lib/image.js');

img = new imglib.Image(256, 256);

for (var y = 0; y < img.height; ++y)
    for (var x = 0; x < img.width; ++x)
        img.setPixel(x, y, (x*255/img.width)|0, (y*255/img.height)|0, 0);

tmpname = stdio.tmpname();
img.writeTGA24(tmpname);

// TODO: read and compare

