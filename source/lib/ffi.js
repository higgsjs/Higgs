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
    CDEFS
    */

    /**
    Take a list of C style declarations and create bindings for them.
    */
    function cdef(defs)
    {

        var def, sig, i, l;

        // Loop through defs
        for (i = 0, l = defs.length; i < l; i++)
        {
            def = defs[i];
            handleDec(def, this);
        }
    }


    /**
    Constants
    */

    // ( [ {
    var OPEN_ROUND = 40;
    var OPEN_SQUARE = 91;
    var OPEN_CURLY = 123;
    // ) ] }
    var CLOSE_ROUND = 41;
    var CLOSE_SQUARE = 93;
    var CLOSE_CURLY = 125;
    // ; * ,
    var SEMI_COLON = 59;
    var STAR = 42;
    var COMMA = 44;


    /**
    Types
    */

    // A mapping of known type names to type values (string or object)
    var types = {
        // void
        "void" : "void",
        // int types
        "char" : "char",
        "int" : "int",
        "signed" : "signed",
        "unsigned" : "unsigned",
        "long" : "long",
        "short" : "short",
        // double
        "double" : "double"
    };

    // Mapping of C types to the low-level FFI type markers.
    var type_map = {
        "*" : "*",
        "void" : "void",
        "char" : "i8",
        "short" : "i16",
        "int" : "i32",
        "long" : "i64",
        "double" : "f64"
    };

    // Mapping of type to size
    var size_map = {
        "char" : 1,
        "short" : 2,
        "int" : 4,
        "long" : 8,
        "*" : 8,
        "double" : 8
    };

    // TODO: more wrappers?
    var load_map = {
        "char" : function (handle, offset) { return $ir_load_u8(handle, offset); },
        "short" : function (handle, offset) { return $ir_load_u16(handle, offset); },
        "int" : function (handle, offset) { return $ir_load_u32(handle, offset); },
        "long" : function (handle, offset) { return $ir_load_u64(handle, offset); },
        "*" : function (handle, offset) { return $ir_load_rawptr(handle, offset); },
        "double" : function (handle, offset) { return $ir_load_f64(handle, offset); }
    };

    var store_map = {
        "char" : function (handle, offset, value) { return $ir_store_u8(handle, offset, value); }
    };

    var array_wrappers = {
        "char" : new FFIArray("char")
    };

    var load_op_map = {
        "char" : "$ir_load_u8",
        "short" :"$ir_load_u16",
        "int" : "$ir_load_u32",
        "long" : "$ir_load_u64",
        "*" :  "$ir_load_rawptr",
        "double" : "$ir_load_f64"
    };

    var store_op_map = {
        "char" : "$ir_store_u8",
        "short" :"$ir_store_u16",
        "int" : "$ir_store_u32",
        "long" : "$ir_store_u64",
        "*" :  "$ir_store_rawptr",
        "double" : "$ir_store_f64"
    };


    /**
    Parser State
    */

    // Input text
    var input;
    // Input tokens
    var tokens;
    // Position in token stream
    var index;
    // Current token
    var tok;


    /**
    Binding Functions
    */

    /**
    Handle a declaration. Entry point from cdef().
    */
    function handleDec(inp, lib)
    {
        // Reset parser state
        input = inp;
        tokens = tokenize();
        index = 0;
        tok = tokens[index];

        // Parse
        var dec = parseDeclaration();
        dec = getTopDec(dec);

        // Handle
        if (dec.typedef)
            handleTypeDef(dec, lib);
        else if (dec.str_or_uni)
        {
            handleTypeDef(dec); // TODO: change this
            lib[dec.type.name] = FFIStruct(dec);
        }
        else if (dec.fun)
        {
            lib.fun(dec.name, getFunSig(dec));
        }
        else
            lib.symbol(dec.name, getTypeMarker(dec));

        return dec;
    }

    /**
    Parse a declaration, used for testing.
    */
    function testParse(inp)
    {
        // Reset parser state
        input = inp;
        tokens = tokenize();
        index = 0;
        tok = tokens[index];

        // Parse
        var dec = parseDeclaration();
        dec = getTopDec(dec);
        return dec;
    }

    /**
    Add a type def to the list of known types.
    */
    function handleTypeDef(dec, lib)
    {
        types[dec.name] = dec.type;
        //TODO: create array wrappers?
        if (dec.array)
            lib[dec.name] = FFIArray(dec.type, dec.size || 0);
    }

    /**
    Get the top most declaration.
    */
    function getTopDec(dec)
    {
        var d = dec;

        while(d.dec)
            d = d.dec;

        return d;
    }

    /**
    Return the function signatrue (in string form) from a declaration.
    */
    function getFunSig(dec)
    {

        var sig = [];
        var args = dec.args;
        var i = -1;
        var l = (args) ? args.length : 0;

        if (dec.ptr)
            sig.push("*");
        else
            sig.push(getTypeMarker(getTopDec(dec.type)));

        while (++i < l)
            sig.push(getTypeMarker(getTopDec(args[i])));

        return sig.join(',');
    }

    /**
    Get a low-level type name for a type.
    */
    function getTypeMarker(type)
    {
        var mark;

        // TODO: more error checking
        if (type.ptr)
        {
            return "*";
        }
        else if (typeof type === "string")
        {
            if (type === "struct")
                ParseError("Invalid use of struct");
            else if (type === "union")
                ParseError("Invalid use of union");
            else if (!type_map.hasOwnProperty(type))
                ParseError("Unkown type " + type);

            mark = type_map[type];
            if (typeof mark === "string")
                return mark;
            else
                return getTypeMarker(mark);
        }
        else if (typeof type !== "object")
        {
            ParseError();
        }
        else
        {
            return getTypeMarker(type.type);
        }

        return null;
    }


    /**
    Helper Functions
    */

    /**
    Move to next token.
    */
    function advance(val)
    {
        tok = tokens[++index];
        return val;
    }

    /**
    Throw an error.
    */
    function ParseError(msg)
    {
        msg = msg || "Unable to parse declaration";
        throw "CDefParseError: '" + msg + "' in '" + input + "'.";
    }

    /**
    Split an input string into an array of token strings.
    */
    function tokenize()
    {
        var end = input.length;
        var chr = 0;
        var cursor = 0;
        var tokens = [];
        var tok = c.malloc(128);
        var tok_cursor = 0;
        var round_counter = 0;
        var square_counter = 0;
        var curly_counter = 0;

        do
        {
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
            if (chr === OPEN_ROUND)
            {
                round_counter += 1;
                tokens.push(chr);
                cursor += 1;
                continue;
            }

            if (chr === OPEN_SQUARE)
            {
                square_counter += 1;
                tokens.push(chr);
                cursor += 1;
                continue;
            }

            if (chr === OPEN_CURLY)
            {
                curly_counter += 1;
                tokens.push(chr);
                cursor += 1;
                continue;
            }

            // ) ] }
            if (chr === CLOSE_ROUND)
            {
                round_counter -= 1;
                tokens.push(chr);
                cursor += 1;
                continue;
            }

            if (chr === CLOSE_SQUARE)
            {
                square_counter -= 1;
                tokens.push(chr);
                cursor += 1;
                continue;
            }

            if (chr === CLOSE_CURLY)
            {
                curly_counter -= 1;
                tokens.push(chr);
                cursor += 1;
                continue;
            }

            // ; * ,
            if (chr === SEMI_COLON || chr === STAR || chr === COMMA)
            {
                tokens.push(chr);
                cursor += 1;
                continue;
            }

            // Anything not ()[]{},;_ or Alphanumeric/Whitespace is invalid
            if (!((chr > 64 && chr < 91) ||
                   (chr > 96 && chr < 123) ||
                   (chr > 47 && chr < 58) ||
                   (chr === 95)))
                ParseError("Invalid Character: " + input[cursor]);

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

        }
        while (cursor < end);

        c.free(tok);

        if (round_counter !== 0)
            ParseError("Unbalanced ()");
        else if (square_counter !== 0)
            ParseError("Unbalanced []");
        else if (curly_counter !== 0)
            ParseError("Unbalanced {}");

        return tokens;
    }


    /**
    Predicate Functions
    */

    /**
    Check if token is a storage class specifier.
    */
    function isStorageClassSpecifier()
    {
        if (tok === "register" || tok === "auto" || tok === "static")
            ParseError("Invalid Storage Class Specifier: " + tok);

        // TODO: let extern pass through?
        return (tok === "typedef");
    }

    /**
    Check if token is a type qualifier.
    */
    function isTypeQualifier()
    {
        return (tok === "const" || tok === "volatile" || tok === "restrict");
    }

    /**
    Check if token is a function specifier.
    */
    function isFunSpecifier()
    {
        if (tok === "inline")
            ParseError("Invalid Function Specifier: inline");
        return false;
    }

    /**
    Check if token is an identifier.
    */
    function isIdentifier()
    {
        return !(tok === STAR || tok === OPEN_ROUND || tok === CLOSE_ROUND ||
                    tok === OPEN_SQUARE || tok === CLOSE_SQUARE ||
                    tok === OPEN_CURLY || tok === CLOSE_CURLY ||
                    tok === COMMA || tok === SEMI_COLON ||
                    isStorageClassSpecifier() || isTypeSpecifier() ||
                    tok === "struct" || tok === "union" ||
                    isTypeQualifier() || isFunSpecifier());
    }

    /**
    Check if token is a type specifier.
    */
    function isTypeSpecifier()
    {
        return (types.hasOwnProperty(tok));
    }


    /**
    Parsing Functions
    */

    /**
    Parse short type
    */
    function parseShortType()
    {
        var peek = tokens[index + 1];
        if (peek === "int")
            return advance("short");
        else
            return tok;
    }

    /**
    Parse long type
    */
    function parseLongType()
    {
        var peek = tokens[index + 1];

        if (peek === "int")
            return advance("long");
        else if (peek === "long")
            return parseLongType(advance());

        if (peek === "unsigned")
        {
            parseUnsignedType(advance());
            return advance("long");
        }
        else if (peek === "signed")
        {
            parseSignedType(advance());
            return advance("long");
        }

        return tok;
    }


    /**
    NOTE: For now the signedness is discarded
          and it's up to the programmer to track whether
          a value is signed or unsigned. Eventually it
          may be kept for use by wrappers.
    */

    /**
    Parse signed type
    */
    function parseSignedType()
    {
        var peek = tokens[index + 1];

        if (peek === "char")
            return "char";
        else if (peek === "int")
            return "int";
        else if (peek === "short")
            return parseShortType();
        else if (peek === "long")
            return parseLongType();
        else
            return tok;
    }

    /**
    Parse unsigned type
    */
    function parseUnsignedType()
    {
        var peek = tokens[index + 1];

        if (peek === "char" || peek === "int")
            return peek;
        else if (peek === "short")
            return parseShortType();
        else if (peek === "long")
            return parseLongType();
        else
            return tok;
    }

    /**
    Parse a declaration.
    */
    function parseDeclaration()
    {
        var dec = {};
        acceptDeclarationSpecifier(dec);
        acceptDeclarator(dec);

        if (tok !== SEMI_COLON)
            ParseError("Expected ;");

        return dec;
    }

    /**
    Accept a declaration specifier.
    */
    function acceptDeclarationSpecifier(dec)
    {
        while (true)
        {
            // NOTE: any number/combination of these is accepted,
            // it doesn't fully validate input.
            if (isTypeSpecifier())
            {
                if (tok === "signed")
                    dec.type = advance(parseSignedType());
                else if (tok === "unsigned")
                    dec.type = advance(parseUnsignedType());
                else if (tok === "short")
                    dec.type = advance(parseShortType());
                else if (tok === "long")
                    dec.type = advance(parseLongType());
                else
                    dec.type = advance(types[tok]);
            }
            else if (tok === "struct" || tok === "union")
            {
                // leave tok in place for parseStructOrUnionSpecifier
                dec.type = parseStructOrUnionSpecifier();
                dec.str_or_uni = true;
            }
            else if (isTypeQualifier() || isStorageClassSpecifier() || isFunSpecifier())
            {
                if (tok === "typedef")
                    dec.typedef = true;
                advance();
            }
            else
            {
                break;
            }
        }
    }

    /**
    Accept a declarator.
    */
    function acceptDeclarator(dec, allow_abstract)
    {
        acceptPointer(dec);
        acceptDirectDeclarator(dec, allow_abstract);
    }

    /**
    Accept a pointer.
    */
    function acceptPointer(dec)
    {
        if (tok === STAR)
        {
            dec.ptr = true;
            while (tok === STAR || isTypeQualifier())
                advance();
        }
    }

    /**
    Accept a direct declarator.
    */
    function acceptDirectDeclarator(dec, allow_abstract)
    {
        var count;
        var nested_dec;
        var num;

        if (isIdentifier())
        {
            if (dec.name)
                ParseError("Unexpected Identifier: " + tok);
            dec.name = tok;
            advance();
        }
        else if (tok === OPEN_ROUND)
        {
            advance();
            nested_dec = {};
            nested_dec.type = dec;
            acceptDeclarator(nested_dec, true);
            dec.dec = nested_dec;

            if (tok === CLOSE_ROUND)
                advance();
            else
                ParseError("Expected )");
        }
        else if (!allow_abstract && !dec.str_or_uni)
        {
            ParseError("Expected identifier or (");
        }

        // Arrays
        if (tok === OPEN_SQUARE)
        {
            dec.array = true;
            advance();

            if (tok === CLOSE_SQUARE)
                return advance();

            num = Number(tok);
            if (isNaN(num))
                ParseError("Expected number");

            dec.size = num;
            advance();

            if (tok === CLOSE_SQUARE)
                return advance();
            else
                ParseError("Expected ]");
        }

        // Functions
        if (tok === OPEN_ROUND)
        {
            // Distinguish between a function declaration and a
            // declaration returning a (pointer to ) function. In the later case we don't care
            // about the signature of the returned function.
            if (dec.fun)
            {
                if (!dec.ptr)
                    ParseError("Cannot return function");

                // Just skip the args
                count = 1;

                while (count > 0)
                {
                    advance();
                    if (tok === undefined)
                        ParseError("Unable to parse declaration");
                    else if (tok === OPEN_ROUND)
                        count += 1;
                    else if(tok === CLOSE_ROUND)
                        count -= 1;
                }

                return advance();
            }

            // Otherwise, it's a function declaration; get the arg types
            dec.fun = true;
            advance();

            // Handle empty arg list
            if (tok === CLOSE_ROUND)
                return advance();

            dec.args = parseParameterTypeList();

            if (tok === CLOSE_ROUND)
                advance();
            else
                ParseError("Expected )");
        }

        return null;
    }

    /**
    Parse a parameter type list.
    */
    function parseParameterTypeList()
    {
        var parameter_decs = [];
        var dec;

        while(true)
        {
            dec = {};
            acceptDeclarationSpecifier(dec);
            // All declarators inside parameter lists can be abstract.
            acceptDeclarator(dec, true);
            parameter_decs.push(dec);

            if (tok === COMMA)
                advance();
            else if (tok == CLOSE_ROUND)
                return parameter_decs;
            else
                ParseError("Expected ,  or )");
        }
    }

    /**
    Parse a struct or union.
    */
    function parseStructOrUnionSpecifier()
    {
        var dec = {};
        var members;
        var member_dec;
        var tagged = false;

        dec.type = tok;
        advance();

        if (isIdentifier())
        {
            tagged = true;
            dec.name = tok;
            advance();
        }

        if (tok === OPEN_CURLY)
        {
            advance();
            members = [];
            dec.members = members;
            member_dec = {};

            while(true)
            {
                member_dec = {};

                acceptDeclarationSpecifier(member_dec);
                acceptDeclarator(member_dec);

                members.push(member_dec);

                if ((tok === SEMI_COLON) && (tokens[index + 1] === CLOSE_CURLY))
                {
                    return advance(), advance(dec);
                }
                else if (tok === SEMI_COLON)
                    advance();
                else
                    ParseError("Expected ;  or }");
            }
        }
        else if (tagged)
        {
            // TODO: more checks?
            return dec;
        }
        else
        {
            ParseError("Expected { or identifier");
        }
        return null;
    }

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
            return arg_strings[len];

        var arg_string = "a";
        for (var i = 1; i < len; i++)
            arg_string += ", " + arg_names[i];
        arg_string += " ";
        arg_strings[len] = arg_string;
        return arg_string;
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
    };

    /**
    Generate a wrapper function to call a function in the lib.
    */
    FFILibrary.prototype.fun = function(fname, sig)
    {
        // Some ir functions expect string constants, so they must be
        // constructed as strings and eval'd
        var args = getArgString(sig.split(",").length - 1);
        var fun = ["function(", args, ")",
                   "{",
                   "    var sym = this.symbols[", ('"' + fname + '"'), "];",
                   "    return $ir_call_ffi(sym, ", ('"' + sig + '"'),
                    (args === "" ? args : (", " + args)),
                    ");",
                   "}"
                  ].join(" ");
        this.getSym(fname);
        this[fname] = eval(fun);
    };

    /**
    Generate a wrapper function to lookup a value in the lib.
    */
    FFILibrary.prototype.symbol = function(symname, sig)
    {
        // TODO: handle more types
        if (sig !== "*")
            throw "Unhandled type in symbol()";

        var fun = ["function()",
                   "{",
                   "    var sym = this.symbols[", ('"' + symname + '"'), "];",
                   "    return $ir_load_rawptr(sym, 0);",
                   "}"
                  ].join(" ");
        this.getSym(symname);
        this[symname] = eval(fun);
    };

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
    };


    /**
    Array wrapper
    */
    function FFIArray(type, size)
    {
        size = size || 0;
        // TODO: construct loader function dynamically using load_op_map?

        var ar_proto = {};

        function Ar(handle, offset)
        {
            var a = Object.create(ar_proto);
            a.type = type;
            a.type_size = size_map[type];
            a.loader = load_map[type];
            if (!a.type_size || !a.loader)
                throw "Unhandled type in array constructor: " + type + ".";

            if ($ir_get_type(handle) === 4)
            {
                a.handle = handle;
                a.offset = offset || 0;
            }
            else
            {
                a.handle = c.malloc(size * a.type_size);
                a.offset = 0;
            }

            return a;
        }

        ar_proto.get = function(index)
        {
            return this.loader(this.handle, this.offset + this.type_size * index);
        };

        return Ar;
    }

    /**
     FFIStruct
     Wrapper around structs.
     */
    function FFIStruct(def)
    {
        var struct_def = def.type;
        var members = struct_def.members;
        var i = 0;
        var l = members.length;
        var offset = 0;
        var member;
        var name;
        var fun;
        var type;
        var size;
        var d;
        var struct_proto = {};

        function struct(handle, offset)
        {
            var s = Object.create(struct_proto);
            // check if a ptr was passed in
            if ($ir_get_type(handle) === 4)
            {
                s.handle = handle;
                s.offset = offset || 0;
            }
            else
            {
                s.handle = c.malloc(size);
                s.offset = 0;
            }

            return s;
        }

        // member wrappers
        for (; i < l; i++)
        {
            member = members[i];
            name = member.name;
            // TODO: do we want the top dec?
            type = getTopDec(member).type;
            // TODO: arrays, structs, etc .... sizeOf() function?
            size = size_map[type];
            // TODO: redesign getters?

            // alignment
            if (offset !== 0)
            {
                d = offset % size;
                if (d !== 0)
                    offset += size - d;
            }

            // return appropriate wrapper for member
            if (member.array)
            {
                struct_proto["wrap_load_" + name] = array_wrappers[type];
                size *= member.size;
                fun = [
                    "function ()",
                    "{",
                    "    var wrapper = new this['wrap_load_", name, "'](this.handle, ", offset, ");",
                    "    this['get_", name, "'] = function() { return wrapper; };",
                    "    return wrapper;",
                    "}"
                ].join("");
                struct_proto["get_" + name] = eval(fun);
            }
            else
            {
                fun = [
                    "function ()",
                    "{",
                    "    return ", load_op_map[type], "(this.handle, ", offset, ");",
                    "};"
                ].join("");
                struct_proto["get_" + name] = eval(fun);
            }

            // Offset for the next member
            offset += size;
        }

        return struct;
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

    // It's common to want to pass a null ptr as an arg,
    // so one is provided by the ffi
    var NullPtr = $nullptr;

    /**
    Create a C string from a JS string.
    */
    function cstr(str, len)
    {
        var cstr, i;
        len = len || str.length;
        cstr = c.malloc(len + 1);

        for (i = 0; i < len; i++)
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
        var i;

        for (i = 0; i < len; i++)
            $ir_store_u8(buff, i, $rt_str_get_data(jstr, i));

        $ir_store_u8(buff, len, 0);
        return buff;
    }

    /**
    Create a JS string from a C string.
    If n is non-zero copy only n chars from the C string.
    */
    function string(cstr, n, offset)
    {
        // TODO: add offset
        var s, i;
        var len = 0;

        offset = offset || 0;

        // Get the length
        if (n)
        {
            len = n;
        }
        else
        {
            while ($ir_load_u8(cstr, offset + len++) !== 0);
            len -= 1;
        }

        // Allocate string
        s = $rt_str_alloc(len);

        // Copy
        for (i = 0; i < len; i++)
            $rt_str_set_data(s, i, $ir_load_u8(cstr, offset + i));

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
        return x === $nullptr;
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
        testParse : testParse,
        getTopDec : getTopDec,
        c : c,
        array : FFIArray,
        size_map : size_map,
        load : function(name) { return new FFILibrary(name); }
    };

})();


