stdio = require('lib/stdio');
imglib = require('lib/image.js');

img = new imglib.Image(256, 256);

for (var y = 0; y < img.height; ++y)
    for (var x = 0; x < img.width; ++x)
        img.setPixel(x, y, (x*255/img.width)|0, (y*255/img.height)|0, 0);

// Write the image to a temp file
tmpname = stdio.tmpname();
imglib.writeTGA24(img, tmpname);

// Read the image back from the file
img2 = imglib.readTGA24(tmpname);

assert (
    img.width === img2.width &&
    img.height === img2.height
);

for (var y = 0; y < img.height; ++y)
{
    for (var x = 0; x < img.width; ++x)
    {
        var p1 = img.getPixel(x, y);
        var p2 = img2.getPixel(x, y);

        assert (
            p1.r === p2.r &&
            p1.g === p2.g &&
            p1.b === p2.b
        );
    }
}

