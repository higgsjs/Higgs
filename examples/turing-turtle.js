/**
@fileOverview
Program to produce drawings using a turtle plotter controlled
by a randonly generated Turing machine.

usage: higgs turing-turtle.js

or:    higgs turing-turtle.js -- <canvas_width> <canvas_height>

@author
Maxime Chevalier-Boisvert
*/

// Import required libraries
var draw = require('lib/draw');
var image = require('lib/image');
var rnd = require('lib/random');

// ===========================================================================

/// Number of direction vectors
var NUM_DIRS = 100;

/// Direction vectors
var vecX = new Array(NUM_DIRS);
var vecY = new Array(NUM_DIRS);
for (var i = 0; i < NUM_DIRS; ++i)
{
    vecX[i] = Math.cos(2 * Math.PI * i / 100);
    vecY[i] = Math.sin(2 * Math.PI * i / 100);
}

/// Memory tape actions
var NUM_TAPE_ACTIONS = 2;
var TAPE_LEFT    = 0;
var TAPE_RIGHT   = 1;

/// Output/plotting actions
var NUM_OUT_ACTIONS = 9;
var OUT_FORWARD = 0;
var OUT_LEFT    = 1;
var OUT_RIGHT   = 2;
var OUT_R_UP    = 3;
var OUT_R_DN    = 4;
var OUT_G_UP    = 5;
var OUT_G_DN    = 6;
var OUT_B_UP    = 7;
var OUT_B_DN    = 8;

/**
N states, one start state
K symbols (written on tape)
4 tape actions (left, right up, down)
X output actions (forward, left, right)

N x K -> N x K x T x O
*/
function Machine(
    numStates,
    numSymbols,
    tapeLength,
    canvasWidth,
    canvasHeight
)
{
    assert (
        numStates >= 1,
        'must have at least 1 state'
    );

    assert (
        numSymbols >= 2,
        'must have at least 2 symbols'
    );

    /// Number of states and symbols
    this.numStates = numStates;
    this.numSymbols = numSymbols;

    /// Map (2D tape)
    this.tape = Array(tapeLength);

    /// Canvas width and height
    this.canvasWidth = canvasWidth;
    this.canvasHeight = canvasHeight;

    /// Transition table
    this.table = new Array(numStates * numSymbols * 4);

    // Generate random transitions
    for (var st = 0; st < numStates; ++st)
    {
        for (var sym = 0; sym < numSymbols; ++sym)
        {
            this.setTrans(
                st,
                sym,
                rnd.index(numStates),
                rnd.index(numSymbols),
                rnd.index(NUM_TAPE_ACTIONS),
                rnd.index(NUM_OUT_ACTIONS)
            );
        }
    }

    // Initialize the state
    this.reset();
}

Machine.prototype.setTrans = function (
    st0,
    sy0,
    st1,
    sy1,
    tapeAc,
    outAc
)
{
    var idx = (this.numStates * sy0 + st0) * 4;

    this.table[idx + 0] = st1;
    this.table[idx + 1] = sy1;
    this.table[idx + 2] = tapeAc;
    this.table[idx + 3] = outAc;
}

Machine.prototype.reset = function ()
{
    /// Current machine state
    this.state = 0;

    /// Read/write head position on the tape
    this.tapePos = 0;

    /// Current canvas position, initially top-left corner
    this.posX = this.canvasWidth / 2;
    this.posY = this.canvasHeight / 2;

    /// Current color, initially white
    this.colorR = 255;
    this.colorG = 255;
    this.colorB = 255;

    /// Current direction, initially pointing right
    this.dir = 0;

    // Initialize the tape
    for (var i = 0; i < this.tape.length; ++i)
        this.tape[i] = 0;

    /// Iteration count
    this.itrCount = 0;
}

