var image = require('lib/image');

img = new image.Image(256, 256);

print(img.width);
print(img.height);

for (var y = 0; y < img.height; ++y)
{
    print(y);

    for (var x = 0; x < img.width; ++x)
    {
        var dSqr = (x - 127)*(x-127) + (y-127)*(y-127);

        if (dSqr < 50 * 50)
            img.setPixel(x, y, 255, 0, 0);
        else
            img.setPixel(x, y, 0, 0, 0);
    }
}

print('writing image');
img.writeTGA24('test.tga');

print('done');

