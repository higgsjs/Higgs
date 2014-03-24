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
Functions for dealing with the filesystem
*/

(function ()
{
    var ffi = require("lib/ffi");

    var c = ffi.c;

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

    /**
    @constructor
    */
    function dir(path)
    {
        this.path = path;
        this.handle = this.open();
    }

    dir.prototype.open = function()
    {
        var c_path = ffi.cstr(this.path);
        var dir = c.opendir(c_path);
        c.free(c_path);
        if (ffi.isNullPtr(dir))
            throw "Unable to open directory: " + this.path;
        return dir;
    };

    dir.prototype.forEach = function(cb)
    {
        var ent;
        var dname;

        while (!ffi.isNullPtr(ent = c.readdir(this.handle)))
        {
            ent = c.dirent(ent);
            dname = ent.d_name.toString();

            if (dname === '.' || dname === '..')
                continue;
            cb.call(this, dname, ent);
        }

        c.rewinddir(this.handle);
    };

    dir.prototype.getDirs = function()
    {
        var ent;
        var dname;
        var dirs = [];

        while (!ffi.isNullPtr(ent = c.readdir(this.handle)))
        {
            ent = c.dirent(ent);
            dname = ent.d_name.toString();

            if (dname === '.' || dname === '..')
                continue;

            if (isDir(ent))
                dirs.push(dname);
        }

        c.rewinddir(this.handle);
        return dirs;
    };

    dir.prototype.getFiles = function()
    {
        var ent;
        var dname;
        var files = [];

        while (!ffi.isNullPtr(ent = c.readdir(this.handle)))
        {
            ent = c.dirent(ent);
            dname = ent.d_name.toString();

            if (dname === '.' || dname === '..')
                continue;

            if (isFile(ent))
                files.push(dname);
        }

        c.rewinddir(this.handle);
        return files;
    };

    function isFile(ent)
    {
        return ent.get_d_type() === d_types.REG;
    }

    function isDir(ent)
    {
        return ent.get_d_type() === d_types.DIR;
    }

    exports = {
        dir : function(path) { return new dir(path); },
        d_types: d_types,
        isFile: isFile,
        isDir: isDir
    };
})();
