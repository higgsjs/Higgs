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
C stdlib functions
*/

(function()
{
    var ffi = require("lib/ffi");
    var io = require("lib/stdio");
    var c = ffi.c;

    c.cdef(`
        typedef unsigned int uint32_t;
        typedef unsigned long int uint64_t;
        
        void exit (int status);
        int system (const char* command);
        char* getenv (const char* name);
        FILE *popen(const char *command, const char *mode);
        void perror(const char *s);
        int chdir (const char *filename);
        typedef int pid_t;
        pid_t fork(void);
        pid_t waitpid(pid_t pid, int *status, int options);

        /* Type used for the number of file descriptors.  */
        typedef unsigned long int nfds_t;
        int poll (struct pollfd *__fds, nfds_t __nfds, int __timeout);
    `);

    /**
    Allocate memory
    */
    function malloc(size)
    {
        return c.malloc(size);
    }

    /**
    Reallocate memory
    */
    function realloc(ptr, size)
    {
        return c.realloc(ptr, size);
    }

    /**
    Free memory
    */
    function free(ptr)
    {
        return c.free(ptr);
    }

    /**
    Exit program
    */
    function exit(status)
    {
        return c.exit(status);
    }

    /**
    Execute a command
    */
    function system(command)
    {
        var c_cmd = ffi.cstr(command);
        var result = c.system(c_cmd);
        c.free(c_cmd);
        return result;
    }

    /**
    Get an environmental variable
    */
    function getenv(name)
    {
        var c_name = ffi.cstr(name);
        var result = c.getenv(c_name);
        c.free(c_name);
        return ffi.string(result);
    }


    var r_mode = ffi.cstr("r");
    var w_mode = ffi.cstr("w");

    /**
    Execute a command and return a stream
    */
    function popen(command, mode)
    {
        var c_mode;
        var c_cmd = ffi.cstr(command);
        mode = mode.toLowerCase();

        if (mode === "r")
            c_mode = r_mode;
        else if (mode === "w")
            c_mode = w_mode;
        else
            throw "Invalide popen mode: " + mode;

        var streamh = c.popen(c_cmd, c_mode);
        c.free(c_cmd);
        c.free(c_mode);

        if (ffi.isNull(streamh))
            throw "Error calling popen with:" + command;

        return io.stream(streamh, "popen_sh");
    }

    function perror(msg)
    {
        var c_msg = ffi.cstr(msg);
        c.perror(c_msg);
        c.free(c_msg);
        return;
    }

    function chdir(dir_name)
    {
        var c_dir_name = ffi.cstr(dir_name);
        var success = c.chdir(c_dir_name);
        c.free(c_dir_name);
        // TODO: check for error here?
        return success;
    }

    exports = {
        malloc : malloc,
        realloc : realloc,
        free : free,
        exit : exit,
        system : system,
        getenv : getenv,
        popen : popen,
        chdir : chdir,
        perror : perror
    };

})();
