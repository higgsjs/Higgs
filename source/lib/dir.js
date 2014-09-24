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
Functions for dealing with the filesystem
*/
(function (exports)
{
    var range = require('lib/range');
    var ffi = require('lib/ffi');
    var c = ffi.c;

    if (ffi.os === 'OSX')
    {
        c.cdef(`
            typedef unsigned int __ino_t;
            typedef unsigned short __uint16_t;
            typedef unsigned char __uint8_t;
            struct dirent
            {
                __ino_t d_ino;
                __uint16_t d_reclen;
                __uint8_t d_type;
                __uint8_t d_namlen;
                char d_name[256];
            };
        `);
    }
    else if (ffi.os === 'BSD')
    {
        c.cdef(`
            typedef unsigned int __uint32_t;
            typedef unsigned short __uint16_t;
            typedef unsigned char __uint8_t;
            struct dirent {
                __uint32_t d_fileno;
                __uint16_t d_reclen;
                __uint8_t  d_type;
                __uint8_t  d_namlen;
                char       d_name[256];
            };
        `);
    }
    else
    {
        c.cdef(`
            typedef unsigned long int __ino_t;
            typedef long int __off_t;
            struct dirent
            {
                __ino_t d_ino;
                __off_t d_off;
                unsigned short int d_reclen;
                unsigned char d_type;
                char d_name[256];
            };
        `);
    }

    c.cdef(`
        typedef struct dirent dirent;
        typedef struct __dirstream DIR;
        DIR *opendir(const char *name);
        dirent *readdir(DIR *dirp);
        void rewinddir(DIR *dirp);
        int closedir(DIR *dirp);
        int errno;
    `);

    // File types (d_type in dirent struct)
    var d_types = {
        UNKNOWN : 0,
        FIFO : 1,
        CHR : 2,
        DIR : 4,
        BLK : 6,
        REG : 8,
        LNK : 10,
        SOCK : 12,
        WHT : 14
    };

    var d_types_map = [
        'UNKNOWN', 'FIFO', 'CHR', undefined, 'DIR', undefined, 'BLK',
        undefined, 'REG', undefined,'LNG',undefined,'SOCK',undefined,'WHT'
    ];

    /**
    DirError
    @constructor
    */
    function DirError(message)
    {
        this.message = message;
    }
    DirError.prototype = new Error();
    DirError.prototype.constructor = DirError;

    /**
    HELPERS
    */
    // TODO: have lib/ffi reuse wrapper
    function getName(ent)
    {
        return c.dirent(ent).d_name.toString();
    }

    function isFile(ent)
    {
        return c.dirent(ent).get_d_type() === d_types.REG;
    }

    function isDir(ent)
    {
        return c.dirent(ent).get_d_type() === d_types.DIR;
    }

    function notDots(n) {
        return n !== '.' && n !== '..';
    }


    /**
    dirRange -
        range for all entries in a dir
    */
    function dirRange(path)
    {
        if (!this instanceof dirRange)
            return new dirRange(path);

        this.path = path;
        this.c_path = ffi.nullPtr;
        this.ptr = ffi.nullPtr;
        this._empty = true;
        return this;
    }

    dirRange.prototype = range.Input();

    /**
       start -
           open the dir
    */
    dirRange.prototype.start = function()
    {
        var dir;
        var c_path;

        // close if already open
        if (this._empty === false)
            this.end();

        // setup c path
        c_path = this.c_path = ffi.cstr(this.path);

        // open dir, error otherwise
        dir = this.ptr = c.opendir(c_path);
        if (ffi.isNullPtr(dir))
            throw new DirError('Unable to open directory: ' + this.path);

        this._empty = false;
        return this;
    };

    /**
    end -
        Close the directory and free resources
    */
    dirRange.prototype.end = function()
    {
        var c_path = this.c_path;
        var dir = this.ptr;

        if (!ffi.isNullPtr(c_path))
            c.free(c_path);

        if (!ffi.isNullPtr(dir))
            c.closedir(dir);

        this._empty = true;
        this.ptr = ffi.nullPtr;
        this.c_path = ffi.nullPtr;
        return this;
    };

    /**
    popFront -
        override the default Input.popFront() to traverse
        the directory.
    */
    dirRange.prototype.popFront = function()
    {
        // TODO: more error checking
        var ent;
        if (this._empty === true)
            this.start();

        ent = c.readdir(this.ptr);
        if (ffi.isNullPtr(ent))
        {
            this.end();
            return undefined;
        }

        this._empty = false;
        this._front = ent;
        return undefined;
    };


    /**
    dir -
        an object representing a directory with various helper methods.
    */
    function dir(path)
    {
        if (!(this instanceof dir))
            return new dir(path);
        this.path = path;
        this.range = new dirRange(path);
    }

    /**
    getFileNames -
        get an array of file names in the directory.
    */
    dir.prototype.getFileNames = function()
    {
        return this.range.filter(isFile).map(getName).toArray();
    };

    /**
    getDirNames -
        get an array of all the (sub)directory names in the directory.
    */
    dir.prototype.getDirNames = function()
    {
        return this.range.filter(isDir).map(getName).filter(notDots).toArray();
    };

    /**
    EXPORTS
    */
    exports.DirError = DirError;
    exports.dirRange = dirRange;
    exports.dir = dir;
    exports.d_types = d_types;
    exports.d_types_map = d_types_map;
    exports.isFile = isFile;
    exports.isDir = isDir;

})(exports);

