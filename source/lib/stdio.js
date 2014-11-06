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
Bindings for common c I/O functions
*/

(function(exports)
{
    /**
    DEPENDENCIES/SETUP
    */

    var ffi = require('lib/ffi');
    var c = ffi.c;

    // TODO: NOTE: size_t should be long int
    c.cdef(`
        typedef int size_t;

        typedef struct _IO_FILE FILE;

        FILE *fopen( const char *filename, const char *mode );
        FILE *fdopen( int fildes, const char *mode );
        int fflush( FILE *stream );
        int fclose( FILE *stream );

        int fgetc( FILE *stream );
        int ungetc( int ch, FILE *stream );

        char *fgets( char *str, int count, FILE *stream );
        size_t fread( void *buffer, size_t size, size_t count, FILE *stream );

        long ftell( FILE *stream );
        int fseek( FILE *stream, long offset, int origin );
        void rewind( FILE *stream );
        int feof( FILE *stream );
        size_t fwrite( const void *buffer, size_t size, size_t count, FILE *stream );
        int fputc( int ch, FILE *stream );
        int remove( const char *fname );
        int rename( const char *old_filename, const char *new_filename );
        char *tmpnam( char *filename );
        FILE *tmpfile();
    `);


    // FFI can't handle printf yet
    c.cfun('printf', 'i32,*');

    // The object for this module
    var io = {};

    // Default settings
    io.BUF_SIZE = 2048;

    // Constants
    io.SEEK_SET = 0;
    io.SEEK_END = 2;

    /**
    FILE OBJECT
    */

    /**
    File
    @Constructor
    */
    function File(file, mode)
    {
        // The file to open
        this.file = file;
        // A name for the object, usually same as file
        this.name = file;
        // What mode to open the file in
        this.mode = mode;
        // The size of the buffer used in various string operations
        this.buf_size = io.BUF_SIZE;
        // Ptr for buffer
        this.buffer = c.malloc(io.BUF_SIZE);

        // Pass null for dummy file object
        if (file === null && mode === undefined)
            return;

        // Open
        var cfile = ffi.cstr(file);
        var cmode = ffi.cstr(mode);
        var fh = c.fopen(cfile, cmode);
        c.free(cfile);
        c.free(cmode);

        if (ffi.isNullPtr(fh))
            throw 'Unable to open file. Mode: \'' + mode + '\' File: \'' + file + '\'';

        this.ptr = fh;
    }

    /**
    Wrap a file-like stream
    */
    function stream(ptr, name)
    {
        var s = new File(null);
        s.stream = true;
        s.name = name || 'stream';
        s.ptr = ptr;
        return s;
    }

    /**
    Resize the buffer used for various string operations.
    */
    File.prototype.resizeBuf = function(size)
    {
        var b = c.realloc(this.buffer, size);
        if (ffi.isNullPtr(b))
            throw 'Unable to resize buffer.';
        this.buffer = b;
        this.buf_size = size;
    };

    /**
    Close this file.
    Return true for success, false for failure
    */
    File.prototype.close = function()
    {
        if (ffi.isNullPtr(this.ptr) || this.file === null)
            throw 'Cannot close file: ' + this.name;

        // Close, return false if it fails
        var r = c.fclose(this.ptr);
        if (r !== 0)
            return false;

        // Free resources
        c.free(this.buffer);
        this.ptr = ffi.nullPtr;

        return true;
    };

    /**
    Flush the file.
    Return true for success, false for failure
    */
    File.prototype.flush = function()
    {
        if (ffi.isNullPtr(this.ptr))
            throw 'Cannot flush file: ' + this.name;
        var r = c.fflush(this.ptr);
        return (r === 0);
    };


    /**
    Check if the next char is EOF.
    */
    File.prototype.EOF = function()
    {
        var chr = c.fgetc(this.ptr);
        c.ungetc(chr, this.ptr);
        return (chr < 0);
    };

    /**
    Get current position in file.
    */
    File.prototype.tell = function()
    {
        return c.ftell(this.ptr);
    };

    /**
    Seek position in file. Return true if successful, false otherwise.
    */
    File.prototype.seek= function(offset, origin)
    {
        origin = (origin > -1 && origin < 3) ? origin : 0;
        var r = c.fseek(this.ptr, offset, origin);
        return (r === 0);
    };

    /**
    Rewind back to beginning.
    */
    File.prototype.rewind = function()
    {
        c.rewind(this.ptr);
    };

    /**
    Get a char.
    */
    File.prototype.getc = function()
    {
        // TODO: skip null chars?
        var chr = c.fgetc(this.ptr);
        return (chr > -1) ? String.fromCharCode(chr) : '';
    };

    /**
    Read a uint8
    */
    File.prototype.readUint8 = function()
    {
        var len = c.fread(this.buffer, 1, 1, this.ptr);
        if (len === 0)
            return NaN;
        return $ir_load_u8(this.buffer, 0);
    };

    /**
    Read a uint16
    */
    File.prototype.readUint16 = function()
    {
        var len = c.fread(this.buffer, 2, 1, this.ptr);
        if (len === 0)
            return NaN;
        return $ir_load_u16(this.buffer, 0);
    };

    /**
    Read a uint32
    */
    File.prototype.readUint32 = function()
    {
        var len = c.fread(this.buffer, 4, 1, this.ptr);
        if (len === 0)
            return NaN;
        return $ir_load_u32(this.buffer, 0);
    };

    /**
    Read a float64
    */
    File.prototype.readFloat64 = function()
    {
        var len = c.fread(this.buffer, 8, 1, this.ptr);
        if (len === 0)
            return NaN;
        return $ir_load_f64(this.buffer, 0);
    };

    /**
    Read a line
    If max is non-negative, only read (up to) max bytes.
    */
    File.prototype.readLine = function(max)
    {
        var str;
        var len;
        var limit = (max > -1);

        if (!limit)
            max = this.buf_size;
        else if (max > this.buf_size)
            this.resizeBuf(max);

        var line = c.fgets(this.buffer, max, this.ptr);

        // Handle cases where line fits within buf_size/max or could not be read
        if (ffi.isNullPtr(line))
            return '';

        len = c.strlen(line);

        if ($ir_load_u8(line, len - 1) === 10 || limit)
            return ffi.string(line, len);

        // Handle cases where line does not fit within buf_size
        str = ffi.string(line, len);

        do {
            line = c.fgets(this.buffer, max, this.ptr);
            if (ffi.isNullPtr(line))
                return str;
            len = c.strlen(line);
            str += ffi.string(line, len);
        } while ($ir_load_u8(line, len - 1) !== 10);

        return str;
    };

    /**
    Read from a file.
    If max is non-negative, only read (up to) max bytes.
    Otherwise read entire file.
    */
    File.prototype.read = function(max)
    {
        var str;
        var len;
        var limit = (max > -1);

        // Handle read(size)
        if (limit)
        {
            if (max > this.buf_size)
                this.resizeBuf(max);
            len = c.fread(this.buffer, 1, max, this.ptr);
            return ffi.string(this.buffer, len);
        }

        // Handle read() entire file
        max = this.buf_size;
        str = '';
        do {
            len = c.fread(this.buffer, 1, max, this.ptr);
            str += ffi.string(this.buffer, len);
        } while (c.feof(this.ptr) === 0);

        return str;
    };

    /**
    Put char to a file.
    */
    File.prototype.putc = function(chr)
    {
        var code = $rt_str_get_data(chr, 0);
        var r;
        r = c.fputc(code, this.ptr);
        return (r === code);
    };

    /**
    Write a uint8
    */
    File.prototype.writeUint8 = function(data)
    {
        var size = 1;
        $ir_store_u8(this.buffer, 0, data);
        var r = c.fwrite(this.buffer, size, 1, this.ptr);
        return r === size;
    };

    /**
    Write a int8
    */
    File.prototype.writeInt8 = function(data)
    {
        var size = 1;
        $ir_store_i8(this.buffer, 0, data);
        var r = c.fwrite(this.buffer, size, 1, this.ptr);
        return r === size;
    };

    /**
    Write a int16
    */
    File.prototype.writeInt16 = function(data)
    {
        var size = 2;
        $ir_store_i16(this.buffer, 0, data);
        var r = c.fwrite(this.buffer, size, 1, this.ptr);
        return r === size;
    };

    /**
    Write a uint16
    */
    File.prototype.writeUint16 = function(data)
    {
        var size = 2;
        $ir_store_u16(this.buffer, 0, data);
        var r = c.fwrite(this.buffer, size, 1, this.ptr);
        return r === size;
    };

    /**
    Write a int32
    */
    File.prototype.writeInt32 = function(data)
    {
        var size = 4;
        $ir_store_i32(this.buffer, 0, data);
        var r = c.fwrite(this.buffer, size, 1, this.ptr);
        return r === size;
    };

    /**
    Write a uint32
    */
    File.prototype.writeUint32 = function(data)
    {
        var size = 4;
        $ir_store_u32(this.buffer, 0, data);
        var r = c.fwrite(this.buffer, size, 1, this.ptr);
        return r === size;
    };

    /**
    Write a float64
    */
    File.prototype.writeFloat64 = function(data)
    {
        var size = 8;
        $ir_store_f64(this.buffer, 0, data);
        var r = c.fwrite(this.buffer, size, 1, this.ptr);
        return r === 1;
    };

    /**
    Write text data to a file
    */
    File.prototype.write = function(data)
    {
        data = String(data);

        var max = data.length;
        if (max > this.buf_size)
            this.resizeBuf(max + 1);

        ffi.jsstrcpy(this.buffer, data);
        var r = c.fwrite(this.buffer, 1, max, this.ptr);

        return r === max;
    };

    /**
    WRAPPERS/EXPORT
    **/
    io.stream = stream;

    // File object for stdin
    io.stdin = stream(c.fdopen(0, ffi.cstr('r')));

    // File object for stdout
    io.stdout = stream(c.fdopen(1, ffi.cstr('w')));

    // File object for stderr
    io.stderr = stream(c.fdopen(2, ffi.cstr('w')));

    /**
    Open a file
    */
    io.fopen = function(file, mode)
    {
        return new File(file, mode);
    };

    /**
    Read an entire file into a string
    */
    io.readFile = function(file)
    {
        var f = new File(file, 'r');
        var str = f.read();
        f.close();
        return str;
    };

    /**
    Delete a file
    */
    io.remove = function(file)
    {
        var name = ffi.cstr(file);
        var r = c.remove(name);
        c.free(name);
        return (r === 0);
    };

    /**
    Rename a file
    */
    io.rename = function(oldfile, newfile)
    {
        var o = ffi.cstr(oldfile);
        var n = ffi.cstr(newfile);
        var r = c.rename(o, n);
        c.free(o);
        c.free(n);
        return (r === 0);
    };

    /**
    Get a tmpfile
    */
    io.tmpfile = function()
    {
        var file = c.tmpfile();
        var r;
        if(ffi.isNullPtr(file))
            throw 'Unable to get tmp file.';

        r = new File(null);
        r.ptr = file;
        r.mode = 'wb+';
        r.name = 'TMPFILE';
        r.file = 'TMPFILE';
        return r;
    };

    /**
    Get a tmpname
    */
    io.tmpname = function()
    {
        var buf = c.malloc(128);
        var name = c.tmpnam(buf);
        if(ffi.isNullPtr(name))
            throw 'Unable to get temp name.';
        name = ffi.string(buf);
        c.free(buf);
        return name;
    };

    /**
    Print (without added newline)
    */
    io.print = function(x)
    {
        var str = ffi.cstr(x);
        c.printf(str);
        c.free(str);
    };

    // Export all definitions in io
    for (name in io)
        exports[name] = io[name];

})(exports);

