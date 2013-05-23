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
The Higgs FFI api
*/
(function()
{

    /**
    UTILITY FUNCTIONS
    */

    // Arg strings are used in the generation of function wrappers for FFI calls
    var arg_strings = ["", " a "];
    var arg_names = "abcdefghijklmnopqrstuvwxyzABCDEFG";

    /**
    Generate/Get an arg string for the # of arguments
    */
    function getArgString(len)
    {
        if (arg_strings[len] !== undefined)
            return arg_strings[len]

        var arg_string = "a";
        for (var i = 1; i < len; i++)
            arg_string += ", " + arg_names[i];
        arg_string += " ";
        arg_strings[len] = arg_string;
        return arg_string
    }


    /**
    FFILibrary
    @Constructor
    Wrapper for loaded shared libs.
    */
    function FFILibrary(name)
    {
        // Pass null to create a dummy library
        if (name !== null)
            this.handle = $ir_load_lib(name);
        this.symbols = {};
    }

    /**
    Lookup a symbol in the lib.
    */
    FFILibrary.prototype.getSym = function(name)
    {
        if (this.symbols.hasOwnProperty(name))
            return this.symbols[name];

        var fun = ["function(libhandle)",
                   "{",
                   "    return $ir_get_sym(libhandle, \"" + name + "\");",
                   "}"
                  ].join(" ");

        var sym = eval(fun)(this.handle);
        this.symbols[name] = sym;
        return sym;
    }

    /**
    Generate a wrapper function to call a function in the lib.
    */
    FFILibrary.prototype.fun = function(fname, sig)
    {
        // Some ir functions expect string constants, so they must be
        // constructed as strings and eval'd.
        var args = getArgString(sig.split(",").length - 1);
        var fun = ["function(", args, ")",
                   "{",
                   "    var sym = this.symbols[", ('"' + fname + '"'), "];",
                   "    return $ir_call_ffi(null, sym, ", ('"' + sig + '"'),
                    (args === "" ? "" : (", " + args)),
                    ");",
                   "}"
                  ].join(" ");
        this.getSym(fname);
        this[fname] = eval(fun);
    }

    /**
    Generate a wrapper function to lookup a value in the lib.
    */
    FFILibrary.prototype.symbol = function(symname, sig)
    {
        // TODO: handle more types
        if (sig !== "*")
            throw "Unhandled type in symbol()"

        var fun = ["function()",
                   "{",
                   "    var sym = this.symbols[", ('"' + symname + '"'), "];",
                   "    return $ir_load_rawptr(sym, 0);",
                   "}"
                  ].join(" ");
        this.getSym(symname);
        this[symname] = eval(fun);
    }

    /**
    Take a list of C style declarations and automatically create bindings for them.
    */
    FFILibrary.prototype.cdef = cdef;

    /**
    Close the library.
    */
    FFILibrary.prototype.close = function()
    {
        $ir_close_lib(this.handle);
    }

    /**
    STDLIB
    */

    // A wrapper for the global symbol object is included
    // since it will probably be used often
    var c = new FFILibrary("");

    // Functions used by the FFI library
    c.fun("malloc", "*,i32");
    c.fun("realloc", "*,*,i32");
    c.fun("free", "void,*");
    c.fun("strlen", "i32,*");

    /**
    TYPE UTILTIY FUNCTIONS
    */

    // Used in some conversions
    var NullPtr = $ir_set_rawptr(0);

    /**
    Create a C string from a JS string.
    */
    function cstr(str, len)
    {
        var cstr;
        len = len || str.length;
        cstr = c.malloc(len + 1);

        for (var i = 0; i < len; i++)
            $ir_store_u8(cstr, i, $rt_str_get_data(str, i));

        $ir_store_u8(cstr, len, 0);
        return cstr;
    }

    /**
    Copy a JS string to a c buffer.
    */
    function jstrcpy(buff, jstr, len)
    {
        len = len || jstr.length;

        for (var i = 0; i < len; i++)
            $ir_store_u8(buff, i, $rt_str_get_data(jstr, i));

        $ir_store_u8(buff, len, 0);
        return buff;
    }

    /**
    Create a JS string from a C string.
    If n is non-zero copy only n chars from the C string.
    */
    function string(cstr, n)
    {
        var s;
        var len = 0;

        // Get the length
        if (n)
        {
            len = n;
        }
        else
        {
            while ($ir_load_u8(cstr, len++) !== 0);
            len -= 1;
        }

        // Allocate string
        s = $rt_str_alloc(len);

        // Copy
        for (var i = 0; i < len; i++)
            $rt_str_set_data(s, i, $ir_load_u8(cstr, i));

        // Attempt to find the string in the string table
        return $ir_get_str(s);
    }

    /**
    Create a buffer.
    */
    function cbuffer(len)
    {
        return c.malloc(len);
    }

    /**
    Check for a null word value (useful for checking null ptrs)
    */
    function isNull(x)
    {
        return $ir_get_word(x) === 0;
    }



    /**
    CDEFS
    */

    /**
    TOKENIZER
    */

    /**
    Split an input string into an array of token strings.
    */
    function tokenize(input)
    {
        var end = input.length;
        var chr = 0;
        var cursor = 0;
        var tokens = [];
        var tok = c.malloc(200);
        var tok_cursor = 0;
        var counter = 0;

        do {

            chr = $rt_str_get_data(input, cursor);

            // Eat whitespace
            while ((chr >= 9 && chr <= 13) || (chr === 32) ||
                   (chr === 160) || (chr >= 8192 && chr <= 8202) ||
                   (chr === 8232) || (chr === 8233) ||
                   (chr === 8239) || (chr === 8287) ||
                   (chr === 12288) || (chr === 65279))
            {
                cursor +=1;
                chr = $rt_str_get_data(input, cursor);
            }

            // ( [ {
            if (chr === 40 || chr === 91 || chr ===123)
            {
                counter += chr - (chr % 10);
                tokens.push(input[cursor])
                cursor += 1;
                continue;
            }

            // ) ] }
            if (chr === 41 || chr === 93 || chr ===125)
            {
                counter -= chr - (chr % 10);
                tokens.push(input[cursor])
                cursor += 1;
                continue;
            }

            // ; * ,
            if (chr === 59 || chr === 42 || chr ===44)
            {
                tokens.push(input[cursor])
                cursor += 1;
                continue;
            }

            // Anything not ()[]{},;_ or Alphanumeric/Whitespace is invalid
            if (!((chr > 64 && chr < 91) ||
                   (chr > 96 && chr < 123) ||
                   (chr > 47 && chr < 58) ||
                   (chr === 95)))
                throw "Invalid character: " + input[cursor];

            // Alphanumeric and _
            while ((chr > 64 && chr < 91) ||
                   (chr > 96 && chr < 123) ||
                   (chr > 47 && chr < 58) ||
                   (chr === 95))
            {
                $ir_store_u8(tok, tok_cursor, chr);
                tok_cursor += 1;
                cursor += 1;
                chr = $rt_str_get_data(input, cursor);
            }

            $ir_store_u8(tok, tok_cursor, 0);
            tokens.push(string(tok, tok_cursor));
            tok_cursor = 0;

        } while (cursor < end);

        c.free(tok);

        if (counter !== 0)
            throw "Unbalanced (), [], or {} in declaration:\n" + input;
        return tokens;
    }


    /**
    PARSER
    */

    /**
    TYPES
    */

    // Mapping of C types to the low-level FFI type markers.
    var type_map = {
        // all pointers
        "*" : "*",
        // void
        "void" : "void",
        "char" : "i8",
        // int
        "int" : "i32",
        // double
        "double" : "f64",
        // TODO: these are wrong
        "long" : "i32",
        "size_t" : "i32"
    }

    /**
    Get the type binding power of a token.
    */
    function typeP(t)
    {
        // Any given token has a "type binding power"
        // 3 all pointer types are all treated as void*
        if (t === "*")
            return 3;
        // 2 all supported short and long types are interchangeable 
        if (t === "short" || t === "long")
            return 2;
        // 1 it's a known type
        if (type_map.hasOwnProperty(t))
            return 1;
        // 0 it's not a known type
        return 0;
    }

    /**
    Convert all types in a body to Higgs FFI type.
    */
    function mapTypes(body)
    {
        var type;
        var i = body.length;
        while (i-- > 1)
        {
            type = body[i];
            if (type === "*")
                continue;
            if (type_map.hasOwnProperty(type))
                body[i] = type_map[type];
            else
                throw "Unknown type: " + type;
        }
    }


    /**
    Helpers
    */

    /**
    Check if a token is a terminator.
    */
    function isTerm(token)
    {
        return (token === "," || token === ";" ||
                token === ")" || token === "}" || token === "]");
    }

    /**
    Check if a token is an l-terminator.
    */
    function isLTerm(token)
    {
        return (token === "(" || token === "{" || token ==- "[");
    }

    /**
    Check if a token is an identifier.
    */
    function isIdent(token)
    {
        return (!typeP(token) && !isTerm(token) && !isLTerm(token));
    }


    /**
    Info for declaration
    */

    // Tokens for declaration
    var tokens;
    // Length of declaration
    var end;
    // Current position
    var index;
    // Current name
    var name;
    // Current type
    var type;
    // Current type binding power
    var type_p;
    // Body for the declaration
    var body;

    /**
    Skip to the next instance of the given token.
    */
    function skipTo(to)
    {
        index += 1;
        while (tokens[index++] !== to) ;
    }

    /**
    Get next type taking type binding power into account.
    */
    function getType(i)
    {
        var token;
        var b = 0;
        do
        {
            token = tokens[i++];
            b = typeP(token);

            if (b === 0 || b < type_p)
                continue;

            // long double type is not currently supported
            if (token === "double" && type === "long")
                throw "Unsupported type: long double.";

            type = token;
            index = i;
            type_p = b;
        } while (!isTerm(token) && !isLTerm(token));
    }


    /**
    Parse a declaration for either a variable or a function.
    */
    function parseVar()
    {
        var token;
        name = undefined;
        type = undefined;
        type_p = 0;

        while ((!type || !name) && index < end)
        {
            getType(index);
            token = tokens[index++];
            if (token === ")")
                break;
            if (isIdent(token))
                name = token;
        }

        return (!!name && !!type);
    }

    /**
    Parse the arguments to a function.
    */
    function parseArgs()
    {
        var token;

        while(index < end)
        {
            token = tokens[index];

            if (!parseVar())
                break;

            body.push(type);
            token = tokens[index];

            if (token === ")" && tokens[index + 1] === "(")
                skipTo(")");

            if (token !== "," && token !== ")")
                throw "Error: expected , or ) after " +
                    tokens[index - 1] + ".";
        }

        if (!type && token !== ")")
            throw "Error: expected ) after " +
                    tokens[index - 1] + ".";

        return;
    }

    /**
    Parse a declaration
    */
    function parseDec(input, lib)
    {
        tokens = tokenize(input);
        end = tokens.length;
        index = 0;
        name = undefined;
        type = undefined;
        type_p = 0;
        body = [];

        if (parseVar())
        {
            body.push(name);
            body.push(type);

            // If it's a function
            if (tokens[index] == "(")
            {
                parseArgs(++index);
                mapTypes(body);
                lib.fun(body.shift(), body.join(","));
                return;
            }

            // Otherwise, it's a var declaration.
            mapTypes(body);
            lib.symbol(body[0], body[1]);
            return;
        }

        throw "Unable to parse declaration.";
        return;
    }

    /**
    Take a list of C style declarations and automatically create bindings for them.
    */
    function cdef(defs)
    {

        var def, sig;

        // Loop through defs
        for (var i = 0, l = defs.length; i < l; i++)
        {
            def = defs[i];
            parseDec(def, this);
        }
    }


    /**
    EXPORTS
    */

    exports = {
        cstr : cstr,
        string : string,
        jstrcpy : jstrcpy,
        cbuffer : cbuffer,
        isNull : isNull,
        NullPtr : NullPtr,
        c : c,
        load : function(name) { return new FFILibrary(name) }
    }

})();

