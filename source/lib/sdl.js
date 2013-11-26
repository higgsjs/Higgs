(function(){
    var ffi = require("lib/ffi");
    var sdl = ffi.load("/usr/lib/x86_64-linux-gnu/libSDL2.so");

    // TODO: organize/comment
    sdl.cdef([
        "typedef unsigned int uint32_t;",
        "typedef uint32_t Uint32;",
        "typedef struct SDL_PixelFormat SDL_PixelFormat;",
        "struct SDL_Rect\
         {\
            int x;\
            int y;\
            int w;\
            int h;\
         };",
        "typedef struct SDL_Rect SDL_Rect;",
        "struct SDL_Surface\
         {\
            Uint32 flags;\
            SDL_PixelFormat *format;\
            int w;\
            int h;\
            int pitch;\
            void *pixels;\
            void *userdata;\
            int locked;\
            void *lock_data;\
            SDL_Rect clip_rect;\
            struct SDL_BlitMap *map;\
            int refcount;\
         };",
        "typedef struct SDL_Surface SDL_Surface;",
        "typedef struct SDL_Window SDL_Window;",
        "int SDL_Init(int flags);",
        "SDL_Window * SDL_CreateWindow(const char *title, int x, int y, int w, int h, Uint32 flags);",
        "SDL_Surface * SDL_GetWindowSurface(SDL_Window * window);",
        "typedef struct SDL_RWops SDL_RWops;",
        "SDL_Surface *SDL_LoadBMP_RW(SDL_RWops *src, int freesrc);",
        "SDL_RWops *SDL_RWFromFile(const char *file, const char *mode);",
        // note this is wrong:
        "typedef Uint32 SDL_Event;",
        "int SDL_PollEvent(SDL_Event * event);",
        "int SDL_UpperBlit(SDL_Surface * src, const SDL_Rect * srcrect, SDL_Surface * dst, SDL_Rect * dstrect);",
        // ok:
        "int SDL_UpdateWindowSurface(SDL_Window * window);",
        "void SDL_Quit(void);",
        "void SDL_DestroyWindow(SDL_Window * window);",
        "void SDL_FreeSurface(SDL_Surface * surface);"
    ]);

    function init(flags)
    {
        // TODO: allow passing multiple flags
        var cflags = _init[flags];
        if (cflags == null)
            throw "Error: invalid flags in sdl.init()";
        var result = sdl.SDL_Init(cflags);
        return result <= 0;
    };

    var _init = {
        timer: 0x00000001,
        audio: 0x00000010,
        video: 0x00000020,
        joystick: 0x00000200,
        haptic: 0x00001000,
        gamecontroller: 0x00002000,
        events: 0x00004000,
        noparachute: 0x00100000,
        everything: (0x00000001 | 0x00000010 |  0x00000020 |  0x00004000 |
                     0x00000200 | 0x00001000 |  0x00002000)
                     /* SDL_INIT_TIMER | SDL_INIT_AUDIO | SDL_INIT_VIDEO | SDL_INIT_EVENTS | 
                                  SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC | SDL_INIT_GAMECONTROLLER */
    };

    // special flags
    var WINDOWPOS_CENTERED = 0x2FFF0000;
    var SDL_WINDOW_SHOWN = 0x00000004;

    function createWindow(title)
    {
        var ctitle = ffi.cstr(title);
        var win = sdl.SDL_CreateWindow(ctitle, 500, 500, 320, 240, SDL_WINDOW_SHOWN);
        //ffi.c.free(ctitle);
        return win;
    }

    var rw = ffi.cstr("rw");

    function LoadBMP(file)
    {
        var cfile = ffi.cstr(file);
        return sdl.SDL_LoadBMP_RW(sdl.SDL_RWFromFile(cfile, rw), 1);
    }

    var evt = {
        quit: 0x100
    };

    function quit()
    {
        sdl.SDL_Quit();
    }

    exports = {
        lib: sdl,
        init: init,
        _init: _init,
        createWindow: createWindow,
        loadBMP: LoadBMP,
        evt: evt,
        quit: quit
    };
})();
