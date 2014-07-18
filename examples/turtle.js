/**
@fileOverview
Program to produce drawings using a turtle plotter controlled
by a randonly generated Turing machine.

usage: higgs turtle.js

@author
Maxime Chevalier-Boisvert
*/

// ===========================================================================

/**
Generate a random integer within [a, b]
*/
function randomInt(a, b)
{
    /*
    assert (
        isInt(a) && isInt(b) && a <= b,
        'invalid params to randomInt'
    );
    */

    var range = b - a;

    var rnd = a + Math.floor(Math.random() * (range + 1));

    return rnd;
}

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
                randomInt(0, numStates - 1),
                randomInt(1, numSymbols - 1),
                randomInt(0, NUM_TAPE_ACTIONS - 1),
                randomInt(0, NUM_OUT_ACTIONS - 1)
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
    this.xPos = this.canvasWidth / 2;
    this.yPos = this.canvasHeight / 2;

    /// Current color, initially white
    this.rColor = 255;
    this.gColor = 255;
    this.bColor = 255;

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
            this.xPos += vecX[this.dir];
            this.yPos += vecY[this.dir];
            if (this.xPos < 0)
                this.xPos += this.canvasWidth;
            if (this.xPos >= this.canvasWidth)
                this.xPos -= this.canvasWidth;
            if (this.yPos < 0)
                this.yPos += this.canvasHeight;
            if (this.yPos >= this.canvasHeight)
                this.yPos -= this.canvasHeight;
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
            this.rColor += 1;
            if (this.rColor > 255)
                this.rColor = 255;
            break;

            case OUT_R_DN:
            this.rColor -= 1;
            if (this.rColor < 0)
                this.rColor = 0;
            break;

            case OUT_G_UP:
            this.gColor += 1;
            if (this.gColor > 255)
                this.gColor = 255;
            break;

            case OUT_G_DN:
            this.gColor -= 1;
            if (this.gColor < 0)
                this.gColor = 0;
            break;

            case OUT_B_UP:
            this.bColor += 1;
            if (this.bColor > 255)
                this.bColor = 255;
            break;

            case OUT_B_DN:
            this.bColor -= 1;
            if (this.bColor < 0)
                this.bColor = 0;
            break;

            default:
            assert(false, 'invalid output action: ' + outAc);
        }

        this.itrCount++;
    }
}

// TODO: use toJSON
/*
Machine.prototype.toString = function ()
{
    var str = this.numStates + ',' + this.numSymbols;

    for (var i = 0; i < this.table.length; ++i)
        str += ',' + this.table[i];

    return str;
}
*/

/*
Machine.fromString = function (str, mapWidth, mapHeight)
{
    console.log(str);

    var nums = str.split(',').map(Number);

    numStates  = nums[0];
    numSymbols = nums[1];

    console.log('num states: ' + numStates);
    console.log('num symbols: ' + numSymbols);

    assert (
        numStates > 0 &&
        numSymbols > 0,
        'invalid input string'
    );

    var prog = new Machine(numStates, numSymbols, mapWidth, mapHeight);

    assert (
        prog.table.length === nums.length - 2,
        'invalid transition table length'
    );

    for (var i = 0; i < prog.table.length; ++i)
        prog.table[i] = nums[i+2];

    return prog;
}
*/

// ===========================================================================

var draw = require('lib/draw');
var image = require('lib/image');

/// Canvas dimensions
var CANVAS_WIDTH = 512;
var CANVAS_HEIGHT = 512;

/// Current Turing machine
var machine;

function newMachine()
{
    window.canvas.clear("#000000");

    machine = new Machine(
        8,              // Num states
        8,              // Num symbols
        128,            // Tape length
        CANVAS_WIDTH,
        CANVAS_HEIGHT
    );
}

// Create the drawing window
var window = draw.Window(50, 50, CANVAS_WIDTH, CANVAS_HEIGHT, "Turing Turtle");

window.onKeypress(function(canvas, key)
{
    if (key === "Right")
        newMachine();

    /*
    else if (x > 50 && key === "Left")
        x -= 10;
    else if (y < 450 && key === "Down")
        y += 10;
    else if (y > 50 && key === "Up")
        y -= 10;
    */
});

window.onRender(function(canvas)
{
    // TODO: speed control
    for (var i = 0; i < 50; ++i)
    {
        // Set the current color
        canvas.setColor(machine.rColor, machine.gColor, machine.bColor);

        // Convert the current position to an integer value
        var xPos = machine.xPos | 0;
        var yPos = machine.yPos | 0;

        // Draw a point at the current coordinates
        canvas.drawPoint(xPos, yPos);

        machine.update(1);
    }

    // Clear a black rectangle at the bottom of the display
    canvas.setColor("#000000");
    canvas.fillRect(0, CANVAS_HEIGHT - 20, CANVAS_WIDTH, 20);

    canvas.setColor("#FFFFFF");
    canvas.drawText(5, CANVAS_HEIGHT - 5, xPos + "," + yPos);
    canvas.drawText(CANVAS_WIDTH - 200, CANVAS_HEIGHT - 5, "itr count: " + machine.itrCount);
});

// Generate a new random Turing machine
newMachine();

// Clear the canvas
window.canvas.clear("#000000");

// Set the font to use
window.canvas.setFont(undefined, 18);

// Show the drawing window
window.show();

