/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

(function(exports)
{
    var io = require('lib/stdio');

    /**
    @class Represents a PCM sound clip
    */
    function Sound(numSamples, numChans, sampleRate)
    {
        if (numSamples === undefined)
            numSamples = 0;

        if (numChans === undefined)
            numChans = 1;

        if (sampleRate === undefined)
            sampleRate = 44100;

        this.numSamples = numSamples;
        this.numChans = numChans;
        this.sampleRate = sampleRate;

        this.samples = new Array(numSamples * numChans);
    }

    /**
    Set the value of a sample
    */
    Sound.prototype.setSample = function (pos, chan, val)
    {
        assert (
            chan < this.numChans
        );

        var offset = pos * this.numChans;

        if (offset >= this.samples.length)
            this.samples.length = offset + this.numChans;

        this.samples[offset + chan] = val;
    }

    Sound.prototype.writeWAV = function (fileName)
    {
        // Open the file for writing
        var file = io.fopen(fileName, "w")

        // Write the chunk ID
        file.putc('R');
        file.putc('I');
        file.putc('F');
        file.putc('F');

        // Number of sample data bytes (16-bit samples, two bytes)
        var subchunk2Size = this.samples.length * 2;

        // Write the chunk size (total file size - 8)
        file.writeInt32(36 + subchunk2Size);

        // Write the 4 format bytes
        file.putc('W');
        file.putc('A');
        file.putc('V');
        file.putc('E');

        // Subchunk1
        // Write the wave format chunk header
        file.putc('f');
        file.putc('m');
        file.putc('t');
        file.putc(' ');
        file.writeInt32(16); // Sub chunk size
        file.writeInt16(1); // Audio format (1 = PCM)
        file.writeInt16(this.numChans); // num channels
        file.writeInt32(this.sampleRate); // Sample rate
        file.writeInt32(this.sampleRate * this.numChans * 2); // Byte rate
        file.writeInt16(this.numChannels * 2); // Block align (sample align)
        file.writeInt16(16);  // Bits per sample

        // Subchunk2
        // Write the data chunk header
        file.putc('d');
        file.putc('a');
        file.putc('t');
        file.putc('a');

        // Write the Subchunk2 size (data size)
        file.writeInt32(subchunk2Size);

        // Write the data in 16-bit format
        for (var i = 0; i < this.samples.length; ++i)
        {
            var sample = this.samples[i];

            if (sample > 1)
                sample = 1;
            else if (sample < -1)
                sample = -1;

            var intSample = (sample * 32767) | 0;

            file.writeInt16(intSample);
        }

	    // Close the file
        file.close();
    };

    exports.Sound = Sound;
    // TODO: readWAV

})(exports)

