var snd = require('lib/sound');

var stdio = require('lib/stdio');

var sound = new snd.Sound(40000);

for (var i = 0; i < sound.numSamples; ++i)
{
    var s = Math.sin(300 * i * 2 * Math.PI / sound.sampleRate);
    sound.setSample(i, 0, s);
}

tmpName = stdio.tmpname();
sound.writeWAV(tmpName);

