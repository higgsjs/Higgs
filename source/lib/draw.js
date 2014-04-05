/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011, Maxime Chevalier-Boisvert. All rights reserved.
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

/**
lib/x - provides bindings to Xlib
NOTE: currently this provides just enough bindings for the drawing lib
*/

(function()
{

    var console = require('lib/console');

    /* DEPENDENCIES */

    // FFI
    var ffi = require('lib/ffi');
    var CNULL = ffi.nullPtr;
    var isNull = ffi.isNullPtr;
    var c = ffi.c;

    // STDlib
    var stdlib = require('lib/stdlib');
    var poll = ffi.c.poll;

    // Xlib
    var Xlib = require('lib/x');
    var XEventMask = Xlib.XEventMask;
    var XEvents = Xlib.XEvents;


    /**
    DrawError
    @constructor
    */
    function DrawError(message)
    {
        this.message = message;
    }
    DrawError.prototype = new Error();
    DrawError.prototype.constructor = DrawError;


    /**
    CanvasWindow
    Construct a new CanvasWindow object.
    */
    var CanvasWindowProto = {
        handle: CNULL,
        frame_rate: 400,
        render_funs: null,
        key_funs: null
    };

    function CanvasWindow(x, y, width, height, title)
    {
        var display;
        var screen;
        var root;
        var cw;

        // TODO: default to center screen?
        x = x || 50;
        y = y || 50;
        width = width || 500;
        height = height || 500;

        cw = Object.create(CanvasWindowProto);
        cw.display = display = Xlib.XOpenDisplay(CNULL);

        if (ffi.isNullPtr(display))
        {
            throw "Could not open X display";
        }

        // X Values
        cw.screen = screen = Xlib.XDefaultScreen(display);
        cw.root = root = Xlib.XRootWindow(display, screen);
        cw.black_pixel = Xlib.XBlackPixel(display, screen);
        cw.white_pixel = Xlib.XWhitePixel(display, screen);

        // X Window properties
        // TODO: default to center of screen
        // other better defaults?
        cw.x = x || 50;
        cw.y = y || 50;
        cw.width = width;
        cw.height = height;
        cw.title = title || "Higgs Canvas";

        // Create window
        cw.create();

        // Canvas
        cw.canvas = Canvas(display, screen, cw.id, width, height);

        // Events
        cw.render_funs = [];
        cw.key_funs = [];

        return cw;
    }

    /**
    Create the X Window
    */
    CanvasWindowProto.create = function()
    {
        var win;
        var title;
        var atom_name;
        var WM_DELTE_WINDOW;
        var display = this.display;
        var WDWAtom;

        // create window
        this.id = win = Xlib.XCreateSimpleWindow(
            display, this.root, this.x, this.y, this.width,
            this.height, 0, this.black_pixel, this.white_pixel
        );

        // set title (if any)
        if (this.title)
        {
            title = ffi.cstr(this.title);
            Xlib.XStoreName(display, win, title);
            c.free(title);
        }

        // select what events to listen to
        Xlib.XSelectInput(display, win,
                      XEventMask.ExposureMask | XEventMask.KeyPressMask);

        // we need to watch for the window closing
        atom_name = ffi.cstr("WM_DELETE_WINDOW");
        WM_DELTE_WINDOW = Xlib.XInternAtom(display, atom_name, 0);
        ffi.c.free(atom_name);
        WDWAtom = Xlib.AtomContainer();
        WDWAtom.set_atom(WM_DELTE_WINDOW);
        Xlib.XSetWMProtocols(display, win, WDWAtom.handle, 1);

        // set window to display
        Xlib.XMapWindow(display, win);
        Xlib.XFlush(display);
    };

    /**
    Close the X display
    */
    CanvasWindowProto.close = function()
    {
        Xlib.XCloseDisplay(this.display);
    };

    /**
    Register a listener for the render event
    */
    CanvasWindowProto.onRender = function(cb)
    {
        if (typeof cb === "function")
            this.render_funs.push(cb);
        else
            throw "Argument not a function in onRender";
    };

    /**
    Register a listener for a keypress event
    */
    CanvasWindowProto.onKeypress = function(cb)
    {
        if (typeof cb === "function")
            this.key_funs.push(cb);
        else
            throw "Argument not a function in onKeypress";
    };

    /**
    Show the window, and start the event loop
    */
    CanvasWindowProto.show = function()
    {
        // canvas/drawing
        var draw = true;
        var display = this.display;
        var canvas = this.canvas;
        var pixmap = canvas.id;
        var window = this.id;
        var frame_rate = this.frame_rate;
        // TODO: may need to check these each loop in case of resize
        var width = this.width;
        var height = this.height;
        // timing
        var work_time;
        var timeout;
        // events
        var event = Xlib.XEvent();
        var event_type;
        var key_sym;
        var key_name_c;
        var e = event.handle;
        // handlers
        var key_funs = this.key_funs;
        var render_funs = this.render_funs;
        var key_funs_i = 0;
        var render_funs_i = 0;

        // event loop
        while (draw)
        {
            // work time includes rendering and time handling events
            work_time = $ir_get_time_ms();

            key_funs_i = key_funs.length;
            render_funs_i = render_funs.length;

            // render
            while (render_funs_i > 0)
            {
                render_funs[--render_funs_i](canvas);
            }

            // Copy from Canvas buffer
            Xlib.XCopyArea(display, canvas.id,
                           window, canvas.gc,
                           0, 0, width, height, 0, 0
                          );

            // handle events
            while (Xlib.XPending(display) > 0)
            {
                // get event
                Xlib.XNextEvent(display, e);

                // dispatch on event type
                event_type = event.get_type();

                if (event_type === XEvents.Expose)
                {
                    // Copy from Canvas buffer
                    Xlib.XCopyArea(display, canvas.id,
                                   window, canvas.gc,
                                   0, 0, width, height, 0, 0
                                  );
                }
                else if (event_type === XEvents.KeyPress)
                {
                    // TODO: index? change to number?
                    key_sym = Xlib.XLookupKeysym(e, 0);
                    key_name_c = Xlib.XKeysymToString(key_sym);
                    key_name = ffi.string(key_name_c);

                    while (key_funs_i > 0)
                    {
                        key_funs[--key_funs_i](canvas, key_name);
                    }
                }
                else if (event_type === XEvents.ClientMessage)
                {
                    // TODO: Should check here for other client message types -
                    // for now we just care about the window closing
                    draw = false;
                }
            }

            // Calculate how long to wait
            work_time = $ir_get_time_ms() - work_time;
            timeout = 1000 / frame_rate - work_time;
            if (timeout < 0)
                timeout = 0;
            else if ($ir_is_f64(timeout))
                timeout = $ir_f64_to_i32(timeout);

            // Just sleep for a bit to not grind the CPU
            // TODO: eventually this should be more clever;
            // polling on the X fd or hooking into some higgs
            // event system so that all the libs like this can
            // be used together
            poll(CNULL, 0, timeout);
        }

        this.close();
    };



    /**
    Canvas
    An object that can be drawn on/has drawing functionality
     */

    var CanvasProto = {
    };

    function Canvas(display, screen, window, width, height)
    {

        var canvas = Object.create(CanvasProto);
        // TODO: make default font more ocnfigurable
        var font_name_c = ffi.cstr("-*-helvetica-*-r-*-*-18-*-*-*-*-*-*-*");

        // cleanup
        canvas.id = Xlib.XCreatePixmap(display, window,
                                       width, height,
                                       Xlib.XDefaultDepth(display, screen)
                                      );
        canvas.display = display;
        canvas.screen = screen;
        canvas.window = window;
        canvas.width = width;
        canvas.height = height;
        canvas.colormap = Xlib.XDefaultColormap(display, 0);
        canvas.colors = Object.create(null);
        canvas.gc = Xlib.XDefaultGC(display, screen);
        canvas.font = Xlib.XFontStruct(Xlib.XLoadQueryFont(display, font_name_c));
        Xlib.XSetFont(display, canvas.gc, canvas.font.get_fid());

        c.free(font_name_c);
        return canvas;
    }

    /**
    Clear the canvas - just a shortcut for fillRect for the entire canvas
    */
    CanvasProto.clear = function(color, g, b)
    {
        if (arguments.length === 1)
            this.setColor(color);
        else
            this.setColor(color, g, b);
        this.fillRect(0, 0, this.width, this.height);
    };

    /**
    Set drawing color for a Canvas, accepts a hex color string
    */
    CanvasProto.setColor = function(color, g, b)
    {
        var gc = this.gc;
        var display = this.display;
        var colormap;
        var XColor;
        var color_string_c;
        var color_string;

        // check whether r,g,b values were passed individually or as a string
        if (typeof b === "number")
        {
            color_string = "#"  + color.toString(16);
            if (color_string.length === 2)
                color_string += "0";
            color_string += g.toString(16);
            if (color_string.length === 4)
                color_string += "0";
            color_string += b.toString(16);
            if (color_string.length === 6)
                color_string += "0";
        }
        else if (color && color[0] == "#")
            color_string = color;
        else
            throw new DrawError("Invalid argument in setFG");

        // Check if we have a graphics context for this color
        XColor = this.colors[color_string];
        if (XColor)
        {
            Xlib.XSetForeground(display, gc, XColor.get_pixel());
            return true;
        }

        // .. if not we need to create one
        color_string_c = ffi.cstr(color_string);
        XColor = Xlib.XColor();
        colormap = this.colormap;

        Xlib.XParseColor(display, colormap, color_string_c, XColor.handle);
        Xlib.XAllocColor(display, colormap, XColor.handle);

        Xlib.XSetForeground(display, gc, XColor.get_pixel());

        // TODO: error checking?

        // Cleanup
        c.free(color_string_c);
        this.colors[color_string] = XColor;
        return true;
    };



    /**
    drawPoint - draw a point
    */
    CanvasProto.drawPoint = function(x, y)
    {
        Xlib.XDrawPoint(this.display, this.id, this.gc, x, y);
    };

    /**
    drawLine - draw a line
    */
    CanvasProto.drawLine = function(x1, y1, x2, y2)
    {
        Xlib.XDrawLine(this.display, this.id, this.gc, x1, y1, x2, y2);
    };

    /**
    drawRect - draw a rectangle
    */
    CanvasProto.drawRect = function(x, y, width, height)
    {
        Xlib.XDrawRectangle(this.display, this.id, this.gc, x, y, width, height);
    };

    /**
    drawArc - draw an arc
    */
    CanvasProto.drawArc = function(x, y, width, height, angle1, angle2)
    {
        Xlib.XDrawArc(this.display, this.id, this.gc, x, y, width, height, angle1, angle2);
    };

    /**
    drawCircle - draw a circle
    */
    CanvasProto.drawCircle = function(x, y, radius)
    {
        var diameter = radius * 2;
        Xlib.XDrawArc(this.display, this.id, this.gc,
                      x - radius, y - radius, diameter, diameter, 0, 23040);
    };

    /**
    fillRect - fill a rectangle
    */
    CanvasProto.fillRect = function(x, y, width, height)
    {
        Xlib.XFillRectangle(this.display, this.id,
                            this.gc, x, y, width, height);
    };

    /**
    fillCircle - fill a circle
    */
    CanvasProto.fillCircle = function(x, y, radius)
    {
        var diameter = radius * 2;
        Xlib.XFillArc(this.display, this.id, this.gc,
                      x - radius, y - radius, diameter, diameter, 0, 23040);
    };

    /**
    setFont - set the font to use
    */
    CanvasProto.setFont = function()
    {

    };

    /**
    drawText - draw some text
    */
    CanvasProto.drawText = function(x, y, text)
    {
        var text_c = ffi.cstr(text);
        var text_l = text.length; // TODO: wchars
        var TextItem = Xlib.XTextItem();
        TextItem.set_chars(text_c);
        TextItem.set_nchars(text_l);
        TextItem.set_delta(0);
        TextItem.set_font(this.font.get_fid());


        Xlib.XDrawText(this.display, this.id, this.gc, x, y, TextItem.handle, 1);
        /*
        Display *display;
        Drawable d;
        GC gc;
        int x, y;
        XTextItem *items;
        int nitems;
        */
        
        c.free(text_c);
    };


    /**
    EXPORTS
    */

    exports = {
        CanvasWindow : CanvasWindow
    };

})();
