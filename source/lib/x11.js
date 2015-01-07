/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2014, Maxime Chevalier-Boisvert. All rights reserved.
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
lib/x11 - provides bindings to Xlib
NOTE: currently this provides just enough bindings for the drawing lib
*/
(function(exports)
{
    var ffi = require('lib/ffi');
    var c = ffi.c;
    var CNULL = ffi.nullPtr;

    var console = require('lib/console');

    /**
    XLibError
    @constructor
    */
    function XlibError(message)
    {
        this.message = message;
    }
    XlibError.prototype = new Error();
    XlibError.prototype.constructor = XlibError;

    var Xlib = ffi.FFILib("X11");

    Xlib.cdef(`
        /* define'd aliases */
        typedef int Status;
        typedef int Bool;

              /* random */
        typedef char *XPointer;
        typedef unsigned long wchar_t;

        /*
        dummy decs for types we don't care about
        If you care about one of these, remove it and add
        an actual dec in the appropriate spot
        */
        typedef struct _XExtData XExtData;
        typedef struct _ScreenFormat ScreenFormat;
        typedef struct _Depth Depth;
        typedef struct _Visual Visual;
        typedef struct _XGCValues XGCValues;
        typedef struct _XSetWindowAttributes XSetWindowAttributes;
        typedef struct _XHostAddress XHostAddress;
        typedef struct _XExtCodes XExtCodes;
        typedef struct _XIM *XIM;
        typedef struct _XIC *XIC;
        typedef struct _XErrorEvent XErrorEvent;
        typedef struct _XPixmapFormatValues XPixmapFormatValues;
        typedef struct _XWindowChanges XWindowChanges;
        typedef struct _XKeyboardControl XKeyboardControl;
        typedef struct _XModifierKeymap XModifierKeymap;
        typedef struct _XKeyboardState XKeyboardState;
        typedef struct _XWindowAttributes XWindowAttributes;
        typedef struct _XImage XImage;
        typedef struct _XMappingEvent XMappingEvent;
        typedef struct _XmbTextItem XmbTextItem;
        typedef struct _XwcTextItem XwcTextItem;
        typedef struct _XGenericEventCookie XGenericEventCookie;
        typedef struct _XFontProp XFontProp;


        /* Resources */
        typedef unsigned long XID;
        typedef unsigned long Mask;
        typedef unsigned long Atom; /* Also in Xdefs.h */
        typedef unsigned long VisualID;
        typedef unsigned long Time;
        typedef XID Window;
        typedef XID Drawable;
        typedef XID Font;
        typedef XID Pixmap;
        typedef XID Cursor;
        typedef XID Colormap;
        typedef XID GContext;
        typedef XID KeySym;

        typedef unsigned char KeyCode;

        /*
         * Graphics context.  The contents of this structure are implementation
         * dependent.  A GC should be treated as opaque by application code.
         */
        typedef struct _XGC *GC;

        /* Screen */
        typedef struct {
            XExtData *ext_data; /* hook for extension to hang data */
            struct _XDisplay *display; /* back pointer to display structure */
            Window root;    /* Root window id. */
            int width, height;  /* width and height of screen */
            int mwidth, mheight;    /* width and height of  in millimeters */
            int ndepths;    /* number of depths possible */
            Depth *depths;  /* list of allowable depths on the screen */
            int root_depth; /* bits per pixel */
            Visual *root_visual;    /* root visual */
            GC default_gc;  /* GC for the root root visual */
            Colormap cmap;  /* default color map */
            unsigned long white_pixel;
            unsigned long black_pixel;  /* White and Black pixel values */
            int max_maps, min_maps; /* max and min color maps */
            int backing_store;  /* Never, WhenMapped, Always */
            Bool save_unders;
            long root_input_mask;   /* initial root input mask */
        } Screen;
        
        /* Display */
        typedef struct _XDisplay
        {
            XExtData *ext_data; /* hook for extension to hang data */
            struct _XPrivate *private1;
            int fd; /* Network socket. */
            int private2;
            int proto_major_version;/* major version of server's X protocol */
            int proto_minor_version;/* minor version of servers X protocol */
            char *vendor;   /* vendor of the server hardware */
            XID private3;
            XID private4;
            XID private5;
            int private6;
            XID (*resource_alloc)(  /* allocator function */
                    struct _XDisplay*
            );
            int byte_order; /* screen byte order, LSBFirst, MSBFirst */
            int bitmap_unit;    /* padding and data requirements */
            int bitmap_pad; /* padding requirements on bitmaps */
            int bitmap_bit_order;   /* LeastSignificant or MostSignificant */
            int nformats;   /* number of pixmap formats in list */
            ScreenFormat *pixmap_format;    /* pixmap format list */
            int private8;
            int release;    /* release of the server */
            struct _XPrivate *private9, *private10;
            int qlen;   /* Length of input event queue */
            unsigned long last_request_read; /* seq number of last event read */
            unsigned long request;  /* sequence number of last request. */
            XPointer private11;
            XPointer private12;
            XPointer private13;
            XPointer private14;
            unsigned max_request_size; /* maximum number 32 bit words in request*/
            struct _XrmHashBucketRec *db;
            int (*private15)(
                    struct _XDisplay*
                    );
            char *display_name; /* "host:display" string used on this connect*/
            int default_screen; /* default screen for operations */
            int nscreens;   /* number of screens on this server*/
            Screen *screens;    /* pointer to list of screens */
            unsigned long motion_buffer;    /* size of motion buffer */
            unsigned long private16;
            int min_keycode;    /* minimum defined keycode */
            int max_keycode;    /* maximum defined keycode */
            XPointer private17;
            XPointer private18;
            int private19;
            char *xdefaults;    /* contents of defaults from server */
            /* there is more to this structure, but it is private to Xlib */
        } Display;

        /*
         * Definitions of specific events.
         */
        typedef struct {
            int type;   /* of event */
            unsigned long serial;   /* # of last request processed by server */
            Bool send_event;    /* true if this came from a SendEvent request */
            Display *display;   /* Display the event was read from */
            Window window;        /* "event" window it is reported relative to */
            Window root;        /* root window that the event occurred on */
            Window subwindow;   /* child window */
            Time time;  /* milliseconds */
            int x, y;   /* pointer x, y coordinates in event window */
            int x_root, y_root; /* coordinates relative to root */
            unsigned int state; /* key or button mask */
            unsigned int keycode;   /* detail */
            Bool same_screen;   /* same screen flag */
        } XKeyEvent;
        typedef XKeyEvent XKeyPressedEvent;
        typedef XKeyEvent XKeyReleasedEvent;
        
        /*
         * this union is defined so Xlib can always use the same sized
         * event structure internally, to avoid memory fragmentation.
         */
        typedef union _XEvent {
            int type;   /* must not be changed; first element */
            XKeyEvent xkey;
            /* NOTE: TODO: snipped: stuff we don't care about,
                add it back as appropriate */
            long pad[24];
        } XEvent;
        
        
        /*
         * Data structure used by color operations
         */
        typedef struct {
            unsigned long pixel;
            unsigned short red, green, blue;
            char flags;  /* do_red, do_green, do_blue */
            char pad;
        } XColor;
        
        /*
         * Data structures for graphics operations.  On most machines, these are
         * congruent with the wire protocol structures, so reformatting the data
         * can be avoided on these architectures.
         */
        
        typedef struct {
            short x1, y1, x2, y2;
        } XSegment;
        
        typedef struct {
            short x, y;
        } XPoint;
        
        typedef struct {
            short x, y;
            unsigned short width, height;
        } XRectangle;
        
        typedef struct {
            short x, y;
            unsigned short width, height;
            short angle1, angle2;
        } XArc;
        
        /*
         * PolyText routines take these as arguments.
         */
        
        typedef struct _XChar2b XChar2b;
        
              typedef struct _XTextItem16 XTextItem16;

        /*
         * per character font metric information.
         */
        typedef struct {
            short lbearing; /* origin to left edge of raster */
            short rbearing; /* origin to right edge of raster */
            short width; /* advance to next char's origin */
            short ascent; /* baseline to top edge of raster */
            short descent; /* baseline to bottom edge of raster */
            unsigned short attributes; /* per char flags (not predefined) */
        } XCharStruct;

        typedef struct {
            XExtData *ext_data;    /* hook for extension to hang data */
            Font        fid;            /* Font id for this font */
            unsigned direction;    /* hint about direction the font is painted */
            unsigned min_char_or_byte2;/* first character */
            unsigned max_char_or_byte2;/* last character */
            unsigned min_byte1;   /* first row that exists */
            unsigned max_byte1;    /* last row that exists */
            Bool all_chars_exist;/* flag if all characters have non-zero size*/
            unsigned default_char;    /* char to print for undefined character */
            int      n_properties;   /* how many properties there are */
            XFontProp *properties;    /* pointer to array of additional properties*/
            XCharStruct min_bounds;    /* minimum bounds over all existing char*/
            XCharStruct max_bounds;    /* maximum bounds over all existing char*/
            XCharStruct *per_char;    /* first_char to last_char information */
            int    ascent;     /* log. extent above baseline for spacing */
            int    descent;    /* log. descent below baseline for spacing */
        } XFontStruct;              
        
        
        typedef union { Display *display;
                        GC gc;
                        Visual *visual;
                        Screen *screen;
                        ScreenFormat *pixmap_format;
                        XFontStruct *font; } XEDataObject;
        
        typedef struct {
            XRectangle      max_ink_extent;
            XRectangle      max_logical_extent;
        } XFontSetExtents;
        
        typedef struct _XOM *XOM;
        typedef struct _XOC *XOC;
        typedef struct _XOC *XFontSet;
        
        typedef void (*XIDProc)(
          Display*,
          XPointer,
          XPointer
        );
        

        /*
         * PolyText routines take these as arguments.
         */
        typedef struct {
            char *chars;    /* pointer to string */
            int nchars;    /* number of characters */
            int delta;    /* delta between strings */
            Font font;    /* font to print it in, None don't change */
        } XTextItem;

        XFontStruct *XLoadQueryFont(
            Display*    /* display */,
            const char*    /* name */
        );

        XFontStruct *XQueryFont(
            Display*    /* display */,
            XID    /* font_ID */
        );
              
        /*
        * X function declarations.
        */
        
        Display *XOpenDisplay(
            const char*  /* display_name */
        );

        void XrmInitialize(
           void
        );
   
        char *XFetchBytes(
           Display*    /* display */,
           int*    /* nbytes_return */
        );
       
        char *XFetchBuffer(
           Display*    /* display */,
           int*    /* nbytes_return */,
           int      /* buffer */
        );
   
        char *XGetAtomName(
           Display*    /* display */,
           Atom    /* atom */
        );
       
       Status XGetAtomNames(
           Display*    /* dpy */,
           Atom*    /* atoms */,
           int      /* count */,
           char**    /* names_return */
        );
       
        char *XGetDefault(
           Display*    /* display */,
           const char*  /* program */,
           const char*  /* option */
        );
       
       char *XDisplayName(
           const char*  /* string */
        );
   
        char *XKeysymToString(
           KeySym    /* keysym */
        );
        
        Atom XInternAtom(
            Display*    /* display */,
            const char*  /* atom_name */,
            Bool    /* only_if_exists */
        );
        
        Status XInternAtoms(
            Display*    /* dpy */,
            char**    /* names */,
            int      /* count */,
            Bool    /* onlyIfExists */,
            Atom*    /* atoms_return */
        );
        
        Colormap XCopyColormapAndFree(
            Display*    /* display */,
            Colormap    /* colormap */
        );
        
        Colormap XCreateColormap(
            Display*    /* display */,
            Window    /* w */,
            Visual*    /* visual */,
            int      /* alloc */
        );
        
        Cursor XCreatePixmapCursor(
            Display*    /* display */,
            Pixmap    /* source */,
            Pixmap    /* mask */,
            XColor*    /* foreground_color */,
            XColor*    /* background_color */,
            unsigned int  /* x */,
            unsigned int  /* y */
        );
        
        Cursor XCreateGlyphCursor(
            Display*    /* display */,
            Font    /* source_font */,
            Font    /* mask_font */,
            unsigned int  /* source_char */,
            unsigned int  /* mask_char */,
            XColor const *  /* foreground_color */,
            XColor const *  /* background_color */
        );

        Cursor XCreateFontCursor(
            Display*    /* display */,
            unsigned int  /* shape */
        );
        
        Font XLoadFont(
            Display*    /* display */,
            const char*  /* name */
        );
        
        GC XCreateGC(
            Display*    /* display */,
            Drawable    /* d */,
            unsigned long  /* valuemask */,
            XGCValues*    /* values */
        );
        
        GContext XGContextFromGC(
            GC      /* gc */
        );
        
        void XFlushGC(
            Display*    /* display */,
            GC      /* gc */
        );
        
        Pixmap XCreatePixmap(
            Display*    /* display */,
            Drawable    /* d */,
            unsigned int  /* width */,
            unsigned int  /* height */,
            unsigned int  /* depth */
        );

        Pixmap XCreateBitmapFromData(
            Display*    /* display */,
            Drawable    /* d */,
            const char*  /* data */,
            unsigned int  /* width */,
            unsigned int  /* height */
        );
            
        Pixmap XCreatePixmapFromBitmapData(
            Display*    /* display */,
            Drawable    /* d */,
            char*    /* data */,
            unsigned int  /* width */,
            unsigned int  /* height */,
            unsigned long  /* fg */,
            unsigned long  /* bg */,
            unsigned int  /* depth */
        );
        
        Window XCreateSimpleWindow(
            Display*    /* display */,
            Window    /* parent */,
            int      /* x */,
            int      /* y */,
            unsigned int  /* width */,
            unsigned int  /* height */,
            unsigned int  /* border_width */,
            unsigned long  /* border */,
            unsigned long  /* background */
        );
        
        Window XGetSelectionOwner(
           Display*    /* display */,
           Atom    /* selection */
        );
        
        Window XCreateWindow(
            Display*    /* display */,
            Window    /* parent */,
            int      /* x */,
            int      /* y */,
            unsigned int  /* width */,
            unsigned int  /* height */,
            unsigned int  /* border_width */,
            int      /* depth */,
            unsigned int  /* class */,
            Visual*    /* visual */,
            unsigned long  /* valuemask */,
            XSetWindowAttributes*  /* attributes */
        );
        
        Colormap *XListInstalledColormaps(
            Display*    /* display */,
            Window    /* w */,
            int*    /* num_return */
        );
        
        char **XListFonts(
            Display*    /* display */,
            const char*  /* pattern */,
            int      /* maxnames */,
            int*    /* actual_count_return */
        );
        
        char **XListFontsWithInfo(
            Display*    /* display */,
            const char*  /* pattern */,
            int      /* maxnames */,
            int*    /* count_return */,
            XFontStruct**  /* info_return */
        );
        
        char **XGetFontPath(
            Display*    /* display */,
            int*    /* npaths_return */
        );
        
        char **XListExtensions(
            Display*    /* display */,
            int*    /* nextensions_return */
        );

        Atom *XListProperties(
            Display*    /* display */,
            Window    /* w */,
            int*    /* num_prop_return */
        );
        
        XHostAddress *XListHosts(
            Display*    /* display */,
            int*    /* nhosts_return */,
            Bool*    /* state_return */
        );
        
        KeySym XLookupKeysym(
            XKeyEvent*    /* key_event */,
            int      /* index */
        );

        KeySym XStringToKeysym(
            const char*  /* string */
        );
        
        long XMaxRequestSize(
            Display*    /* display */
        );
        
        long XExtendedMaxRequestSize(
            Display*    /* display */
        );
        
        char *XResourceManagerString(
            Display*    /* display */
        );
        
        char *XScreenResourceString(
            Screen*    /* screen */
        );
        
        unsigned long XDisplayMotionBufferSize(
            Display*    /* display */
        );
        
        VisualID XVisualIDFromVisual(
            Visual*    /* visual */
        );

        /* multithread routines */

        Status XInitThreads(
            void
        );

        void XLockDisplay(
            Display*    /* display */
        );

        void XUnlockDisplay(
            Display*    /* display */
        );

        /* routines for dealing with extensions */

        XExtCodes *XInitExtension(
            Display*    /* display */,
            const char*  /* name */
        );

        XExtCodes *XAddExtension(
            Display*    /* display */
        );
        
        XExtData *XFindOnExtensionList(
            XExtData**    /* structure */,
            int      /* number */
        );
        
        /* these are routines for which there are also macros */
        Window XRootWindow(
            Display*    /* display */,
            int      /* screen_number */
        );
        
        Window XDefaultRootWindow(
            Display*    /* display */
        );
        
        Window XRootWindowOfScreen(
            Screen*    /* screen */
        );
        
        Visual *XDefaultVisual(
            Display*    /* display */,
            int      /* screen_number */
        );
        
        Visual *XDefaultVisualOfScreen(
            Screen*    /* screen */
        );
        
        GC XDefaultGC(
            Display*    /* display */,
            int      /* screen_number */
        );

        GC XDefaultGCOfScreen(
            Screen*    /* screen */
        );
        
        unsigned long XBlackPixel(
            Display*    /* display */,
            int      /* screen_number */
        );
        
        unsigned long XWhitePixel(
            Display*    /* display */,
            int      /* screen_number */
        );
        
        unsigned long XAllPlanes(
            void
        );
        
        unsigned long XBlackPixelOfScreen(
            Screen*    /* screen */
        );
        
        unsigned long XWhitePixelOfScreen(
            Screen*    /* screen */
        );
        
        unsigned long XNextRequest(
            Display*    /* display */
        );
        
        unsigned long XLastKnownRequestProcessed(
            Display*    /* display */
        );
        
        char *XServerVendor(
            Display*    /* display */
        );
        
        char *XDisplayString(
            Display*    /* display */
        );
        
        Colormap XDefaultColormap(
            Display*    /* display */,
            int      /* screen_number */
        );
        
        Colormap XDefaultColormapOfScreen(
            Screen*    /* screen */
        );
        
        Display *XDisplayOfScreen(
            Screen*    /* screen */
        );
        
        Screen *XScreenOfDisplay(
            Display*    /* display */,
            int      /* screen_number */
        );
        
        Screen *XDefaultScreenOfDisplay(
            Display*    /* display */
        );
        
        long XEventMaskOfScreen(
           Screen*    /* screen */
        );

        int XScreenNumberOfScreen(
            Screen*    /* screen */
        );
        
        typedef int (*XErrorHandler) (      /* WARNING, this type not in Xlib spec */
            Display*    /* display */,
            XErrorEvent*  /* error_event */
        );

        typedef int (*XIOErrorHandler) (    /* WARNING, this type not in Xlib spec */
          Display*		/* display */
        );

        XErrorHandler XSetErrorHandler (
            XErrorHandler  /* handler */
        );

        XIOErrorHandler XSetIOErrorHandler (
            XIOErrorHandler  /* handler */
        );

        XPixmapFormatValues *XListPixmapFormats(
            Display*    /* display */,
            int*    /* count_return */
        );
        
        int *XListDepths(
            Display*    /* display */,
            int      /* screen_number */,
            int*    /* count_return */
        );

        /* ICCCM routines for things that don't require special include files; */
        /* other declarations are given in Xutil.h                             */
        Status XReconfigureWMWindow(
            Display*    /* display */,
            Window    /* w */,
            int      /* screen_number */,
            unsigned int  /* mask */,
            XWindowChanges*  /* changes */
        );

        Status XGetWMProtocols(
            Display*    /* display */,
            Window    /* w */,
            Atom**    /* protocols_return */,
            int*    /* count_return */
        );
        
        Status XSetWMProtocols(
            Display*    /* display */,
            Window    /* w */,
            Atom*    /* protocols */,
            int      /* count */
        );
        
        Status XIconifyWindow(
           Display*    /* display */,
           Window    /* w */,
           int      /* screen_number */
        );
        Status XWithdrawWindow(
           Display*    /* display */,
           Window    /* w */,
           int      /* screen_number */
        );
        Status XGetCommand(
           Display*    /* display */,
           Window    /* w */,
           char***    /* argv_return */,
           int*    /* argc_return */
        );
        Status XGetWMColormapWindows(
           Display*    /* display */,
           Window    /* w */,
           Window**    /* windows_return */,
           int*    /* count_return */
        );
        Status XSetWMColormapWindows(
           Display*    /* display */,
           Window    /* w */,
           Window*    /* colormap_windows */,
           int      /* count */
        );
        void XFreeStringList(
           char**    /* list */
        );
        int XSetTransientForHint(
           Display*    /* display */,
           Window    /* w */,
           Window    /* prop_window */
        );
       
       /* The following are given in alphabetical order */
       
        int XActivateScreenSaver(
           Display*    /* display */
        );
       
        int XAddHost(
           Display*    /* display */,
           XHostAddress*  /* host */
        );
       
        int XAddHosts(
           Display*    /* display */,
           XHostAddress*  /* hosts */,
           int      /* num_hosts */
        );
       
        int XAddToExtensionList(
           struct _XExtData**  /* structure */,
           XExtData*    /* ext_data */
        );
       
        int XAddToSaveSet(
           Display*    /* display */,
           Window    /* w */
        );
       
        Status XAllocColor(
           Display*    /* display */,
           Colormap    /* colormap */,
           XColor*    /* screen_in_out */
        );

        Status XAllocColorCells(
           Display*    /* display */,
           Colormap    /* colormap */,
           Bool          /* contig */,
           unsigned long*  /* plane_masks_return */,
           unsigned int  /* nplanes */,
           unsigned long*  /* pixels_return */,
           unsigned int   /* npixels */
        );
       
        Status XAllocColorPlanes(
           Display*    /* display */,
           Colormap    /* colormap */,
           Bool    /* contig */,
           unsigned long*  /* pixels_return */,
           int      /* ncolors */,
           int      /* nreds */,
           int      /* ngreens */,
           int      /* nblues */,
           unsigned long*  /* rmask_return */,
           unsigned long*  /* gmask_return */,
           unsigned long*  /* bmask_return */
        );
       
        Status XAllocNamedColor(
           Display*    /* display */,
           Colormap    /* colormap */,
           const char*  /* color_name */,
           XColor*    /* screen_def_return */,
           XColor*    /* exact_def_return */
        );

        int XAllowEvents(
           Display*    /* display */,
           int      /* event_mode */,
           Time    /* time */
        );
       
        int XAutoRepeatOff(
           Display*    /* display */
        );
       
        int XAutoRepeatOn(
           Display*    /* display */
        );
       
        int XBell(
           Display*    /* display */,
           int      /* percent */
        );
       
        int XBitmapBitOrder(
           Display*    /* display */
        );
        int XBitmapPad(
           Display*    /* display */
        );
       
        int XBitmapUnit(
           Display*    /* display */
        );
       
        int XCellsOfScreen(
           Screen*    /* screen */
        );
       
        int XChangeActivePointerGrab(
           Display*    /* display */,
           unsigned int  /* event_mask */,
           Cursor    /* cursor */,
           Time    /* time */
        );

        int XChangeGC(
           Display*    /* display */,
           GC      /* gc */,
           unsigned long  /* valuemask */,
           XGCValues*    /* values */
        );
       
        int XChangeKeyboardControl(
           Display*    /* display */,
           unsigned long  /* value_mask */,
           XKeyboardControl*  /* values */
        );
       
        int XChangeKeyboardMapping(
           Display*    /* display */,
           int      /* first_keycode */,
           int      /* keysyms_per_keycode */,
           KeySym*    /* keysyms */,
           int      /* num_codes */
        );
       
        int XChangePointerControl(
           Display*    /* display */,
           Bool    /* do_accel */,
           Bool    /* do_threshold */,
           int      /* accel_numerator */,
           int      /* accel_denominator */,
           int      /* threshold */
        );
       
        int XChangeProperty(
           Display*    /* display */,
           Window    /* w */,
           Atom    /* property */,
           Atom    /* type */,
           int      /* format */,
           int      /* mode */,
           const unsigned char*  /* data */,
           int      /* nelements */
        );
       
        int XChangeSaveSet(
           Display*    /* display */,
           Window    /* w */,
           int      /* change_mode */
        );
       
        int XChangeWindowAttributes(
           Display*    /* display */,
           Window    /* w */,
           unsigned long  /* valuemask */,
           XSetWindowAttributes* /* attributes */
        );

        Bool XCheckIfEvent(
           Display*    /* display */,
           XEvent*    /* event_return */,
           Bool (*) (
                Display*      /* display */,
                      XEvent*      /* event */,
                      XPointer      /* arg */
                    )    /* predicate */,
           XPointer    /* arg */
        );
       
        Bool XCheckMaskEvent(
           Display*    /* display */,
           long    /* event_mask */,
           XEvent*    /* event_return */
        );
       
        Bool XCheckTypedEvent(
           Display*    /* display */,
           int      /* event_type */,
           XEvent*    /* event_return */
        );
       
        Bool XCheckTypedWindowEvent(
           Display*    /* display */,
           Window    /* w */,
           int      /* event_type */,
           XEvent*    /* event_return */
        );
       
        Bool XCheckWindowEvent(
           Display*    /* display */,
           Window    /* w */,
           long    /* event_mask */,
           XEvent*    /* event_return */
        );
       
        int XCirculateSubwindows(
           Display*    /* display */,
           Window    /* w */,
           int      /* direction */
        );
       
        int XCirculateSubwindowsDown(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XCirculateSubwindowsUp(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XClearArea(
           Display*    /* display */,
           Window    /* w */,
           int      /* x */,
           int      /* y */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           Bool    /* exposures */
        );
       
        int XClearWindow(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XCloseDisplay(
           Display*    /* display */
        );
       
        int XConfigureWindow(
           Display*    /* display */,
           Window    /* w */,
           unsigned int  /* value_mask */,
           XWindowChanges*  /* values */
        );
       
        int XConnectionNumber(
           Display*    /* display */
        );
       
        int XConvertSelection(
           Display*    /* display */,
           Atom    /* selection */,
           Atom     /* target */,
           Atom    /* property */,
           Window    /* requestor */,
           Time    /* time */
        );

        int XCopyArea(
           Display*    /* display */,
           Drawable    /* src */,
           Drawable    /* dest */,
           GC      /* gc */,
           int      /* src_x */,
           int      /* src_y */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           int      /* dest_x */,
           int      /* dest_y */
        );
       
        int XCopyGC(
           Display*    /* display */,
           GC      /* src */,
           unsigned long  /* valuemask */,
           GC      /* dest */
        );
       
        int XCopyPlane(
           Display*    /* display */,
           Drawable    /* src */,
           Drawable    /* dest */,
           GC      /* gc */,
           int      /* src_x */,
           int      /* src_y */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           int      /* dest_x */,
           int      /* dest_y */,
           unsigned long  /* plane */
        );
       
        int XDefaultDepth(
           Display*    /* display */,
           int      /* screen_number */
        );
       
        int XDefaultDepthOfScreen(
           Screen*    /* screen */
        );
       
        int XDefaultScreen(
           Display*    /* display */
        );
       
        int XDefineCursor(
           Display*    /* display */,
           Window    /* w */,
           Cursor    /* cursor */
        );
       
        int XDeleteProperty(
           Display*    /* display */,
           Window    /* w */,
           Atom    /* property */
        );
       
        int XDestroyWindow(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XDestroySubwindows(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XDoesBackingStore(
           Screen*    /* screen */
        );
       
        Bool XDoesSaveUnders(
           Screen*    /* screen */
        );
       
        int XDisableAccessControl(
           Display*    /* display */
        );
       
       
        int XDisplayCells(
           Display*    /* display */,
           int      /* screen_number */
        );
       
        int XDisplayHeight(
           Display*    /* display */,
           int      /* screen_number */
        );
       
        int XDisplayHeightMM(
           Display*    /* display */,
           int      /* screen_number */
        );
 
        int XDisplayKeycodes(
           Display*    /* display */,
           int*    /* min_keycodes_return */,
           int*    /* max_keycodes_return */
        );
       
        int XDisplayPlanes(
           Display*    /* display */,
           int      /* screen_number */
        );
       
        int XDisplayWidth(
           Display*    /* display */,
           int      /* screen_number */
        );
       
        int XDisplayWidthMM(
           Display*    /* display */,
           int      /* screen_number */
        );
       
        int XDrawArc(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           int      /* angle1 */,
           int      /* angle2 */
        );

        int XDrawArcs(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XArc*    /* arcs */,
           int      /* narcs */
        );
       
        int XDrawImageString(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const char*  /* string */,
           int      /* length */
        );

        int XDrawImageString16(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const XChar2b*  /* string */,
           int      /* length */
        );
       
        int XDrawLine(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x1 */,
           int      /* y1 */,
           int      /* x2 */,
           int      /* y2 */
        );

        int XDrawLines(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XPoint*    /* points */,
           int      /* npoints */,
           int      /* mode */
        );
       
        int XDrawPoint(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */
        );
       
        int XDrawPoints(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XPoint*    /* points */,
           int      /* npoints */,
           int      /* mode */
        );
       
        int XDrawRectangle(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           unsigned int  /* width */,
           unsigned int  /* height */
        );
       
        int XDrawRectangles(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XRectangle*    /* rectangles */,
           int      /* nrectangles */
        );

        int XDrawSegments(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XSegment*    /* segments */,
           int      /* nsegments */
        );
       
        int XDrawString(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const char*  /* string */,
           int      /* length */
        );
       
        int XDrawString16(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const XChar2b*  /* string */,
           int      /* length */
        );

        int XDrawText(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           XTextItem*    /* items */,
           int      /* nitems */
        );
       
        int XDrawText16(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           XTextItem16*  /* items */,
           int      /* nitems */
        );
       
        int XEnableAccessControl(
           Display*    /* display */
        );
       
        int XEventsQueued(
           Display*    /* display */,
           int      /* mode */
        );
       
        Status XFetchName(
           Display*    /* display */,
           Window    /* w */,
           char**    /* window_name_return */
        );
       
        int XFillArc(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           int      /* angle1 */,
           int      /* angle2 */
        );
       
        int XFillArcs(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XArc*    /* arcs */,
           int      /* narcs */
        );
       
        int XFillPolygon(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XPoint*    /* points */,
           int      /* npoints */,
           int      /* shape */,
           int      /* mode */
        );
       
        int XFillRectangle(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           unsigned int  /* width */,
           unsigned int  /* height */
        );
       
        int XFillRectangles(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XRectangle*    /* rectangles */,
           int      /* nrectangles */
        );
       
        int XFlush(
           Display*    /* display */
        );
       
        int XForceScreenSaver(
           Display*    /* display */,
           int      /* mode */
        );
       
        int XFree(
           void*    /* data */
        );
       
        int XFreeColormap(
           Display*    /* display */,
           Colormap    /* colormap */
        );

        int XFreeColors(
           Display*    /* display */,
           Colormap    /* colormap */,
           unsigned long*  /* pixels */,
           int      /* npixels */,
           unsigned long  /* planes */
        );
       
        int XFreeCursor(
           Display*    /* display */,
           Cursor    /* cursor */
        );
       
        int XFreeExtensionList(
           char**    /* list */
        );
       
        int XFreeFont(
           Display*    /* display */,
           XFontStruct*  /* font_struct */
        );
       
        int XFreeFontInfo(
           char**    /* names */,
           XFontStruct*  /* free_info */,
           int      /* actual_count */
        );

        int XFreeFontNames(
           char**    /* list */
        );
       
        int XFreeFontPath(
           char**    /* list */
        );
       
        int XFreeGC(
           Display*    /* display */,
           GC      /* gc */
        );
       
        int XFreeModifiermap(
           XModifierKeymap*  /* modmap */
        );
       
        int XFreePixmap(
           Display*    /* display */,
           Pixmap    /* pixmap */
        );
       
        int XGeometry(
           Display*    /* display */,
           int      /* screen */,
           const char*  /* position */,
           const char*  /* default_position */,
           unsigned int  /* bwidth */,
           unsigned int  /* fwidth */,
           unsigned int  /* fheight */,
           int      /* xadder */,
           int      /* yadder */,
           int*    /* x_return */,
           int*    /* y_return */,
           int*    /* width_return */,
           int*    /* height_return */
        );
       
        int XGetErrorDatabaseText(
           Display*    /* display */,
           const char*  /* name */,
           const char*  /* message */,
           const char*  /* default_string */,
           char*    /* buffer_return */,
           int      /* length */
        );
       
        int XGetErrorText(
           Display*    /* display */,
           int      /* code */,
           char*    /* buffer_return */,
           int      /* length */
        );
       
        Bool XGetFontProperty(
           XFontStruct*  /* font_struct */,
           Atom    /* atom */,
           unsigned long*  /* value_return */
        );
       
        Status XGetGCValues(
           Display*    /* display */,
           GC      /* gc */,
           unsigned long  /* valuemask */,
           XGCValues*    /* values_return */
        );

        Status XGetGeometry(
           Display*    /* display */,
           Drawable    /* d */,
           Window*    /* root_return */,
           int*    /* x_return */,
           int*    /* y_return */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */,
           unsigned int*  /* border_width_return */,
           unsigned int*  /* depth_return */
        );
       
        Status XGetIconName(
           Display*    /* display */,
           Window    /* w */,
           char**    /* icon_name_return */
        );
       
        int XGetInputFocus(
           Display*    /* display */,
           Window*    /* focus_return */,
           int*    /* revert_to_return */
        );
       
        int XGetKeyboardControl(
           Display*    /* display */,
           XKeyboardState*  /* values_return */
        );
       
        int XGetPointerControl(
           Display*    /* display */,
           int*    /* accel_numerator_return */,
           int*    /* accel_denominator_return */,
           int*    /* threshold_return */
        );
       
        int XGetPointerMapping(
           Display*    /* display */,
           unsigned char*  /* map_return */,
           int      /* nmap */
        );
       
        int XGetScreenSaver(
           Display*    /* display */,
           int*    /* timeout_return */,
           int*    /* interval_return */,
           int*    /* prefer_blanking_return */,
           int*    /* allow_exposures_return */
        );
       
        Status XGetTransientForHint(
           Display*    /* display */,
           Window    /* w */,
           Window*    /* prop_window_return */
        );
       
        int XGetWindowProperty(
           Display*    /* display */,
           Window    /* w */,
           Atom    /* property */,
           long    /* long_offset */,
           long    /* long_length */,
           Bool    /* delete */,
           Atom    /* req_type */,
           Atom*    /* actual_type_return */,
           int*    /* actual_format_return */,
           unsigned long*  /* nitems_return */,
           unsigned long*  /* bytes_after_return */,
           unsigned char**  /* prop_return */
        );
       
        Status XGetWindowAttributes(
           Display*    /* display */,
           Window    /* w */,
           XWindowAttributes*  /* window_attributes_return */
        );
       
        int XGrabButton(
           Display*    /* display */,
           unsigned int  /* button */,
           unsigned int  /* modifiers */,
           Window    /* grab_window */,
           Bool    /* owner_events */,
           unsigned int  /* event_mask */,
           int      /* pointer_mode */,
           int      /* keyboard_mode */,
           Window    /* confine_to */,
           Cursor    /* cursor */
        );
       
        int XGrabKey(
           Display*    /* display */,
           int      /* keycode */,
           unsigned int  /* modifiers */,
           Window    /* grab_window */,
           Bool    /* owner_events */,
           int      /* pointer_mode */,
           int      /* keyboard_mode */
        );
       
        int XGrabKeyboard(
           Display*    /* display */,
           Window    /* grab_window */,
           Bool    /* owner_events */,
           int      /* pointer_mode */,
           int      /* keyboard_mode */,
           Time    /* time */
        );
       
        int XGrabPointer(
           Display*    /* display */,
           Window    /* grab_window */,
           Bool    /* owner_events */,
           unsigned int  /* event_mask */,
           int      /* pointer_mode */,
           int      /* keyboard_mode */,
           Window    /* confine_to */,
           Cursor    /* cursor */,
           Time    /* time */
        );
       
        int XGrabServer(
           Display*    /* display */
        );
       
        int XHeightMMOfScreen(
           Screen*    /* screen */
        );
       
        int XHeightOfScreen(
           Screen*    /* screen */
        );
       
        int XIfEvent(
           Display*    /* display */,
           XEvent*    /* event_return */,
           Bool (*) (
                Display*      /* display */,
                      XEvent*      /* event */,
                      XPointer      /* arg */
                    )    /* predicate */,
           XPointer    /* arg */
        );
       
        int XImageByteOrder(
           Display*    /* display */
        );
       
        int XInstallColormap(
           Display*    /* display */,
           Colormap    /* colormap */
        );
       
        KeyCode XKeysymToKeycode(
           Display*    /* display */,
           KeySym    /* keysym */
        );
       
        int XKillClient(
           Display*    /* display */,
           XID      /* resource */
        );
       
        Status XLookupColor(
           Display*    /* display */,
           Colormap    /* colormap */,
           const char*  /* color_name */,
           XColor*    /* exact_def_return */,
           XColor*    /* screen_def_return */
        );
       
        int XLowerWindow(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XMapRaised(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XMapSubwindows(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XMapWindow(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XMaskEvent(
           Display*    /* display */,
           long    /* event_mask */,
           XEvent*    /* event_return */
        );
       
        int XMaxCmapsOfScreen(
           Screen*    /* screen */
        );
       
        int XMinCmapsOfScreen(
           Screen*    /* screen */
        );
       
        int XMoveResizeWindow(
           Display*    /* display */,
           Window    /* w */,
           int      /* x */,
           int      /* y */,
           unsigned int  /* width */,
           unsigned int  /* height */
        );
       
        int XMoveWindow(
           Display*    /* display */,
           Window    /* w */,
           int      /* x */,
           int      /* y */
        );
       
        int XNextEvent(
           Display*    /* display */,
           XEvent*    /* event_return */
        );
       
        int XNoOp(
           Display*    /* display */
        );
       
        Status XParseColor(
           Display*    /* display */,
           Colormap    /* colormap */,
           const char*  /* spec */,
           XColor*    /* exact_def_return */
        );
       
        int XParseGeometry(
           const char*  /* parsestring */,
           int*    /* x_return */,
           int*    /* y_return */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */
        );
       
        int XPeekEvent(
           Display*    /* display */,
           XEvent*    /* event_return */
        );
       
        int XPeekIfEvent(
           Display*    /* display */,
           XEvent*    /* event_return */,
           Bool (*) (
                Display*    /* display */,
                      XEvent*    /* event */,
                      XPointer    /* arg */
                    )    /* predicate */,
           XPointer    /* arg */
        );
       
        int XPending(
           Display*    /* display */
        );
       
        int XPlanesOfScreen(
           Screen*    /* screen */
        );
       
        int XProtocolRevision(
           Display*    /* display */
        );
       
        int XProtocolVersion(
           Display*    /* display */
        );
       
       
        int XPutBackEvent(
           Display*    /* display */,
           XEvent*    /* event */
        );
       
        int XPutImage(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           XImage*    /* image */,
           int      /* src_x */,
           int      /* src_y */,
           int      /* dest_x */,
           int      /* dest_y */,
           unsigned int  /* width */,
           unsigned int  /* height */
        );
       
        int XQLength(
           Display*    /* display */
        );
       
        Status XQueryBestCursor(
           Display*    /* display */,
           Drawable    /* d */,
           unsigned int        /* width */,
           unsigned int  /* height */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */
        );
       
        Status XQueryBestSize(
           Display*    /* display */,
           int      /* class */,
           Drawable    /* which_screen */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */
        );
       
        Status XQueryBestStipple(
           Display*    /* display */,
           Drawable    /* which_screen */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */
        );
       
        Status XQueryBestTile(
           Display*    /* display */,
           Drawable    /* which_screen */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */
        );
       
        int XQueryColor(
           Display*    /* display */,
           Colormap    /* colormap */,
           XColor*    /* def_in_out */
        );
       
        int XQueryColors(
           Display*    /* display */,
           Colormap    /* colormap */,
           XColor*    /* defs_in_out */,
           int      /* ncolors */
        );
       
        Bool XQueryExtension(
           Display*    /* display */,
           const char*  /* name */,
           int*    /* major_opcode_return */,
           int*    /* first_event_return */,
           int*    /* first_error_return */
        );
              
        int XQueryKeymap(
           Display*    /* display */,
           char [32]   /* keys_return */
        );
              
        Bool XQueryPointer(
           Display*    /* display */,
           Window    /* w */,
           Window*    /* root_return */,
           Window*    /* child_return */,
           int*    /* root_x_return */,
           int*    /* root_y_return */,
           int*    /* win_x_return */,
           int*    /* win_y_return */,
           unsigned int*       /* mask_return */
        );
       
        int XQueryTextExtents(
           Display*    /* display */,
           XID      /* font_ID */,
           const char*  /* string */,
           int      /* nchars */,
           int*    /* direction_return */,
           int*    /* font_ascent_return */,
           int*    /* font_descent_return */,
           XCharStruct*  /* overall_return */
        );
       
        int XQueryTextExtents16(
           Display*    /* display */,
           XID      /* font_ID */,
           const XChar2b*  /* string */,
           int      /* nchars */,
           int*    /* direction_return */,
           int*    /* font_ascent_return */,
           int*    /* font_descent_return */,
           XCharStruct*  /* overall_return */
        );
       
        Status XQueryTree(
           Display*    /* display */,
           Window    /* w */,
           Window*    /* root_return */,
           Window*    /* parent_return */,
           Window**    /* children_return */,
           unsigned int*  /* nchildren_return */
        );
       
        int XRaiseWindow(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XReadBitmapFile(
           Display*    /* display */,
           Drawable     /* d */,
           const char*  /* filename */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */,
           Pixmap*    /* bitmap_return */,
           int*    /* x_hot_return */,
           int*    /* y_hot_return */
        );
       
        int XReadBitmapFileData(
           const char*  /* filename */,
           unsigned int*  /* width_return */,
           unsigned int*  /* height_return */,
           unsigned char**  /* data_return */,
           int*    /* x_hot_return */,
           int*    /* y_hot_return */
        );
       
        int XRebindKeysym(
           Display*    /* display */,
           KeySym    /* keysym */,
           KeySym*    /* list */,
           int      /* mod_count */,
           const unsigned char*  /* string */,
           int      /* bytes_string */
        );
       
        int XRecolorCursor(
           Display*    /* display */,
           Cursor    /* cursor */,
           XColor*    /* foreground_color */,
           XColor*    /* background_color */
        );
       
        int XRefreshKeyboardMapping(
           XMappingEvent*  /* event_map */
        );
       
        int XRemoveFromSaveSet(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XRemoveHost(
           Display*    /* display */,
           XHostAddress*  /* host */
        );
       
        int XRemoveHosts(
           Display*    /* display */,
           XHostAddress*  /* hosts */,
           int      /* num_hosts */
        );
       
        int XReparentWindow(
           Display*    /* display */,
           Window    /* w */,
           Window    /* parent */,
           int      /* x */,
           int      /* y */
        );
       
        int XResetScreenSaver(
           Display*    /* display */
        );
       
        int XResizeWindow(
           Display*    /* display */,
           Window    /* w */,
           unsigned int  /* width */,
           unsigned int  /* height */
        );
       
        int XRestackWindows(
           Display*    /* display */,
           Window*    /* windows */,
           int      /* nwindows */
        );
       
        int XRotateBuffers(
           Display*    /* display */,
           int      /* rotate */
        );
       
        int XRotateWindowProperties(
           Display*    /* display */,
           Window    /* w */,
           Atom*    /* properties */,
           int      /* num_prop */,
           int      /* npositions */
        );
       
        int XScreenCount(
           Display*    /* display */
        );
       
        int XSelectInput(
           Display*    /* display */,
           Window    /* w */,
           long    /* event_mask */
        );
       
        Status XSendEvent(
           Display*    /* display */,
           Window    /* w */,
           Bool    /* propagate */,
           long    /* event_mask */,
           XEvent*    /* event_send */
        );
       
        int XSetAccessControl(
           Display*    /* display */,
           int      /* mode */
        );
       
        int XSetArcMode(
           Display*    /* display */,
           GC      /* gc */,
           int      /* arc_mode */
        );
       
        int XSetBackground(
           Display*    /* display */,
           GC      /* gc */,
           unsigned long  /* background */
        );
       
        int XSetClipMask(
           Display*    /* display */,
           GC      /* gc */,
           Pixmap    /* pixmap */
        );
       
        int XSetClipOrigin(
           Display*    /* display */,
           GC      /* gc */,
           int      /* clip_x_origin */,
           int      /* clip_y_origin */
        );
       
        int XSetClipRectangles(
           Display*    /* display */,
           GC      /* gc */,
           int      /* clip_x_origin */,
           int      /* clip_y_origin */,
           XRectangle*    /* rectangles */,
           int      /* n */,
           int      /* ordering */
        );
       
        int XSetCloseDownMode(
           Display*    /* display */,
           int      /* close_mode */
        );
       
        int XSetCommand(
           Display*    /* display */,
           Window    /* w */,
           char**    /* argv */,
           int      /* argc */
        );
       
        int XSetDashes(
           Display*    /* display */,
           GC      /* gc */,
           int      /* dash_offset */,
           const char*  /* dash_list */,
           int      /* n */
        );
       
        int XSetFillRule(
           Display*    /* display */,
           GC      /* gc */,
           int      /* fill_rule */
        );
       
        int XSetFillStyle(
           Display*    /* display */,
           GC      /* gc */,
           int      /* fill_style */
        );
       
        int XSetFont(
           Display*    /* display */,
           GC      /* gc */,
           Font    /* font */
        );
       
        int XSetFontPath(
           Display*    /* display */,
           char**    /* directories */,
           int      /* ndirs */
        );
       
        int XSetForeground(
           Display*    /* display */,
           GC      /* gc */,
           unsigned long  /* foreground */
        );
       
        int XSetFunction(
           Display*    /* display */,
           GC      /* gc */,
           int      /* function */
        );
       
        int XSetGraphicsExposures(
           Display*    /* display */,
           GC      /* gc */,
           Bool    /* graphics_exposures */
        );
       
        int XSetIconName(
           Display*    /* display */,
           Window    /* w */,
           const char*  /* icon_name */
        );
       
        int XSetInputFocus(
           Display*    /* display */,
           Window    /* focus */,
           int      /* revert_to */,
           Time    /* time */
        );
       
        int XSetLineAttributes(
           Display*    /* display */,
           GC      /* gc */,
           unsigned int  /* line_width */,
           int      /* line_style */,
           int      /* cap_style */,
           int      /* join_style */
        );
       
        int XSetModifierMapping(
           Display*    /* display */,
           XModifierKeymap*  /* modmap */
        );
       
        int XSetPlaneMask(
           Display*    /* display */,
           GC      /* gc */,
           unsigned long  /* plane_mask */
        );
       
        int XSetPointerMapping(
           Display*    /* display */,
           const unsigned char*  /* map */,
           int      /* nmap */
        );
       
        int XSetScreenSaver(
           Display*    /* display */,
           int      /* timeout */,
           int      /* interval */,
           int      /* prefer_blanking */,
           int      /* allow_exposures */
        );
       
        int XSetSelectionOwner(
           Display*    /* display */,
           Atom          /* selection */,
           Window    /* owner */,
           Time    /* time */
        );
       
        int XSetState(
           Display*    /* display */,
           GC      /* gc */,
           unsigned long   /* foreground */,
           unsigned long  /* background */,
           int      /* function */,
           unsigned long  /* plane_mask */
        );
       
        int XSetStipple(
           Display*    /* display */,
           GC      /* gc */,
           Pixmap    /* stipple */
        );
       
        int XSetSubwindowMode(
           Display*    /* display */,
           GC      /* gc */,
           int      /* subwindow_mode */
        );
       
        int XSetTSOrigin(
           Display*    /* display */,
           GC      /* gc */,
           int      /* ts_x_origin */,
           int      /* ts_y_origin */
        );
       
        int XSetTile(
           Display*    /* display */,
           GC      /* gc */,
           Pixmap    /* tile */
        );
       
        int XSetWindowBackground(
           Display*    /* display */,
           Window    /* w */,
           unsigned long  /* background_pixel */
        );
       
        int XSetWindowBackgroundPixmap(
           Display*    /* display */,
           Window    /* w */,
           Pixmap    /* background_pixmap */
        );
       
        int XSetWindowBorder(
           Display*    /* display */,
           Window    /* w */,
           unsigned long  /* border_pixel */
        );
       
        int XSetWindowBorderPixmap(
           Display*    /* display */,
           Window    /* w */,
           Pixmap    /* border_pixmap */
        );
       
        int XSetWindowBorderWidth(
           Display*    /* display */,
           Window    /* w */,
           unsigned int  /* width */
        );
       
        int XSetWindowColormap(
           Display*    /* display */,
           Window    /* w */,
           Colormap    /* colormap */
        );
       
        int XStoreBuffer(
           Display*    /* display */,
           const char*  /* bytes */,
           int      /* nbytes */,
           int      /* buffer */
        );
       
        int XStoreBytes(
           Display*    /* display */,
           const char*  /* bytes */,
           int      /* nbytes */
        );
       
        int XStoreColor(
           Display*    /* display */,
           Colormap    /* colormap */,
           XColor*    /* color */
        );
       
        int XStoreColors(
           Display*    /* display */,
           Colormap    /* colormap */,
           XColor*    /* color */,
           int      /* ncolors */
        );
       
        int XStoreName(
           Display*    /* display */,
           Window    /* w */,
           const char*  /* window_name */
        );
       
        int XStoreNamedColor(
           Display*    /* display */,
           Colormap    /* colormap */,
           const char*  /* color */,
           unsigned long  /* pixel */,
           int      /* flags */
        );
       
        int XSync(
           Display*    /* display */,
           Bool    /* discard */
        );
       
        int XTextExtents(
           XFontStruct*  /* font_struct */,
           const char*  /* string */,
           int      /* nchars */,
           int*    /* direction_return */,
           int*    /* font_ascent_return */,
           int*    /* font_descent_return */,
           XCharStruct*  /* overall_return */
        );
       
        int XTextExtents16(
           XFontStruct*  /* font_struct */,
           const XChar2b*  /* string */,
           int      /* nchars */,
           int*    /* direction_return */,
           int*    /* font_ascent_return */,
           int*    /* font_descent_return */,
           XCharStruct*  /* overall_return */
        );
       
        int XTextWidth(
           XFontStruct*  /* font_struct */,
           const char*  /* string */,
           int      /* count */
        );
       
        int XTextWidth16(
           XFontStruct*  /* font_struct */,
           const XChar2b*  /* string */,
           int      /* count */
        );
       
        Bool XTranslateCoordinates(
           Display*    /* display */,
           Window    /* src_w */,
           Window    /* dest_w */,
           int      /* src_x */,
           int      /* src_y */,
           int*    /* dest_x_return */,
           int*    /* dest_y_return */,
           Window*    /* child_return */
        );
       
        int XUndefineCursor(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XUngrabButton(
           Display*    /* display */,
           unsigned int  /* button */,
           unsigned int  /* modifiers */,
           Window    /* grab_window */
        );
       
        int XUngrabKey(
           Display*    /* display */,
           int      /* keycode */,
           unsigned int  /* modifiers */,
           Window    /* grab_window */
        );
       
        int XUngrabKeyboard(
           Display*    /* display */,
           Time    /* time */
        );
       
        int XUngrabPointer(
           Display*    /* display */,
           Time    /* time */
        );
       
        int XUngrabServer(
           Display*    /* display */
        );
       
        int XUninstallColormap(
           Display*    /* display */,
           Colormap    /* colormap */
        );
       
        int XUnloadFont(
           Display*    /* display */,
           Font    /* font */
        );
       
        int XUnmapSubwindows(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XUnmapWindow(
           Display*    /* display */,
           Window    /* w */
        );
       
        int XVendorRelease(
           Display*    /* display */
        );
       
        int XWarpPointer(
           Display*    /* display */,
           Window    /* src_w */,
           Window    /* dest_w */,
           int      /* src_x */,
           int      /* src_y */,
           unsigned int  /* src_width */,
           unsigned int  /* src_height */,
           int      /* dest_x */,
           int      /* dest_y */
        );
       
        int XWidthMMOfScreen(
           Screen*    /* screen */
        );
       
        int XWidthOfScreen(
           Screen*    /* screen */
        );
       
        int XWindowEvent(
           Display*    /* display */,
           Window    /* w */,
           long    /* event_mask */,
           XEvent*    /* event_return */
        );
       
        int XWriteBitmapFile(
           Display*    /* display */,
           const char*  /* filename */,
           Pixmap    /* bitmap */,
           unsigned int  /* width */,
           unsigned int  /* height */,
           int      /* x_hot */,
           int      /* y_hot */
        );
       
        Bool XSupportsLocale (void);
       
        char *XSetLocaleModifiers(
           const char*    /* modifier_list */
        );
       
        XOM XOpenOM(
           Display*      /* display */,
           struct _XrmHashBucketRec*  /* rdb */,
           const char*    /* res_name */,
           const char*    /* res_class */
        );
       
        Status XCloseOM(
           XOM      /* om */
        );
       
        Display *XDisplayOfOM(
           XOM      /* om */
        );
       
        char *XLocaleOfOM(
           XOM      /* om */
        );
       
        void XDestroyOC(
           XOC      /* oc */
        );
       
        XOM XOMOfOC(
           XOC      /* oc */
        );
        
        XFontSet XCreateFontSet(
           Display*    /* display */,
           const char*  /* base_font_name_list */,
           char***    /* missing_charset_list */,
           int*    /* missing_charset_count */,
           char**    /* def_string */
        );
       
        void XFreeFontSet(
           Display*    /* display */,
           XFontSet    /* font_set */
        );
       
        int XFontsOfFontSet(
           XFontSet    /* font_set */,
           XFontStruct***  /* font_struct_list */,
           char***    /* font_name_list */
        );
       
        char *XBaseFontNameListOfFontSet(
           XFontSet    /* font_set */
        );
       
        char *XLocaleOfFontSet(
           XFontSet    /* font_set */
        );
       
        Bool XContextDependentDrawing(
           XFontSet    /* font_set */
        );
       
        Bool XDirectionalDependentDrawing(
           XFontSet    /* font_set */
        );
       
        Bool XContextualDrawing(
           XFontSet    /* font_set */
        );
       
        XFontSetExtents *XExtentsOfFontSet(
           XFontSet    /* font_set */
        );
       
        int XmbTextEscapement(
           XFontSet    /* font_set */,
           const char*  /* text */,
           int      /* bytes_text */
        );
       
        int XwcTextEscapement(
           XFontSet    /* font_set */,
           const wchar_t*  /* text */,
           int      /* num_wchars */
        );
       
        int Xutf8TextEscapement(
           XFontSet    /* font_set */,
           const char*  /* text */,
           int      /* bytes_text */
        );
       
        int XmbTextExtents(
           XFontSet    /* font_set */,
           const char*  /* text */,
           int      /* bytes_text */,
           XRectangle*    /* overall_ink_return */,
           XRectangle*    /* overall_logical_return */
        );
       
        int XwcTextExtents(
           XFontSet    /* font_set */,
           const wchar_t*  /* text */,
           int      /* num_wchars */,
           XRectangle*    /* overall_ink_return */,
           XRectangle*    /* overall_logical_return */
        );
       
        int Xutf8TextExtents(
           XFontSet    /* font_set */,
           const char*  /* text */,
           int      /* bytes_text */,
           XRectangle*    /* overall_ink_return */,
           XRectangle*    /* overall_logical_return */
        );
       
        Status XmbTextPerCharExtents(
           XFontSet    /* font_set */,
           const char*  /* text */,
           int      /* bytes_text */,
           XRectangle*    /* ink_extents_buffer */,
           XRectangle*    /* logical_extents_buffer */,
           int      /* buffer_size */,
           int*    /* num_chars */,
           XRectangle*    /* overall_ink_return */,
           XRectangle*    /* overall_logical_return */
        );
       
        Status XwcTextPerCharExtents(
           XFontSet    /* font_set */,
           const wchar_t*  /* text */,
           int      /* num_wchars */,
           XRectangle*    /* ink_extents_buffer */,
           XRectangle*    /* logical_extents_buffer */,
           int      /* buffer_size */,
           int*    /* num_chars */,
           XRectangle*    /* overall_ink_return */,
           XRectangle*    /* overall_logical_return */
        );
       
        Status Xutf8TextPerCharExtents(
           XFontSet    /* font_set */,
           const char*  /* text */,
           int      /* bytes_text */,
           XRectangle*    /* ink_extents_buffer */,
           XRectangle*    /* logical_extents_buffer */,
           int      /* buffer_size */,
           int*    /* num_chars */,
           XRectangle*    /* overall_ink_return */,
           XRectangle*    /* overall_logical_return */
        );
       
        void XmbDrawText(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           XmbTextItem*  /* text_items */,
           int      /* nitems */
        );

        void XwcDrawText(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           XwcTextItem*  /* text_items */,
           int      /* nitems */
        );
       
        void Xutf8DrawText(
           Display*    /* display */,
           Drawable    /* d */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           XmbTextItem*  /* text_items */,
           int      /* nitems */
        );
       
        void XmbDrawString(
           Display*    /* display */,
           Drawable    /* d */,
           XFontSet    /* font_set */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const char*  /* text */,
           int      /* bytes_text */
        );
       
        void XwcDrawString(
           Display*    /* display */,
           Drawable    /* d */,
           XFontSet    /* font_set */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const wchar_t*  /* text */,
           int      /* num_wchars */
        );
       
        void Xutf8DrawString(
           Display*    /* display */,
           Drawable    /* d */,
           XFontSet    /* font_set */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const char*  /* text */,
           int      /* bytes_text */
        );
       
        void XmbDrawImageString(
           Display*    /* display */,
           Drawable    /* d */,
           XFontSet    /* font_set */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const char*  /* text */,
           int      /* bytes_text */
        );
       
        void XwcDrawImageString(
           Display*    /* display */,
           Drawable    /* d */,
           XFontSet    /* font_set */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const wchar_t*  /* text */,
           int      /* num_wchars */
        );
       
        void Xutf8DrawImageString(
           Display*    /* display */,
           Drawable    /* d */,
           XFontSet    /* font_set */,
           GC      /* gc */,
           int      /* x */,
           int      /* y */,
           const char*  /* text */,
           int      /* bytes_text */
       ) ;
       
        XIM XOpenIM(
           Display*      /* dpy */,
           struct _XrmHashBucketRec*  /* rdb */,
           char*      /* res_name */,
           char*      /* res_class */
        );
       
        Status XCloseIM(
           XIM /* im */
        );
       
        Display *XDisplayOfIM(
           XIM /* im */
        );
       
        char *XLocaleOfIM(
           XIM /* im*/
        );
       
        void XDestroyIC(
           XIC /* ic */
        );
       
        void XSetICFocus(
           XIC /* ic */
        );
       
        void XUnsetICFocus(
           XIC /* ic */
        );
       
        wchar_t *XwcResetIC(
           XIC /* ic */
        );
       
        char *XmbResetIC(
           XIC /* ic */
        );
       
        char *Xutf8ResetIC(
           XIC /* ic */
        );
       
        XIM XIMOfIC(
           XIC /* ic */
        );
       
        Bool XFilterEvent(
           XEvent*  /* event */,
           Window  /* window */
        );

        int XmbLookupString(
           XIC      /* ic */,
           XKeyPressedEvent*  /* event */,
           char*    /* buffer_return */,
           int      /* bytes_buffer */,
           KeySym*    /* keysym_return */,
           Status*    /* status_return */
        );
       
        int XwcLookupString(
           XIC      /* ic */,
           XKeyPressedEvent*  /* event */,
           wchar_t*    /* buffer_return */,
           int      /* wchars_buffer */,
           KeySym*    /* keysym_return */,
           Status*    /* status_return */
        );
       
        int Xutf8LookupString(
           XIC      /* ic */,
           XKeyPressedEvent*  /* event */,
           char*    /* buffer_return */,
           int      /* bytes_buffer */,
           KeySym*    /* keysym_return */,
           Status*    /* status_return */
        );

        /* internal connections for IMs */
       
        Bool XRegisterIMInstantiateCallback(
           Display*      /* dpy */,
           struct _XrmHashBucketRec*  /* rdb */,
           char*      /* res_name */,
           char*      /* res_class */,
           XIDProc      /* callback */,
           XPointer      /* client_data */
        );
       
        Bool XUnregisterIMInstantiateCallback(
           Display*      /* dpy */,
           struct _XrmHashBucketRec*  /* rdb */,
           char*      /* res_name */,
           char*      /* res_class */,
           XIDProc      /* callback */,
           XPointer      /* client_data */
        );
       
        typedef void (*XConnectionWatchProc)(
           Display*      /* dpy */,
           XPointer      /* client_data */,
           int        /* fd */,
           Bool      /* opening */,   /* open or close flag */
           XPointer*      /* watch_data */ /* open sets, close uses */
        );
       
        Status XInternalConnectionNumbers(
           Display*      /* dpy */,
           int**      /* fd_return */,
           int*      /* count_return */
        );
       
        void XProcessInternalConnection(
           Display*      /* dpy */,
           int        /* fd */
        );

        Status XAddConnectionWatch(
           Display*      /* dpy */,
           XConnectionWatchProc  /* callback */,
           XPointer      /* client_data */
        );
       
        void XRemoveConnectionWatch(
           Display*      /* dpy */,
           XConnectionWatchProc  /* callback */,
           XPointer      /* client_data */
        );
       
        void XSetAuthorization(
           char *      /* name */,
           int        /* namelen */,
           char *      /* data */,
           int        /* datalen */
        );
       
        int _Xwctomb(
           char *      /* str */,
           wchar_t      /* wc */
        );
       
        Bool XGetEventData(
           Display*      /* dpy */,
           XGenericEventCookie*  /* cookie*/
        );
       
        void XFreeEventData(
           Display*      /* dpy */,
           XGenericEventCookie*  /* cookie*/
        );        
        
        /* Helpers */
        typedef union { Atom atom; } AtomContainer;
    `);


    /**
    Input Event Masks. Used as event-mask window attribute and as arguments
    to Grab requests.  Not to be confused with event names.
    */
    var XEventMask = Xlib.XEventMask = {
        NoEventMask : 0,
        KeyPressMask : (1<<0),
        KeyReleaseMask : (1<<1),
        ButtonPressMask : (1<<2),
        ButtonReleaseMask : (1<<3),
        EnterWindowMask : (1<<4),
        LeaveWindowMask : (1<<5),
        PointerMotionMask : (1<<6),
        PointerMotionHintMask : (1<<7),
        Button1MotionMask : (1<<8),
        Button2MotionMask : (1<<9),
        Button3MotionMask : (1<<10),
        Button4MotionMask : (1<<11),
        Button5MotionMask : (1<<12),
        ButtonMotionMask : (1<<13),
        KeymapStateMask : (1<<14),
        ExposureMask : (1<<15),
        VisibilityChangeMask : (1<<16),
        StructureNotifyMask : (1<<17),
        ResizeRedirectMask : (1<<18),
        SubstructureNotifyMask : (1<<19),
        SubstructureRedirectMask : (1<<20),
        FocusChangeMask : (1<<21),
        PropertyChangeMask : (1<<22),
        ColormapChangeMask : (1<<23),
        OwnerGrabButtonMask : (1<<24)
    };

    /**
    Event names.  Used in "type" field in XEvent structures.  Not to be
    confused with event masks above.  They start from 2 because 0 and 1
    are reserved in the protocol for errors and replies.
    */
    var XEvents = Xlib.XEvents = {
        KeyPress : 2,
        KeyRelease : 3,
        ButtonPress : 4,
        ButtonRelease : 5,
        MotionNotify : 6,
        EnterNotify : 7,
        LeaveNotify : 8,
        FocusIn : 9,
        FocusOut : 10,
        KeymapNotify : 11,
        Expose : 12,
        GraphicsExpose : 13,
        NoExpose : 14,
        VisibilityNotify :15,
        CreateNotify : 16,
        DestroyNotify : 17,
        UnmapNotify : 18,
        MapNotify : 19,
        MapRequest : 20,
        ReparentNotify : 21,
        ConfigureNotify : 22,
        ConfigureRequest : 23,
        GravityNotify : 24,
        ResizeRequest : 25,
        CirculateNotify : 26,
        CirculateRequest : 27,
        PropertyNotify : 28,
        SelectionClear : 29,
        SelectionRequest : 30,
        SelectionNotify : 31,
        ColormapNotify : 32,
        ClientMessage : 33,
        MappingNotify : 34,
        GenericEvent : 35,
        LASTEvent : 36
    };

    /* EXPORT */
    for (name in Xlib)
        exports[name] = Xlib[name];

})(exports);

