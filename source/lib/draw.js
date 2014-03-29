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
    
    // Xlib
    var Xlib = require('lib/x');
    var XEventMask = Xlib.XEventMask;
    var XEvents = Xlib.XEvents;
    
    
    var CanvasWindowProto = {
        handle: CNULL
    };
    
    // Dummy draw function
    CanvasWindowProto.draw = function(){};
    
    CanvasWindowProto.create = function()
    {
        var win;
        var title;
        var atom_name
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
    }
    
    CanvasWindowProto.close = function()
    {
        Xlib.XCloseDisplay(this.display);
    }
    
    
    /**
    Wrapper object for a X window
    */
    function CanvasWindow(x, y, width, height, title)
    {
        var display;
        var screen;
        var root;
        
        window = Object.create(CanvasWindowProto);
        window.display = display = Xlib.XOpenDisplay(CNULL);

        if (ffi.isNullPtr(display))
        {
            throw "Could not open X display";
        }
        
        window.screen = screen = Xlib.XDefaultScreen(display);
        window.root = root = Xlib.XRootWindow(display, screen);
        window.black_pixel = Xlib.XBlackPixel(display, screen);
        window.white_pixel = Xlib.XWhitePixel(display, screen);
        
        window.x = x || 50;
        window.y = y || 50;
        window.width = width || 500;
        window.height = height || 500;
        window.title = title || "Higgs Canvas";
        
        return window;
    }

    
    var CanvasProto = {
    };
    
    CanvasProto.setFG = function(color)
    {
        var gc = this.colorGCs[color];
        var colormap;
        var window = this.window;
        var display = window.display;
        var XColor;
        var color_name;

        if (gc)
        {
            this.gc = gc;
            return true;
        }
        
        color_name = ffi.cstr(color);
        XColor = Xlib.XColor();
        colormap = this.colormap;
        
        gc = Xlib.XCreateGC(display, window.id, 0, 0);
        
        
        Xlib.XParseColor(display, colormap, color_name, XColor.handle);
        Xlib.XAllocColor(display, colormap, XColor.handle);
        
        Xlib.XSetForeground(display, gc, XColor.get_pixel());
        
        c.free(color_name);
        //c.free(XColor);

        this.gc = gc;
        return true;
    }
    
    CanvasProto.fillRect = function(x, y, w, h)
    {
        var window = this.window;
        Xlib.XFillRectangle(window.display, window.id,
                       this.gc, x, y, w, h);
    }
    
    CanvasProto.createGC = function()
    {
        
    }
    
    CanvasProto.display = function(draw_fun)
    {
        var window = this.window;
        var display = window.display;
        var draw = (typeof draw_fun === "function");

        
        // events
        var event = Xlib.XEvent();
        var e = event.handle;

        /* main loop */
        while (draw)
        {
            while (Xlib.XPending(display) > 0)
            {
                // get
                Xlib.XNextEvent(display, e);
                var event_type = event.get_type();
            
                if (event_type === XEvents.Expose)
                {
                    console.log("expose")
                    // TODO: pass args, more stuff
                    draw_fun(this);
                }
                // TODO: keyboard events, etc
                else if (event_type === XEvents.ClientMessage)
                {
                    // TODO: Should check here for other client message types - 
                    // for now we just care about the window closing
                    draw = false;
                }
            }
            
            draw_fun(this);
        }
        
        this.close();
    }
    
    function Canvas()
    {
        var canvas = Object.create(CanvasProto);
        var window;

        // TODO: move this to .display?
        canvas.window = window = CanvasWindow(100, 100, 500, 500,"higgs");
        window.create();
        
        canvas.colormap = Xlib.XDefaultColormap(window.display, 0);
        
        canvas.colorGCs = Object.create(null);
        canvas.gc = Xlib.XDefaultGC(window.display, window.screen);
        
        return canvas;
    }
    
    var mycanvas = Canvas();
    mycanvas.display(function(canvas)
    {
        canvas.setFG("#00FF00");
        canvas.fillRect(10, 10, 100, 100);
        canvas.setFG("#00FFFF");
        canvas.fillRect(120, 120, 100, 100);
    })
})();