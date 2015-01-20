stdio = require('lib/stdio');
imglib = require('lib/image.js');

// Create an image and generate a color gradient
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

// Compare pixels from the written and read image
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

// Load the Lenna PBM image
img = imglib.readPBM('../examples/load-image/lenna512.pbm');

assert (img.width === 512 && img.height === 512);

// Count and verify the number of white pixels
var numOnes = 0;
for (var y = 0; y < img.height; ++y)
{
    for (var x = 0; x < img.width; ++x)
    {
        var p = img.getPixel(x, y);
        assert (p.r === p.g && p.g === p.b);
        numOnes += (p.r > 0)? 1:0;
    }
}
assert (numOnes === 134000);

