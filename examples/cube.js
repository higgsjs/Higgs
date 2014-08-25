/**
@fileOverview
3D perspective projection demo, draws a 3D wireframe cube in a 2D canvas.

usage: higgs cube.js

@author
Maxime Chevalier-Boisvert
*/

var draw = require('lib/draw');

require('lib/gl-matrix/common');
require('lib/gl-matrix/vec3');
require('lib/gl-matrix/mat4');

/// Canvas dimensions
var CANVAS_WIDTH = 512;
var CANVAS_HEIGHT = 512;

// Create the drawing window
var window = draw.Window(50, 50, CANVAS_WIDTH, CANVAS_HEIGHT, '3D Cube');

window.onRender(function(canvas)
{
    window.canvas.clear('#000000');

    // Set the current color
    canvas.setColor(255, 255, 255);

    var posMat = mat4.create();
    mat4.translate(posMat, posMat, vec3.fromValues(0, 0, -5));

    var xRotMat = mat4.create();
    mat4.rotateX(xRotMat, xRotMat, xAngle);

    var yRotMat = mat4.create();
    mat4.rotateY(yRotMat, yRotMat, yAngle);

    xAngle += Math.PI / 200;
    yAngle += Math.PI / 250;

    var tSegs = segments.map(
        function (v)
        {
            var v = vec3.clone(v);

            v = vec3.transformMat4(v, v, xRotMat);
            v = vec3.transformMat4(v, v, yRotMat);
            v = vec3.transformMat4(v, v, posMat);

            v = vec3.transformMat4(v, v, perMat);
            v = vec3.transformMat4(v, v, scaleMat);
            v = vec3.transformMat4(v, v, transMat);

            return v;
        }
    );

    for (var i = 0; i < tSegs.length; i += 2)
    {
        var v0 = tSegs[i];
        var v1 = tSegs[i+1];

        canvas.drawLine(
            v0[0]|0,
            v0[1]|0,
            v1[0]|0,
            v1[1]|0
        );
    }

    curTime = (new Date()).getTime() / 1000;
    var deltaTime = curTime - lastTime;
    lastTime = curTime;
    var fps = 1 / deltaTime;
    canvas.setColor('#FFFFFF');
    canvas.drawText(5, CANVAS_HEIGHT - 5, 'FPS: ' + fps.toFixed(1));
});

var segments = [

    // Front face
    vec3.fromValues(-1,+1,+1),
    vec3.fromValues(+1,+1,+1),
    vec3.fromValues(+1,+1,+1),
    vec3.fromValues(+1,-1,+1),
    vec3.fromValues(+1,-1,+1),
    vec3.fromValues(-1,-1,+1),
    vec3.fromValues(-1,-1,+1),
    vec3.fromValues(-1,+1,+1),

    // Back face
    vec3.fromValues(-1,+1,-1),
    vec3.fromValues(+1,+1,-1),
    vec3.fromValues(+1,+1,-1),
    vec3.fromValues(+1,-1,-1),
    vec3.fromValues(+1,-1,-1),
    vec3.fromValues(-1,-1,-1),
    vec3.fromValues(-1,-1,-1),
    vec3.fromValues(-1,+1,-1),

    // Joining segments
    vec3.fromValues(-1,+1,+1),
    vec3.fromValues(-1,+1,-1),
    vec3.fromValues(+1,+1,+1),
    vec3.fromValues(+1,+1,-1),
    vec3.fromValues(+1,-1,+1),
    vec3.fromValues(+1,-1,-1),
    vec3.fromValues(-1,-1,+1),
    vec3.fromValues(-1,-1,-1),
];

// Perspective matrix
var perMat = mat4.perspective(mat4.create(), 45, 1, 0.01, 100);

// Display scaling matrix
var scaleMat = mat4.scale(mat4.create(), mat4.create(), vec3.fromValues(CANVAS_WIDTH/2, -CANVAS_HEIGHT/2, 1));

// Display translation matrix
var transMat = mat4.translate(mat4.create(), mat4.create(), vec3.fromValues(CANVAS_WIDTH/2, CANVAS_WIDTH/2, 0));

// Current rotation angles
var xAngle = 0;
var yAngle = 0;

// Last frame update time
var lastTime;

// Clear the canvas
window.canvas.clear('#000000');

// Set the font to use
window.canvas.setFont(undefined, 18);

// Show the drawing window
window.show();

