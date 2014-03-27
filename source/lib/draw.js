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
        var wptrl
        var title;
        var atom_name
        var WM_DELTE_WINDOW;
        var display = this.display;
        var WDWAtom;
        
        // create window
        this.handle = wptr = Xlib.XCreateSimpleWindow(
                                            display, this.root, this.x, this.y, this.width,
                                            this.height, 0, this.black_pixel, this.black_pixel
                                            );
    
        // set title (if any)
        if (this.title)
        {
            title = ffi.cstr(this.title);
            Xlib.XStoreName(display, wptr, title);
            c.free(title);
        }
        
        // select what events to listen to
        Xlib.XSelectInput(display, wptr,
                      XEventMask.ExposureMask | XEventMask.KeyPressMask);

        // we need to watch for the window closing
        atom_name = ffi.cstr("WM_DELETE_WINDOW");
        WM_DELTE_WINDOW = Xlib.XInternAtom(display, atom_name, 0);
        ffi.c.free(atom_name);
        WDWAtom = Xlib.AtomContainer();
        WDWAtom.set_atom(WM_DELTE_WINDOW);
        Xlib.XSetWMProtocols(display, wptr, WDWAtom.handle, 1);
        
        // set window to display
        Xlib.XMapWindow(display, wptr);
    }
    
    CanvasWindowProto.close = function()
    {
        Xlib.XCloseDisplay(this.display);
    }
    
    CanvasWindowProto.show = function()
    {
        var display = this.display;
        // events
        // TODO: move to CanvasWindow object?
        var event = Xlib.XEvent();
        var e = event.handle;

        /* main loop */
        while (true)
        {
            // get
            Xlib.XNextEvent(display, e);
            var event_type = event.get_type();
            
            if (event_type === XEvents.Expose)
            {
                this.draw();
            }
            // TODO: keyboard events, etc
            else if (event_type === XEvents.ClientMessage)
            {
                // TODO: Should check here for other client message types - 
                // for now we just care about the window closing
                break;
            }
        }
        
        this.close();
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
        
        window.x = x;
        window.y = y;
        window.width = width;
        window.height = height;
        window.title = title;
        
        return window;
    }

    function Canvas()
    {
        
    }
    
})();