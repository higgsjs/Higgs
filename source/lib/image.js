/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013, Maxime Chevalier-Boisvert. All rights reserved.
*
*  This software is licensed under the following license (Modified BSD
*  License):
*
*  Redistribution and use in source and binary forms, with or without
*  modification, are permitted provided that the following conditions are
*  met:
*   1. Redistributions of source code must retain the above copyright
*      notice, this list of conditions and the following disclaimer.
*   2. Redistributions in binary form must reproduce the above copyright
*      notice, this list of conditions and the following disclaimer in the
*      documentation and/or other materials provided with the distribution.
*   3. The name of the author may not be used to endorse or promote
*      products derived from this software without specific prior written
*      permission.
*
*  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
*  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
*  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
*  NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
*  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
*  NOT LIMITED TO PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
*  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
*  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
*  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
*  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
*****************************************************************************/

(function()
{
    var io = require('lib/stdio');

    /**
    @class Represents an RGBA bitmap image
    */
    function Image(width, height)
    {
        this.width = width;
        this.height = height;

        this.data = new Array(4 * width * height);
        for (var i = 0; i < this.width * this.height; ++i)
            this.data[i] = 0;
    }

    /**
    Set the color of a single pixel
    */
    Image.prototype.setPixel = function (x, y, r, g, b, a)
    {
        assert (
            x < this.width && y < this.height,
            'invalid pixel coordinates'
        );

        if (g === undefined)
        {
            r = r.r;
            g = r.g;
            b = r.b;
            a = r.a;
        }

        if (a === undefined)
        {
            a = 255;
        }

	    // Copy the pixel color information
	    this.data[4 * (y * this.width + x) + 0] = r;
	    this.data[4 * (y * this.width + x) + 1] = g;
	    this.data[4 * (y * this.width + x) + 2] = b;
	    this.data[4 * (y * this.width + x) + 3] = a;
    };

    /**
    Get the color of a single pixel
    */
    Image.prototype.getPixel = function (x, y)
    {
        assert (
            x < this.width && y < this.height,
            'invalid pixel coordinates'
        );

	    // Copy the pixel color information
        return {
	        r: this.data[4 * (y * this.width + x) + 0],
	        g: this.data[4 * (y * this.width + x) + 1],
	        b: this.data[4 * (y * this.width + x) + 2],
	        a: this.data[4 * (y * this.width + x) + 3]
        };
    }

    /**
    Write the image to a 24-bit RGB Targa (TGA) file
    */
    Image.prototype.writeTGA24 = function (fileName)
    {
	    // Make sure there is image data
        assert (
            this.data instanceof Array,
            'no image data'
        );

        // Open the file for writing
        var file = io.fopen(fileName, "w")

	    // Write the appropriate values in the header
	    file.writeUint8(0);             // No custom identification
	    file.writeUint8(0);             // No color map
	    file.writeUint8(2);             // Uncompressed, RGB image
	    file.writeUint16(0);            // No color map
  	    file.writeUint16(0);            // No color map
	    file.writeUint8(0);             // No color map
	    file.writeUint16(0);            // X Origin
	    file.writeUint16(0);            // Y Origin
	    file.writeUint16(this.width);   // Image width
	    file.writeUint16(this.height);  // Image height
	    file.writeUint8(24);            // 24 bit RGB color
	    file.writeUint8(0x20);          // Image descriptor

	    // Loop through every pixel of the image
	    for (var i = 0; i < this.width * this.height; ++i)
	    {
		    // Write this pixel in BGR order (yes, targa stores it as BGR)
            file.writeUint8(this.data[4 * i + 2]);
            file.writeUint8(this.data[4 * i + 1]);
            file.writeUint8(this.data[4 * i + 0]);
	    }

	    // Close the file
        file.close();
    };

    // Exported namespace
    exports = {
        Image: Image
        // TODO: readTGA24
    };

})()

