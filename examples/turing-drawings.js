/**
@fileOverview
Turing Drawings uses randomly generated Turing machines to produce drawings
on a canvas, as a form of generative art. The typical Turing machine
formulation manipulates symbols on a one-dimensional tape. Turing Drawings
uses machines that operate on a finite 2D grid, where each grid cell can
contain one symbol which corresponds to a color value. This 2D grid is
represented in the canvas shown at the left, which is dynamically updated
as the Turing machine iterates.

usage: higgs turing-drawings.js

or:    higgs turing-drawings.js -- <canvas_width> <canvas_height>

@author
Maxime Chevalier-Boisvert
*/

// Import required libraries
var draw = require('lib/draw');
var image = require('lib/image');
var rnd = require('lib/random');

// ===========================================================================

/**
Map of symbols (numbers) to colors
*/
var colorMap = [
    255,0  ,0  ,    // Initial symbol color
    0  ,0  ,0  ,    // Black
    255,255,255,    // White
    0  ,255,0  ,    // Green
    0  ,0  ,255,    // Blue
    255,255,0  ,
    0  ,255,255,
    255,0  ,255,
];

var colorMap = [
    '#FF0000',  // Initial symbol color
    '#000000',  // Black
    '#FFFFFF',  // White
    '#00FF00',  // Green
    '#0000FF',  // Blue
    '#FFFF00',
    '#00FFFF',
    '#FF00FF',
];

/// Turing Machine actions
var ACTION_LEFT  = 0;
var ACTION_RIGHT = 1;
var ACTION_UP    = 2;
var ACTION_DOWN  = 3;
var NUM_ACTIONS  = 4;

/*
N states, one start state
K symbols
4 actions (left, right up, down)

N x K -> N x K x A
*/
function Machine(numStates, numSymbols, mapWidth, mapHeight)
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

    /// Image dimensions
    this.mapWidth = mapWidth;
    this.mapHeight = mapHeight;

    /// Transition table
    this.table = new Array(numStates * numSymbols * 3);

    /// Map (2D tape)
    this.map = new Array(mapWidth * mapHeight); 

    // Generate random transitions
    for (var st = 0; st < numStates; ++st)
    {
        for (var sy = 0; sy < numSymbols; ++sy)
        {
            this.setTrans(
                st,
                sy,
                rnd.index(numStates),
                rnd.index(numSymbols),
                rnd.index(NUM_ACTIONS)
            );
        }
    }

    // Initialize the state
    this.reset();
}

Machine.prototype.setTrans = function (st0, sy0, st1, sy1, ac1)
{
    var idx = (this.numStates * sy0 + st0) * 3;

    this.table[idx + 0] = st1;
    this.table[idx + 1] = sy1;
    this.table[idx + 2] = ac1;
}

Machine.prototype.reset = function ()
{
    /// Start state
    this.state = 0;

    /// Top-left corner
    this.posX = 0;
    this.posY = 0;

    /// Iteration count
    this.itrCount = 0;

    // Initialize the image
    for (var i = 0; i < this.map.length; ++i)
        this.map[i] = 0;
}

Machine.prototype.toString = function ()
{
    var str = this.numStates + ',' + this.numSymbols;

    for (var i = 0; i < this.table.length; ++i)
        str += ',' + this.table[i];

    return str;
}

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

Machine.prototype.update = function (numItrs)
{
    for (var i = 0; i < numItrs; ++i)
    {
        var sy = this.map[this.mapWidth * this.posY + this.posX];
        var st = this.state;

        var idx = (this.numStates * sy + st) * 3;
        var st = this.table[idx + 0];
        var sy = this.table[idx + 1];
        var ac = this.table[idx + 2];

        // Update the current state
        this.state = st;

        // Write the new symbol
        this.map[this.mapWidth * this.posY + this.posX] = sy;

        // Perform the transition action
        switch (ac)
        {
            case ACTION_LEFT:
            this.posX += 1;
            if (this.posX >= this.mapWidth)
                this.posX -= this.mapWidth;
            break;

            case ACTION_RIGHT:
            this.posX -= 1;
            if (this.posX < 0)
                this.posX += this.mapWidth;
            break;

            case ACTION_UP:
            this.posY -= 1;
            if (this.posY < 0)
                this.posY += this.mapHeight;
            break;

            case ACTION_DOWN:
            this.posY += 1;
            if (this.posY >= this.mapHeight)
                this.posY -= this.mapHeight;
            break;

            default:
            error('invalid action: ' + ac);
        }

        /*
        assert (
            this.posX >= 0 && this.posX < this.mapWidth,
            'invalid x position'
        );

        assert (
            this.posY >= 0 && this.posY < this.mapHeight,
            'invalid y position'
        );

        assert (
            this.state >= 0 && this.state < this.numStates,
            'invalid state'
        );
        */

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
        if (speed < 0xFFFFFF)
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
    // Last symbol seen
    var lastSym;

    // For each update to perform
    for (var i = 0; i < speed && !paused; ++i)
    {
        // Convert the current position to an integer value
        var posX = machine.posX;
        var posY = machine.posY;

        // Set the current color
        var sym = machine.map[machine.mapWidth * posY + posX];
        if (sym !== lastSym)
            canvas.setColor(colorMap[sym]);

        // Draw a point at the current coordinates
        canvas.drawPoint(posX, posY);

        // Run the machine for one iteration
        machine.update(1);

        lastSym = sym;
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

