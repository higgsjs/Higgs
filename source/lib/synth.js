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
    var snd = require('lib/sound');
    var mus = require('lib/music');







    /**
    Triangle wave oscillator
    @param phase phase offset in cycles [0, 1]
    */
    function triOsc(time, freq, phase)
    {
        var absPos = phase + time * freq;
        var cyclePos = absPos - (absPos | 0);

        if (cyclePos < 0.5)
            return (4 * cyclePos) - 1;
        else
            return 1 - (4 * (cyclePos - 0.5));
    }

    // TODO: sineOsc
    /*
    Math.sin(2 * Math.PI * cyclePos);
    */

    function noiseOsc()
    {
        return Math.random() * 2 - 1;
    }






    /*
    ./higgs --e "synth = require('lib/synth'); sound = synth.synthBassDrum(44100); sound.writeWAV('test.wav');"; aplay test.wav
    */

    function synthBassDrum(sampleRate)
    {
        var sound = new snd.Sound(30000);

        for (var i = 0; i < sound.numSamples; ++i)
        {
            var t = i / sampleRate;

            var a = Math.max(0, 1 - (t / 0.20));

            var s = a * triOsc(t, 42, 0.25);

            sound.setSample(i, 0, s);
        }

        return sound;
    }

    function synthSnare(sampleRate)
    {
        var sound = new snd.Sound(30000);

        for (var i = 0; i < sound.numSamples; ++i)
        {
            var t = i / sampleRate;

            // TODO: very short attack?
            var a = Math.max(0, 1 - (t / 0.25));

            var s = a * (1.0 * triOsc(t, 20, 0.25) + 0.1 * noiseOsc());

            sound.setSample(i, 0, s);
        }

        return sound;


    }


    // TODO: try acid note






    // TODO: function in sound to (over)write a given sound at a given time offset







    exports.synthBassDrum = synthBassDrum;
    exports.synthSnare = synthSnare;

})(exports)