Machine.prototype.update = function (numItrs)
{
    for (var i = 0; i < numItrs; ++i)
    {
        var sym = this.tape[this.tapePos];
        var st = this.state;

        var idx = (this.numStates * sym + st) * 4;
        var st      = this.table[idx + 0];
        var sym     = this.table[idx + 1];
        var tapeAc  = this.table[idx + 2];
        var outAc   = this.table[idx + 3];

        // Update the current state
        this.state = st;

        // Write the new symbol
        this.tape[this.tapePos] = sym;

        // Perform the tape action
        switch (tapeAc)
        {
            case TAPE_LEFT:
            this.tapePos -= 1;
            if (this.tapePos < 0)
                this.tapePos += this.tape.length;
            break;

            case TAPE_RIGHT:
            this.tapePos += 1;
            if (this.tapePos >= this.tape.length)
                this.tapePos -= this.tape.length;
            break;

            default:
            assert(false, 'invalid tape action: ' + tapeAc);
        }

        // Perform the output action
        switch (outAc)
        {
            case OUT_FORWARD:
            this.posX += vecX[this.dir];
            this.posY += vecY[this.dir];
            if (this.posX < 0)
                this.posX += this.canvasWidth;
            if (this.posX >= this.canvasWidth)
                this.posX -= this.canvasWidth;
            if (this.posY < 0)
                this.posY += this.canvasHeight;
            if (this.posY >= this.canvasHeight)
                this.posY -= this.canvasHeight;
            break;

            case OUT_LEFT:
            this.dir += 1;
            if (this.dir >= NUM_DIRS)
                this.dir -= NUM_DIRS;
            break;

            case OUT_RIGHT:
            this.dir -= 1;
            if (this.dir < 0)
                this.dir += NUM_DIRS;
            break;

            case OUT_R_UP:
            this.colorR += 1;
            if (this.colorR > 255)
                this.colorR = 255;
            break;

            case OUT_R_DN:
            this.colorR -= 1;
            if (this.colorR < 0)
                this.colorR = 0;
            break;

            case OUT_G_UP:
            this.colorG += 1;
            if (this.colorG > 255)
                this.colorG = 255;
            break;

            case OUT_G_DN:
            this.colorG -= 1;
            if (this.colorG < 0)
                this.colorG = 0;
            break;

            case OUT_B_UP:
            this.colorB += 1;
            if (this.colorB > 255)
                this.colorB = 255;
            break;

            case OUT_B_DN:
            this.colorB -= 1;
            if (this.colorB < 0)
                this.colorB = 0;
            break;

            default:
            assert(false, 'invalid output action: ' + outAc);
        }

        this.itrCount++;
    }
}

// ===========================================================================

/// Canvas dimensions
var canvasWidth  = arguments[0]? Math.max(parseInt(arguments[0]), 400):600;
var canvasHeight = arguments[1]? Math.max(parseInt(arguments[1]), 400):600;

/// Current Turing machine
var machine;

// Last machine position
var lastPosX;
var lastPosY;

/// Number of updates per frame
var speed = 128;

/// Paused flag
var paused = false;

function newMachine()
{
    window.canvas.clear('#000000');

    machine = new Machine(
        4,              // Num states
        8,              // Num symbols
        256,            // Tape length
        canvasWidth,
        canvasHeight
    );

    lastPosX = machine.posX | 0;
    lastPosY = machine.posY | 0;
}

// Create the drawing window
var window = draw.Window(50, 50, canvasWidth, canvasHeight, 'Turing Turtle');

window.onKeypress(function(canvas, key)
{
    if (key === 'Right')
    {
        newMachine();
        print('new machine');
    }
    else if (key === 'Left')
    {
        window.canvas.clear('#000000');
        machine.reset();
    }
    else if (key === 'Up')
    {
        if (speed < 8192)
            speed <<= 1;
        print('speed=', speed);
    }
    else if (key === 'Down')
    {
        if (speed > 1)
            speed >>= 1;
        print('speed=', speed);
    }
    else if (key === 'space')
    {
        paused = !paused;
    }
});

window.onRender(function(canvas)
{
    // For each update to perform
    for (var i = 0; i < speed && !paused; ++i)
    {
        // Convert the current position to an integer value
        var posX = machine.posX | 0;
        var posY = machine.posY | 0;

        if (posX !== lastPosX || posY !== lastPosY)
        {
            // Set the current color
            canvas.setColor(machine.colorR, machine.colorG, machine.colorB);

            // Draw a point at the current coordinates
            canvas.drawPoint(posX, posY);

            // Update the last position
            lastPosX = posX;
            lastPosY = posY;
        }

        // Run the machine for one iteration
        machine.update(1);
    }

    // Clear a black rectangle at the bottom of the display
    canvas.setColor('#000000');
    canvas.fillRect(0, canvasHeight - 20, canvasWidth, 20);

    canvas.setColor('#FFFFFF');
    canvas.drawText(5, canvasHeight - 5, paused? "PAUSED":(posX + ',' + posY));
    canvas.drawText(canvasWidth - 240, canvasHeight - 5, 'itr count: ' + machine.itrCount);
});

// Set the random seed so we get a different machine on every startup
Math.setRandSeed((new Date()).getTime());

// Generate a new random Turing machine
newMachine();

// Clear the canvas
window.canvas.clear('#000000');

// Set the font to use
window.canvas.setFont(undefined, 18);

// Print basic instructions
window.canvas.setColor('#FFFFFF');
window.canvas.drawText(20, 30, "Right arrow for new drawing");
window.canvas.drawText(20, 60, "Left arrow to restart");
window.canvas.drawText(20, 90, "Up arrow to increase speed");
window.canvas.drawText(20, 120, "Down arrow to decrease speed");

// Show the drawing window
window.show();

