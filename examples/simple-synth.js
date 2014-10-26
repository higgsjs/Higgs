// Import required libraries
var stdio = require('lib/stdio');
var stdlib = require('lib/stdlib');
var draw = require('lib/draw');
var music = require('lib/music');
var snd = require('lib/sound');
var rnd = require('lib/random');

// ===========================================================================

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

/**
Interpolation function:
@param x ranges from 0 to 1
*/
function interp(x, yL, yR, exp)
{
    // If the curve is increasing
    if (yR > yL)
    {
        return yL + Math.pow(x, exp) * (yR - yL);
    }
    else
    {
        return yR + Math.pow(1 - x, exp) * (yL - yR);
    }
}

function ARExpEnv(time, attack, release)
{
    if (time < attack)
    {
        return time / attack;
    }
    else
    {
        time = (time - attack) / release;

        var rExp = 2;

        if (time < 1)
            return interp(time, 1, 0, rExp);

        return 0;
    }
}

// ===========================================================================

/// Canvas dimensions
var CANVAS_WIDTH = 800;
var CANVAS_HEIGHT = 400;

function newSound()
{
    print('new sound');

    var sound = new snd.Sound();

    var notes = music.genScale('A3', 'natural minor', 2);
    var curNote = notes[0];

    function nextNote(curNote)
    {
        for (;;)
        {
            var note = rnd.elem(notes);

            var cons = music.consonance(curNote, note);

            if (cons < 0)
                continue;

            return note;
        }
    }

    print('generating sound...');
    var startTime = (new Date()).getTime();

    for (var noteIdx = 0; noteIdx < 6; ++noteIdx)
    {
        var curNote = nextNote(curNote);

        var f0 = curNote.getFreq();
        var f1 = 2.01 * f0;

        for (var i = 0; i < 16000; ++i)
        {
            var t = i / sound.sampleRate;

            var s0 = triOsc(t, f0, 0.25);
            var s1 = triOsc(t, f1, 0.20);

            var e0 = ARExpEnv(t, 0.02, 0.2);
            var e1 = ARExpEnv(t, 0.01, 0.4);

            var s = (e0 * s0 + e1 * s1) / 2;

            sound.setSample(sound.numSamples, 0, s);
        }
    }

    var endTime = (new Date()).getTime();
    print('done generating, time =', endTime - startTime, 'ms');

    window.canvas.clear('#000000');
    window.canvas.setColor(255, 0, 0);

    for (var i = 0; i < sound.numSamples; ++i)
    {
        var s = sound.getSample(i, 0);

        var x = ((i / sound.numSamples) * window.width) | 0;

        var y = (((s + 1) / 2) * window.height) | 0;

        window.canvas.drawPoint(x, y);
    }

    print('num samples:', sound.numSamples);

    tmpName = stdio.tmpname();
    print('writing sound to:', tmpName);
    sound.writeWAV(tmpName);

    var r = stdlib.system('aplay ' + tmpName);
    if (r !== 0)
        print('install aplay program for sound playback');

    stdlib.system('rm ' + tmpName);
}

// Create the drawing window
var window = draw.Window(50, 50, CANVAS_WIDTH, CANVAS_HEIGHT, 'simple-synth');

window.onKeypress(function(canvas, key)
{
    if (key === 'Right')
    {
        newSound();
    }
});

// Set the random seed so we get a different result on every startup
Math.setRandSeed((new Date()).getTime());

// Clear the canvas
window.canvas.clear('#000000');

// Set the font to use
window.canvas.setFont(undefined, 18);

// Generate a new random sound
newSound();

// Show the drawing window
window.show();

