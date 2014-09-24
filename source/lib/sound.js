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
    function Sound(numSamples, numChans)
    {
        if (numSamples === undefined)
            numSamples = 0;

        if (numChans === undefined)
            numChans = 1;

        this.numChans = numChans;
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

        var offset = pos.this.numChans;

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

        // Write the 4 format bytes
        file.putc('W');
        file.putc('A');
        file.putc('V');
        file.putc('E');




        // TODO: compute the wave chunk size

        /*
	    // Ensure that the sound parameters are valid	
	    if (NumChannels <= 0 || SampleRate <= 0 || BitsPerSample <= 0 || BitsPerSample % 8 != 0)
	    {
		    fclose(pFile);
		    return false;
	    }
	
	    // Ensure that the block alignment is coherent
	    if (BlockAlign > NumChannels * (BitsPerSample / 8))
	    {
		    fclose(pFile);
		    return false;
	    }
        */




        // Write the wave format chunk header
        file.putc('f');
        file.putc('m');
        file.putc('t');
        file.putc(' ');
        file.writeInt32();  // Wave chunk size
        file.writeInt16(1);  // Audio format
        file.writeInt16();  // num channels
        file.writeInt32();  // Sample rate
        file.writeInt32();  // Byte rate
        file.writeInt16();  // Block align
        file.writeInt16();  // Bits per sample







        // TODO
        // Write the data chunk header
        file.putc('d');
        file.putc('a');
        file.putc('t');
        file.putc('a');



        /*		
	    fread(&SubChunk2Size, sizeof(SubChunk2Size), 1, pFile);

	    // Ensure that the data chunk size is valid
	    if (SubChunk2Size < BlockAlign)
	    {
		    fclose(pFile);
		    return false;
	    }

	    // Store the current file position
	    size_t DataStart = ftell(pFile);
	
	    // Seek to the end of the file
	    fseek(pFile, 0, SEEK_END);
	
	    // Store the end of file position
	    size_t DataEnd = ftell(pFile);
	
	    // Seek back to the start of the data
	    fseek(pFile, DataStart, SEEK_SET);

	    // Compute the size of the audio data
	    size_t DataSize = DataEnd - DataStart;

	    // If the data size does not match the data chunk size, stop	
	    if ((size_t)SubChunk2Size > DataSize)
	    {
		    fclose(pFile);
		    return false;
	    }	
	
	    // Allocate a buffer to read the data
	    byte* pDataBuffer = new byte[SubChunk2Size];
	
	    // Declare a variable for the number of data bytes read
	    size_t DataBytesRead = 0;
	
	    // Until all the data has been read
	    while (DataBytesRead < (size_t)SubChunk2Size)
	    {
		    // Read as much data as possible
		    size_t NumRead = fread(&pDataBuffer[DataBytesRead], sizeof(byte), SubChunk2Size - DataBytesRead, pFile);
		
		    // Increment the number of bytes read
		    DataBytesRead += NumRead;
		
		    // If there was an error reading the file
		    if (ferror(pFile))
		    {
			    // Close the file
			    fclose(pFile);
			
			    // Delete the data buffer
			    delete [] pDataBuffer;
			
			    // Abort the operation
			    return false;
		    }	
	    }

	    // Close the file
	    fclose(pFile);
        */	




        /*
	    // Compute the total number of blocks
	    size_t NumBlocks = SubChunk2Size / BlockAlign;
		
	    // Reserve space for the samples
	    m_Samples.reserve(NumChannels * (SubChunk2Size / BlockAlign));

	    // If we are working with 16 bits per sample
	    if (BitsPerSample == 16)
	    {
		    // For each block to be processed
		    for (size_t BlockIndex = 0; BlockIndex < NumBlocks; ++BlockIndex)
		    {
			    // Compute the address of the block
			    byte* pBlock = &pDataBuffer[BlockIndex * BlockAlign];
			
			    // For each channel
			    for (int ChanIndex = 0; ChanIndex < NumChannels; ++ChanIndex)
			    {
				    // Extract the sample
				    int16 Sample = *((int16*)&pBlock[ChanIndex * 2]);
				
				    // Convert the sample to a real value
				    float RealSample = float(Sample) / 32767;
				
				    // Store the sample
				    m_Samples.push_back(RealSample);
			    }
		    }	
	    }
        */







	    // Close the file
        file.close();
    };

    exports.Sound = Sound;
    // TODO: readWAV

})(exports)

