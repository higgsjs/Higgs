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
FFI - provides functionality for writing bindings to/wrappers for C code.
*/


(function()
{

    var console = require('lib/console');

    /**
    ERRORS
    */

    /**
    FFIError
    @constructor
    */
    function FFIError(message)
    {
        this.message = message;
    }
    FFIError.prototype = new Error();
    FFIError.prototype.constructor = FFIError;

    /**
    CParseError
    @constructor
    */
    function CParseError(message, at)
    {
        this.name = "CParseError";
        this.message = message || "error parsing c declaration";
        if (at)
            this.message += at;
    }

    CParseError.prototype = new Error();
    CParseError.prototype.constructor = CParseError;

    /**
    CParseExpectedError
    @constructor
    */
    function CParseExpectedError(expected, got, at)
    {
        var message;
        this.name = "CParseExpectedError";

        if (expected)
        {
            expected = (typeof expected === "number") ?
                "'" + String.fromCharCode(expected) + "'" : expected;
            message = "Expected: " + expected;

            if (got === 0)
            {
                message += " Got EOF";
            }
            else if (got)
            {
                got = (typeof got === "number") ?
                    String.fromCharCode(got) : got;
                message += " Got: '" + got + "'";
            }

            if (at)
                message += at;

            this.message = message;
        }
    }

    CParseExpectedError.prototype = new CParseError();
    CParseExpectedError.prototype.constructor = CParseExpectedError;

    /**
    CParseUnexpectedError
    @constructor
    */
    function CParseUnexpectedError(unexpected, got, at)
    {
        var message;
        this.name = "CParseUnexpectedError";
        if (unexpected)
        {
            message = "Unexpected: " + got;

            if (got)
            {
                got = (typeof got === "number") ?
                    "'" + String.fromCharCode(got) + "'" : got;
                message += " - '" + got + "'";
            }

            if (at)
                message += at;

            this.message = message;
        }
    }

    CParseUnexpectedError.prototype = new CParseError();
    CParseUnexpectedError.prototype.constructor = CParseUnexpectedError;


    /**
    TOKEN TYPES
    */

    var EOF = 0;
    var IDENTIFIER = 1;
    var STORAGE_CLASS_SPECIFIER = 2;
    var TYPE_SPECIFIER = 3;
    var STRUCT_OR_UNION = 4;
    var TYPE_QUALIFIER = 5;
    var NUMBER_LITERAL = 6;
    var ENUM = 7;

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

    // =
    var EQUAL_SIGN = 61;


    /**
    LEXER
    */

    /**
    Lexer Object
    */
    var Lexer = {
        ctypes : null,
        input : null,
        token : null,
        token_type : null,
        index : 0,
        cursor : 0,
        line : 1,
        line_index : 0,
        last_index : 0,
        peeked : false
    };

    /**
    Return the current location as a string for error messages
    */
    Lexer.loc = function()
    {
        return " (CDeclaration@" + this.line + ":" + (this.line_index + 1)  + ")";
    };

    /**
    Get the next token/token type. If peek is true, the same values will be emitted next call
    */
    Lexer.next = function(peek)
    {
        var chr;
        var t;
        var t_length;
        var t_string;
        var i;

        var CTypes = this.ctypes;
        var input = this.input;
        var end = input.length;
        var cursor = this.cursor;
        var index = this.index;
        var last_index = this.last_index;

        if (this.peeked)
        {
            this.peeked = peek;
            return;
        }
        else if (peek)
        {
            this.peeked = true;
        }

        // scan next token
        while (cursor < end)
        {
            chr = $rt_str_get_data(input, cursor);

            // Handle Loners
            switch(chr)
            {
                // ( )
            case 40: case 41:
                // ; = * ,
            case 59: case 61: case 42: case 44:
                //  [ {
            case 91: case 123:
                // ] }
            case 93: case 125:
                this.token = chr;
                this.token_type = chr;
                this.cursor = cursor + 1;
                this.index = cursor + 1;
                this.line_index = cursor - last_index;
                return;
            // whitespace
            // LF
            case 10:
                this.line += 1;
                this.line_index = 0;
                this.last_index = cursor;
                cursor += 1;
                index = cursor;
                break;
            // (H) TAB, SPACE
            case 9: case 32:
                this.line_index += 1;
            // other whitespace
            case 11: case 12: case 13: case 160:
                cursor += 1;
                index = cursor;
                break;
            default:

                // number literals
                if ((cursor === index) && (chr > 47 && chr < 58))
                {
                     while (chr > 47 && chr < 58)
                        chr = $rt_str_get_data(input, ++cursor);

                    if (((chr >= 65 && chr <= 90) || (chr >= 97 && chr <= 122) ||
                         (chr >= 48 && chr <= 57) || (chr === 95)))
                        throw new CParseError("Identifiers cannot start with a number.");

                    this.token_type = NUMBER_LITERAL;
                }
                else
                {
                    // idents
                    while (((chr >= 65 && chr <= 90) || (chr >= 97 && chr <= 122) ||
                            (chr >= 48 && chr <= 57) || (chr === 95)) && cursor < end)
                        chr = $rt_str_get_data(input, ++cursor);
                    this.token_type = IDENTIFIER;
                }

                // copy substr
                t_length = cursor - index;
                t_string = $rt_str_alloc(t_length);
                for (i = 0; i < t_length; i++)
                    $rt_str_set_data(t_string, i, $rt_str_get_data(input, index++));

                // emit
                t = $ir_get_str(t_string);
                this.token = t;

                if (t === "typedef")
                    this.token_type = STORAGE_CLASS_SPECIFIER;
                else if (t === "struct" || t === "union")
                    this.token_type = STRUCT_OR_UNION;
                else if (t === "enum")
                    this.token_type = ENUM;
                else if (t === "const")
                    this.token_type = TYPE_QUALIFIER;
                else if (CTypes[t])
                    this.token_type = TYPE_SPECIFIER;

                // advance
                this.cursor = cursor;
                this.index = index;
                this.line_index = index - last_index;
                return;
            }
        }

        this.token = EOF;
        this.token_type = EOF;
        return;
    };

    /*
    Initialize lexer instance
    */
    Lexer.init = function(input, ctypes)
    {
        this.input = input;
        this.cursor = 0;
        this.index = 0;
        this.token = null;
        this.token_type = null;
        this.ctypes = ctypes;
        this.peeked = false;
    };


    /**
    PARSER
    */

    var Parser = {
        dec : null,
        dec_stack : null,
        dec_stacks : null,
        dec_list : null,
        CType : null
    };

    /**
    declaration
    */
    Parser.acceptDeclaration = function ()
    {
        var lex = this.lex;
        var next_dec;

        this.acceptDeclarationSpecifiers();

        // init-declarator-list
        while (true)
        {
            // init-declarator
            this.acceptDeclarator(0);

            if (lex.token_type === EQUAL_SIGN)
            {
                lex.next();
                // initializer
                // NOTE: this only accepts integer constants currently
                if (lex.token_type === NUMBER_LITERAL)
                {
                    this.dec.value = lex.token;
                    lex.next();
                }
                else
                {
                    throw new CParseExpectedError("Number Literal", lex.token, lex.loc());
                }
            }

            if (lex.token_type === COMMA)
            {
                lex.next();
                next_dec = CDec(this.dec);
                this.dec_list.push(this.dec);
                this.dec = next_dec;
            }
            else
            {
                break;
            }
        }

        if (lex.token_type !== SEMI_COLON)
            throw new CParseExpectedError(SEMI_COLON, lex.token, lex.loc());

    };

    /**
    declaration-specifiers
    */
    Parser.acceptDeclarationSpecifiers = function()
    {
        var lex = this.lex;
        var dec = this.dec;
        var CType = this.CType;
        var tok;
        var type;

        while (true)
        {
            lex.next();
            type = lex.token_type;
            tok = lex.token;

            if (type === STORAGE_CLASS_SPECIFIER)
                dec.storage_class = tok;
            else if (type === STRUCT_OR_UNION)
                this.acceptStructOrUnionSpecifier();
            else if (type === ENUM)
                this.acceptEnumSpecifier();
            else if (type === TYPE_SPECIFIER)
                if (dec.type)
                    if (tok === "char" || tok === "int" || tok === "long")
                    {
                        dec.type = CType(dec.type.name + " " + tok);
                    }
                    else
                    {
                        if (dec.storage_class === "typedef")
                            dec.name = tok;
                        else
                            throw new CParseUnexpectedError("type specifier", tok, lex.loc());
                    }
                else
                    dec.type = CType(tok);
            else if (type === TYPE_QUALIFIER)
            {} // NOTE: eat this
            else
                break;
        }
    };

    /**
    Accept a struct-or-union-specifier:
    */
    Parser.acceptStructOrUnionSpecifier = function()
    {
        var lex = this.lex;
        var tok = lex.token;
        var type = lex.token_type;
        var members;
        var names;
        var name;
        var t;
        var w;

        if (tok !== "struct" && tok !== "union")
            throw new CParseExpectedError("'struct' or 'union'", tok, lex.loc());

        lex.next();

        // struct name
        if (lex.token_type === IDENTIFIER)
        {
            name = lex.token;
            lex.next(true);
        }

        // members
        if (lex.token_type === OPEN_CURLY)
        {
            if (name)
                lex.next();
            lex.next();

            // Consume member declarators and names
            members = [];
            names = [];

            this.acceptStructDeclarationList(members, names);

            // Wrap the declaration appropriately
            if (tok === "struct")
                this.dec.type = CStruct(members);
            else
                this.dec.type = CUnion(members);

            // If the struct is tagged and this is the first time seeing it, add
            // the wrapper to the library
            if (name)
            {
                t = this.lib[name];
                if (!t)
                {
                    t = this.dec.type;
                    w = t.wrapper_fun(c, names);
                    t = Object.create(t);
                    t.wrapper_fun = w;
                    this.ctypes[tok + " " + name] = t;
                    this.lib[name] = w;

                }
            }


            if (lex.token_type !== CLOSE_CURLY)
                throw new CParseExpectedError(CLOSE_CURLY, lex.token, lex.loc());
        }
        else if (name)
        {
            // In this case we just have "struct TagName"
            // check if this can be wrapped
            t = this.ctypes[tok + " " + name];

            // otherwise, create a new wrapper
            if (!t)
            {
                if (tok === "struct")
                    t = CStruct(null);
                else
                    t = CUnion(null);
            }

            this.dec.type = t;
        }
        else
        {
            throw new CParseExpectedError("identifier or {", lex.token, lex.loc());
        }

        // NOTE: advance handled by caller
    };

    /**
    Accept a struct-declaration-list
    */
    Parser.acceptStructDeclarationList = function(members, names)
    {
        var dec = this.dec;
        var lex = this.lex;
        var CType = this.CType;
        var type;
        var tok;
        var of;

        // struct-declaration-list
        while (true)
        {
            this.dec = of = {};

            // struct-declaration
            // specifier-qualifier-list
            while (true)
            {
                if (lex.token_type === TYPE_SPECIFIER)
                {
                    if (of.type)
                        of.type = CType(of.type.name + " " + lex.token);
                    else
                        of.type = CType(lex.token);
                    lex.next();
                    continue;
                }
                else if (lex.token_type === TYPE_QUALIFIER)
                {} // NOTE: just eat this
                break;
            }

            // struct-declarator-list
            while (true)
            {
                // struct-declarator
                this.acceptDeclarator();

                // TODO: = constant expression

                members.push(of.type);
                names.push(of.name);

                if (lex.token_type !== COMMA)
                    break;

                lex.next();
                of = this.dec = CDec(of);
            }


            if (lex.token_type === SEMI_COLON)
            {
                lex.next(true);
                if (lex.token === CLOSE_CURLY)
                {
                    lex.next();
                    break;
                }
                else
                {
                    lex.next();
                    continue;
                }
            }

            break;
        }

        this.dec = dec;
    };

    /**
    Accept a enum-specifier
    **/
    Parser.acceptEnumSpecifier = function()
    {
        var lex = this.lex;
        var tok = lex.token;
        var type = lex.token_type;
        var members;
        var member;
        var name;
        var map;
        var l;
        var i = 0;
        var count = 0;

        if (tok !== "enum")
            throw new CParseExpectedError("'struct' or 'union'", tok, lex.loc());

        lex.next();

        if (lex.token_type === IDENTIFIER)
        {
            name = lex.token;
            lex.next();
        }

        this.dec.type = CEnum();

        if (lex.token_type !== OPEN_CURLY)
            return;
        else
            lex.next();

        members = [];

        // enumerator-list
        while (true)
        {
            if (lex.token_type === COMMA)
            {
                lex.next();
                continue;
            }
            else if (lex.token_type === IDENTIFIER)
            {
                member = CDec();
                member.name = lex.token;
                member.value = count++;
                members.push(member);
                lex.next();
                if (lex.token_type === EQUAL_SIGN)
                {
                    lex.next();
                    if (lex.token_type === NUMBER_LITERAL)
                    {
                        member.value = count = parseInt(lex.token);
                        lex.next();
                        continue;
                    }
                }
                continue;
            }
            else if (lex.token_type === CLOSE_CURLY)
            {
                break;
            }
            else
            {
                throw new CParseExpectedError("identifier, ',', or '}'", lex.token, lex.loc());
            }
        }

        if (name && !this.lib[name])
        {
            // If the enum is tagged, add a mapping to the library
            map = Object.create(null);
            this.lib[name] = map;
            l = members.length;

            while (i < l)
            {
                member = members[i++];
                map[member.name] = member.value;
            }
        }
    };

    /**
    Accept a declarator
    */
    Parser.acceptDeclarator = function(nested)
    {
        var lex = this.lex;
        var dec = this.dec;
        var type = lex.token_type;
        var p;

        /**
        Accept a pointer
        */
        if (type === STAR)
        {
            while (true)
            {
                type = lex.token_type;
                // Don't wrap yet if in nested declarator
                if (type === STAR)
                    if (nested)
                        this.dec_stack.push(STAR);
                else
                    dec.type = CPtr(dec.type);
                else if (type === TYPE_QUALIFIER)
                {} // NOTE: eat this
                else
                    break;

                lex.next();
            }
        }

        this.acceptDirectDeclarator(nested);
    };

    /**
    Accept a direct-declarator
    */
    Parser.acceptDirectDeclarator = function(nested)
    {
        var lex = this.lex;
        var dec = this.dec;
        var type;
        var tok;
        var num;
        var args;
        var depth;

        while (true)
        {
            type = lex.token_type;

            // direct-declarator
            if (type === IDENTIFIER)
            {
                // identifier
                dec.name = lex.token;
                lex.next();
                type = lex.token_type;
            }
            else if (type === OPEN_ROUND)
            {
                // Enter a nested declarator
                lex.next();

                // Create a stack for the nested declarators
                if (this.dec_stacks === null)
                    this.dec_stacks = [];

                // Create a stack for the current declarator level
                depth = this.dec_stacks.length;
                this.dec_stack = [];
                this.dec_stacks.push(this.dec_stack);

                // Consume the current declarator and advance
                this.acceptDeclarator(++nested);
                nested -= 1;
                lex.next();
            }

            // It's an array
            if (lex.token_type === OPEN_SQUARE)
            {
                lex.next();
                type = lex.token_type;

                // Check if we have a size for the array
                if (type === CLOSE_SQUARE)
                {
                    num = 0;
                }
                else if (type === NUMBER_LITERAL)
                {
                    /*
                    NOTE:
                    According to the c grammar we should accept a constant-expression here.
                    Right now it just accepts integer constants.
                    */
                    num = parseInt(lex.token);
                    if (isNaN(num))
                        throw new CParseExpectedError("integer constant", lex.token, lex.loc());
                    lex.next();
                }
                else
                {
                    throw new CParseExpectedError("] or integer constant", lex.token, lex.loc());
                }

                // Don't wrap yet if we're in a nested declarator
                if (nested > 0)
                    this.dec_stack.push(num, OPEN_SQUARE);
                else if (dec.type.wrapper === "CFun")
                    dec.type = CFun( CArray(dec.type.ret, num), dec.type.args);
                else
                    dec.type = CArray(dec.type, num);

                // Apply type info from nested declarators
                if (nested === 0 && this.dec_stack && this.dec_stack.length > 0)
                    this.handleDecStack(depth);

                if (lex.token_type !== CLOSE_SQUARE)
                    throw  new CParseExpectedError(CLOSE_SQUARE, lex.token);

                lex.next();
                continue;
            }

            // It's a function
            if (lex.token_type === OPEN_ROUND)
            {
                args = [];
                // NOTE: no identifier-list.
                this.acceptParameterTypeList(args);

                // Don't wrap yet if we're in a nested declarator
                if (nested > 0)
                    this.dec_stack.push(args, OPEN_ROUND);
                else
                    dec.type = CFun(dec.type, args);

                // Apply type info from nested declarators
                if (nested === 0 && this.dec_stack && this.dec_stack.length > 0)
                    this.handleDecStack(depth);

                // Advance
                type = lex.token_type;
                if (type !== CLOSE_ROUND)
                    throw new CParseExpectedError(CLOSE_ROUND, lex.token, lex.loc());

                lex.next();
                continue;
            }

            break;
       }
    };

    /**
    Accept a parameter-type-list
    */
    Parser.acceptParameterTypeList = function (sig)
    {
        var dec = this.dec;
        var lex = this.lex;
        var of;
        var t;

        while (true)
        {
            // peek
            lex.next(true);

            // Check for end of arg list/void function
            if (lex.token_type === CLOSE_ROUND)
            {
                lex.next();
                break;
            }

            // Create new dec for arg
            of = this.dec = CDec();
            this.acceptDeclarationSpecifiers();

            if (lex.token_type !== COMMA)
                this.acceptDeclarator(0);

            // cover functions explicitly declared as (void)
            t = of.type;
            if (t && t.name === "void")
                break;

            sig.push(t);

            if (lex.token_type === COMMA)
                continue;
            else
                break;
        }

        this.dec = dec;
    };

    /**
    Apply types that have been stacked from nested declarators
    */
    Parser.handleDecStack = function(depth)
    {
        var dec_stack;
        var dec_stacks = this.dec_stacks.splice(depth);
        var i;
        var len;
        var t;

        for (i = 0, len = dec_stacks.length; i < len; i++)
        {
            dec_stack = dec_stacks[i];
            while (dec_stack.length)
            {
                t = dec_stack.pop();
                if (t === STAR)
                    this.dec.type = CPtr(this.dec.type);
                else if (t === OPEN_ROUND)
                    this.dec.type = CFun(this.dec.type, dec_stack.pop());
                else if (t === OPEN_SQUARE)
                    this.dec.type = CArray(this.dec.type, dec_stack.pop());
                else
                    throw new CParseError();
            }
        }
    };


    /*
    WRAPPER HELPERS
    */

    // Arg strings are used in the generation of function wrappers for the FFI
    var arg_strings = ["", " a "];
    var arg_names = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP";

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
    Generate a name for a struct or union type
    */
    function StructUnionNameStr(is_struct, members)
    {
        var i = 0;
        var l = members.length - 1;
        var str;

        if (is_struct)
            str = "s{";
        else
            str = "u{";

        while (i <= l)
        {
            str += members[i].name;
            if (i < l)
                str += ",";
            i += 1;
        }

        return str + "}";
    }

    /**
    Generate a name for a function type
    */
    function FunNameStr(ret, args)
    {
        var i = 0;
        var l = args.length - 1;
        var str = "(" + ret.name + ",";

        if (args.length === 0)
            return str + "void)";
        else
            while (i <= l)
            {
                str += args[i].name;
                if (i < l)
                    str += ",";
                i += 1;
            }

        return str + ")";
    }


    /**
    WRAPPING CODEGEN
    */

    /**
    Generate a wrapping function for a CFun
    */
    function CFunGen(ret, args)
    {
        var base = ret.base_type;
        var sig_str = base;
        var i = 0;
        var l = args.length;
        var arg_str = getArgString(l);
        var fun_str;

        // Check if this is a return type that can be wrapped
        if (!base)
            throw new TypeError("Invalid return type for CFun: " + ret.name);

        // Generate a sig string for $ir_call_ffi
        while (i < l)
        {
            base = args[i++].base_type;
            if (!base)
                throw new TypeError("Invalid arg type for CFun:" + args[--i].name);
            sig_str += "," + base;
        }

        // Generate wrapper function
        fun_str = "\
            function(fun_sym)\n\
            {\n\
                return function(" + arg_str  + ")\n\
                {\n\
                    return $ir_call_ffi(fun_sym, " + ('"' + sig_str + '"') + (arg_str === "" ? arg_str : (", " + arg_str)) + ");\n\
                };\n\
            };\n\
        ";

        return eval(fun_str);
    }

    /**
    Generate a wrapping function for a CArray
    */
    function CArrayGen(type, length)
    {
        var size = type.size;
        var load_fun = type.load_fun;
        var store_fun = type.store_fun;
        var wrapper_fun = "\
        (function(c, string)\n\
        {\
        ";

        if (type.name === "char")
        {
            // Special case toString for char[]
            wrapper_fun = "\
            (function(c, string)\n\
            {\n\
            var arrProto = {};\n\
            arrProto.toString = function()\n\
            {\n\
                return string(this.handle, 0, this.offset);\n\
            };\n\
            arrProto.toJS = arrProto.toString;\n\
            ";
        }
        else
        {
            // toString for other types
            wrapper_fun = "\
            (function(c)\n\
            {\
            var arrProto = {};\n\
            \n\
            arrProto.toString = function()\n\
            {\n\
                var arr_string = '[ ' + this.get(0).toString();\n\
                var i = 1;\n\
                var l = this.length;\n\
                while (i < l)\n\
                {\n\
                    arr_string += ', ' + this.get(i).toString();\n\
                    i += 1;\
                }\n\
                arr_string += ' ]';\n\
                return arr_string;\n\
            };\
            \n\
            arrProto.toJS = function()\n\
            {\n\
                var a = []\n\
                var i = 0;\n\
                var l = this.length;\n\
                while (i < l)\n\
                {\n\
                    a.push(this.get(i));\n\
                    i += 1;\
                }\n\
                return a;\n\
            };\
            ";
        }

        // get/set functions and constructor
        wrapper_fun += "\
            arrProto.get = function(index)\
            {\n\
                return " + load_fun + "(this.handle, this.offset + (" + size + " * index));\n\
            };\n\
            arrProto.set = function(index, val)\n\
            {\n\
                return " + store_fun + "(this.handle, this.offset + (" + size + " * index), val);\n\
            };\
            return (function(handle, offset)\n\
            {\n\
                var arr = Object.create(arrProto);\n\
                \
                if ($ir_is_rawptr(handle))\n\
                {\n\
                    arr.handle = handle;\n\
                    arr.offset = offset || 0;\n\
                    arr.length = " + length + ";\n\
                }\n\
                else\n\
                {\n\
                    arr.handle = c.malloc(" + (length * size) + " )\n\
                    arr.offset = 0;\n\
                }\n\
                return arr;\n\
            });\n\
        })\
        ";

        // The wrapper needs acces to the c object for c.malloc and string for toString
        return eval(wrapper_fun)(c, string);
    }

    /**
    Generate a wrapping function for a CUnion
    */
    function CUnionGen(members, size)
    {
        var i = 0;
        var l = members.length;
        var mem;
        var type_size;
        var d;
        var loader;
        var loaders;
        var loader_dec = "";
        var loader_n = 0;
        var arg_str;

        var wrapper_fun = "\
            (function(c, names)\
            {\n\
                var strProto = {};\
        ";

        while (i < l)
        {
            mem = members[i];
            type_size = mem.align_size || mem.size;

            // members with a simple type like int are handled differently than members
            // of type like char[], the former uses simple getters/setters
            // the latter use a wrapper
            loader = mem.load_fun;

            if (!loader)
            {
                // This member uses a wrapper
                loaders = loaders || [];
                loader_n += 1;
                arg_str = (arg_str) ? (arg_str + ", ld" + loader_n) : ("ld1");
                loaders.push(mem.wrapper_fun);
                loader_dec = "\n\
                s[names[" + i + "]] = ld" + loader_n + "(s.handle, s.offset);\n\
                ";
            }
            else
            {
                // This member uses simple getter/setter
                wrapper_fun += "\n\
                strProto['get_' + names[" + i + "]] = function (){\n\
                    return " + loader + "(this.handle, this.offset);\n\
                };\n\
                strProto['set_' + names[" + i + "]] = function (val){\n\
                    return " + mem.store_fun + "(this.handle, this.offset, val);\n\
                };\
                ";
            }

            // setup for next member
            i += 1;
        }

        // constructor function
        wrapper_fun += "\n\
                return (function(handle, offset)\
                {\
                    var s = Object.create(strProto);\n\
                    if ($ir_is_rawptr(handle))\n\
                    {\n\
                       s.handle = handle;\n\
                       s.offset = offset || 0;\n\
                    }\
                    else\
                    {\
                      s.handle = c.malloc(" + size + ");\
                      s.offset = offset || 0;\n\
                   }\n" +
                   loader_dec +
                   "\
                    return s;\
                });\
            })\
        ";

        if (loader_n > 0)
        {
            // If any of the members use wrappers, add access to the wrapping functions
            wrapper_fun = "(function(" + arg_str + "){\n    return " + wrapper_fun + "\n})";
            return eval(wrapper_fun).apply(this, loaders);
        }
        else
        {
            // ...otherwise just return the wrapping function
            return eval(wrapper_fun);
        }
    }

    /**
    Generate a wrapping function for a CStruct
    */
    function CStructGen(members, size)
    {
        var i = 0;
        var l = members.length;
        var mem;
        var mem_offset = 0;
        var type_size;
        var d;
        var loader;
        var loaders;
        var loader_dec = "";
        var loader_n = 0;
        var arg_str;

        var wrapper_fun = "\
            (function(c, names)\
            {\
                var strProto = {};\
        ";

        while (i < l)
        {
            mem = members[i];
            type_size = mem.align_size || mem.size;

            // member alignment
            if (mem_offset !== 0)
            {
                d = mem_offset % type_size;
                if (d !== 0)
                    mem_offset += type_size - d;
            }

            // members with a simple type like int are handled differently than members
            // of a type like char[], the former uses simple getters/setters
            // the latter use a wrapper
            loader = mem.load_fun;

            if (!loader)
            {
                // This member uses a wrapper
                loaders = loaders || [];
                loader_n += 1;
                arg_str = (arg_str) ? (arg_str + ", ld" + loader_n) : ("ld1");
                loaders.push(mem.wrapper_fun);
                loader_dec = "\n\
                s[names[" + i + "]] = ld" + loader_n + "(s.handle, s.offset + " + mem_offset + ");\n\
                ";
            }
            else
            {
                // This member uses simple getter/setter
                wrapper_fun += "\
                strProto['get_' + names[" + i + "]] = function (){\n\
                    return " + loader + "(this.handle, this.offset + " + mem_offset + ");\n\
                };\n\
                strProto['set_' + names[" + i + "]] = function (val){\n\
                    return " + mem.store_fun + "(this.handle, this.offset + " + mem_offset + ", val);\n\
                };\
                ";
            }

            // setup for next member
            mem_offset += type_size;
            i += 1;
        }

        // constructor function
        wrapper_fun += "\
                return (function(handle, offset)\
                {\
                    var s = Object.create(strProto);\n\
                    if ($ir_is_rawptr(handle))\n\
                    {\n\
                       s.handle = handle;\n\
                       s.offset = offset || 0;\n\
                    }\
                    else\
                    {\
                      s.handle = c.malloc(" + size + ");\
                      s.offset = offset || 0;\n\
                   }\n" +
                   loader_dec +
                   "\
                    return s;\
                });\
            })\
        ";

        if (loader_n > 0)
        {
            // If any of the members use wrappers, add access to the wrapping functions
            wrapper_fun = "(function(" + arg_str + "){\n    return " + wrapper_fun + "\n})";
            return eval(wrapper_fun).apply(this, loaders);
        }
        else
        {
            // ...otherwise just return the wrapping function
            return eval(wrapper_fun);
        }
    }

    /**
    TYPE WRAPPERS
    */

    /**
    Wrappers for C Declarations
    */

    function CDec(base)
    {
        var dec = {
            wrapper : "CDec"
        };

        if (base)
            dec.type = base.type;

        return dec;
    }

    /**
    Wrappers for C Types

    NOTE: CTypes is a little different: it represnts the "type namespace" for a FFILib,
          so they each have their own copy. So this function actually returns a wrapper function.
          The other type wrappers are all shared between libs.
    */

    function CTypeFun(ob)
    {
        var CTypes = ob || Object.create(null);

        return function(name, base_type, size, load_fun, store_fun, wrapper_fun)
        {
            var t = CTypes[name];

            if (!t)
            {
                if (arguments.length < 3)
                {
                    throw new CParseError("Invalid or unspecified type: " + name);
                }

                t = {
                    wrapper : "CType",
                    name : name,
                    base_type : base_type,
                    size : size,
                    load_fun : load_fun,
                    store_fun : store_fun,
                    wrapper_fun : wrapper_fun || null
                };

                CTypes[name] = t;
            }
            return t;
        };
    }

    // "Global" versions of types
    var CTypes = Object.create(null);
    var CType = CTypeFun(CTypes);

    // Types
    CType("char", "i8", 1, "$ir_load_i8", "$ir_store_i8");
    CType("signed char", "i8", 1, "$ir_load_i8", "$ir_store_i8");
    CType("unsigned char", "u8", 1, "$ir_load_u8", "$ir_store_u8");

    CType("short", "i16", 2, "$ir_load_i16", "$ir_store_i16");
    CType("short int", "i16", 2, "$ir_load_i16", "$ir_store_i16");
    CType("signed short", "i16", 2, "$ir_load_i16", "$ir_store_i16");
    CType("signed short int", "i16", 2, "$ir_load_i16", "$ir_store_i16");
    CType("unsigned short", "u16", 2, "$ir_load_u16", "$ir_store_u16");
    CType("unsigned short int", "u16", 2, "$ir_load_u16", "$ir_store_u16");

    CType("int", "i32", 4, "$ir_load_i32", "$ir_store_i32");
    CType("signed int", "i32", 4, "$ir_load_i32", "$ir_store_i32");
    CType("unsigned", "u32", 4, "$ir_load_u32", "$ir_store_u32");
    CType("unsigned int", "u32", 4, "$ir_load_u32", "$ir_store_u32");

    CType("long", "i64", 8, "$ir_load_i64", "$ir_store_i64");
    CType("long int", "i64", 8, "$ir_load_i64", "$ir_store_i64");
    CType("signed long", "i64", 8, "$ir_load_i64", "$ir_store_i64");
    CType("signed long int", "i64", 8, "$ir_load_i64", "$ir_store_i64");

    CType("unsigned long", "u64", 8, "$ir_load_u64", "$ir_store_u64");
    CType("unsigned long int", "u64", 8, "$ir_load_u64", "$ir_store_u64");

    CType("long long", "i64", 8, "$ir_load_i64", "$ir_store_i64");
    CType("long long int", "i64", 8, "$ir_load_i64", "$ir_store_i64");
    CType("signed long long", "i64", 8, "$ir_load_i64", "$ir_store_i64");
    CType("signed long long int", "i64", 8, "$ir_load_i64", "$ir_store_i64");

    CType("unsigned long long", "u64", 8, "$ir_load_u64", "$ir_store_u64");
    CType("unsigned long long int", "u64", 8, "$ir_load_u64", "$ir_store_u64");

    CType("double", "f64", 8, "$ir_load_f64", "$ir_store_f64");

    // Some Special handling for these types
    CType("void", "void", NaN);

    /**
    Wrappers for C Pointers
    */

    var CPtrs = Object.create(null);

    function CPtr(to)
    {
        var name = to.name;
        var p = CPtrs[name];

        if (!p)
        {
            p = {
                wrapper : "CPtr",
                to : to,
                base_type : "*",
                name : "*" + name,
                size : 8,
                load_fun : "$ir_load_rawptr",
                store_fun : "$ir_store_rawptr"
            };

            CPtrs[name] = p;
        }

        return p;
    }

    /**
    Wrappers for C Arrays
    */

    var CArrays = Object.create(null);

    function CArray(of, length)
    {
        var name = of.name;
        var a = CArrays[name];
        var t;
        var wrap;

        length = length || 0;

        // check for existing wrapper
        if (!a)
            a = CArrays[name] = Object.create(null);

        t = a[length];

        // otherwise create a new wrapper
        if (t === undefined)
        {
            t = {
                of : of,
                name : "[" + name + "]",
                length : length,
                wrapper : "CArray",
                size : of.size * length,
                align_size : of.size,
                wrapper_fun : CArrayGen(of, length)
            };

            a[length] = t;
        }

        return t;
    }

    /**
    Wrappers for C Structs
    */

    var CStructs = Object.create(null);

    function CStruct(members)
    {
        var l;
        var mem;
        var key_name;
        var last;
        var next;
        var s;
        var d;
        var key = 1;
        var type_size = 0;
        var struct_size = 0;

        // Sometimes the FFI user doesn't care about the layout of the struct, in that case
        // they can just specify the tag: such as "struct Foo". These cannot be fully wrapped,
        // but usually when you do this it's because you are just passing around an opaque pointer.
        if (members == null)
            return { wrapper: "CStruct", name: "s{}" };

        // Otherwise, get a full type wrapper
        l = members.length;
        mem = members[0];
        key_name = mem.name;
        last = CStructs[key_name];
        struct_size = mem.size;

        // check for existing wrapper
        if (!last)
            CStructs[key_name] = last = Object.create(null);

        while (key < l)
        {
            mem = members[key++];
            type_size = mem.size;

            // track size of struct
            struct_size += type_size;
            d = struct_size % type_size;
            if (d !== 0)
                struct_size += type_size - d;

            // wrapper lookup
            key_name = mem.name;
            next = last[key_name];
            if (!next)
                last = last[key_name] = Object.create(null);
            else
                last = next;
        }

        s = last["$"];

        // otherwise, create a new wrapper
        if (!s)
        {
            s = {
                wrapper : "CStruct",
                members : members,
                name : StructUnionNameStr(true, members),
                size : struct_size,
                wrapper_fun : CStructGen(members, struct_size)
            };

            last["$"] = s;
        }

        return s;
    }

    /**
    Wrappers for C Unions
    */

    var CUnions = Object.create(null);

    function CUnion(members)
    {

        var l;
        var mem;
        var key_name;
        var last;
        var next;
        var u;
        var d;
        var key = 1;
        var type_size = 0;
        var union_size = 0;

        if (members == null)
            return {
                wrapper : "CUnion",
                name : "u{}"
            };

        // Otherwise, get a full type wrapper
        l = members.length;
        mem = members[0];
        key_name = mem.name;
        last = CUnions[key_name];
        union_size = mem.size;

        // check for existing wrapper
        if (!last)
            CUnions[key_name] = last = Object.create(null);

        while (key < l)
        {
            mem = members[key++];
            type_size = mem.size;

            // track size of union
            if (type_size > union_size)
                union_size = type_size;

            // wrapper lookup
            key_name = mem.name;
            next = last[key_name];
            if (!next)
                last = last[key_name] = Object.create(null);
            else
                last = next;
        }

        u = last["$"];

        // otherwise, create a new wrapper
        if (!u)
        {
            u = {
                wrapper : "CUnion",
                members : members,
                name : StructUnionNameStr(false, members),
                size : union_size,
                wrapper_fun : CUnionGen(members, union_size)
            };

            last["$"] = u;
        }

        return u;
    }

    /**
    Wrapper for C Enums

    NOTE: all enums share the same type wrapper, the declaration just adds
    a mapping of the member names to values to the FFILibrary.
    */

    var CEnums = {
        wrapper : "CEnum",
        name : "int",
        base_type : "i32",
        size : 4,
        load_fun : "$ir_load_i32",
        store_fun : "$ir_store_i32"
    };

    function CEnum()
    {
        return CEnums;
    }

    /**
    Wrappers for C Functions
    */

    var CFuns = Object.create(null);

    function CFun(ret, args)
    {
        var next = null;
        var key = 0;
        var l = args.length;
        var key_name = ret.name;
        var f;
        var last = CFuns[key_name];

        // Check for existing wrapper
        if (!last)
        {
            last = CFuns[key_name] = Object.create(null);
            if (args.length === 0)
                last = last["void"] = Object.create(null);
            else
                while (key < l)
                    last = last[args[key++].name] = Object.create(null);
        }
        else
        {
            while (key < l)
            {
                key_name = args[key++].name;
                next = last[key_name];
                if (!next)
                    last = last[key_name] = Object.create(null);
                else
                    last = next;
            }
        }

        f = last["$"];

        // Otherwise, create a new one
        if (!f)
        {
            f = {
                wrapper : "CFun",
                args : args,
                ret : ret,
                name : FunNameStr(ret, args),
                wrapper_fun : CFunGen(ret, args)
            };

            last["$"] = f;
        }

        return f;
    }

    /**
    Helper to lookup symbol name
    */
    function getSym(lib, name)
    {
        return eval("function(lib){ return $ir_get_sym(lib, '" + name + "'); };")(lib.handle);
    }

    /**
    Wrap a group of defs appropriately
    */
    function handleDecs(lib, dlist, ctypes)
    {
        var i = 0;
        var l = dlist.length;
        var dec;
        var handle;
        var dec_type;
        var dec_name;

        do
        {
            dec = dlist[i];

            if (!dec.type)
                throw new FFIError("Missing type in declaration: " + (dec.name ? dec.name : ""));

            dec_type = dec.type.wrapper;
            dec_name = dec.name;

            if (dec.storage_class === "typedef")
            {
               ctypes[dec_name] = dec.type;
            }
            else if (dec_name && dec_type === "CFun")
            {
                handle = getSym(lib, dec.name);
                lib[dec_name] = dec.type.wrapper_fun(handle);
            }
            else if (dec_name && dec_type === "CArray")
            {
                handle = getSym(lib, dec_name);
                lib[dec_name] = dec.type.wrapper_fun(handle);
            }
            else if (dec_name && (dec_type === "CStruct" || dec_type === "CUnion"))
            {
                handle = getSym(lib, dec.name);
                lib[dec.name] = dec.type.wrapper_fun(handle);
            }
            else if (dec_name)
            {
                handle = getSym(lib, dec_name);
                lib["get_" + dec_name] = eval("function(handle)\
                                               {\
                                                   return function()\
                                                   {\
                                                       return " + dec.type.load_fun + "(handle, 0);\
                                                   }\
                                               }")(handle);

                lib["set_" + dec_name] = eval("function(handle)\
                                              {\
                                                  return function(val)\
                                                  {\
                                                      return " + dec.type.store_fun + "(handle, 0, val);\
                                                 }\
                                              }")(handle);
            }
        } while (++i < l);

        // clear array
        dlist.length = 0;
    }


    /**
    LIBRARY WRAPPERS
    */

    /*
    FFILib Prototype Object
    */

    var FFILibProto = Object.create(null);;
    FFILibProto.ctypes = null;
    FFILibProto.CType = null;
    FFILibProto.CPtr = CPtr;
    FFILibProto.parser = null;
    FFILibProto.lexer = null;


    /**
    Shortcut to create a function binding with just a sig string or some types
    */
    FFILibProto.cfun = function(fname, sig)
    {
        var fun_str;
        var fun;
        var arg_str;
        var sig_arr;
        var sig_str;
        var i;

        // handle sig strings like "i8,f64,*" etc
        if (typeof sig === "string")
        {
            sig_arr = sig.split(",");
            arg_str = getArgString(sig_arr.length - 1);
            fun_str = "\
                function(lib)\n\
                {\n\
                    var fun_sym = $ir_get_sym(lib, '" + fname + "');\n\
                    return function(" + arg_str  + ")\n\
                    {\n\
                        return $ir_call_ffi(fun_sym, " + ('"' + sig + '"') + (arg_str === "" ? arg_str : (", " + arg_str)) + ");\n\
                    };\n\
                };\n\
            ";
            fun = eval(fun_str)(this.handle);
        }
        else
        {
            // TODO: add support for passing type wrappers
            throw new FFIError("Invalid arg in CFun");
        }

        this[fname] = fun;
        return fun;
    };

    /**
    Parse a group of c definitions and generate bindings etc
    */
    FFILibProto.cdef = function(input)
    {
        var parser = this.parser;
        var lexer = this.lexer;
        var ctypes = this.ctypes;
        var dlist;
        var i;
        var l;

        // initialize parser
        parser.dec_stack = null;
        parser.dec_stacks = null;
        parser.dec_list = dlist = [];
        parser.ctypes = ctypes;
        parser.lex = lexer;
        parser.lib = this;

        // initialize lexer
        lexer.init(input, ctypes);

        // consume *ALL* the decs
        while (true)
        {
            parser.dec = CDec();
            parser.acceptDeclaration();

            dlist.push(parser.dec);
            handleDecs(this, dlist, ctypes);

            lexer.next(true);
            if (lexer.token_type === EOF)
                break;
        };
    };

    /**
    Create a FFILib object
    */
    function FFILib(name)
    {
        var lib = Object.create(FFILibProto);
        var ct = Object.create(CTypes);
        lib.parser = Object.create(Parser);
        lib.lexer = Object.create(Lexer);
        lib.ctypes = ct;
        lib.CType = lib.parser.CType = CTypeFun(ct);

        // Pass null to create a dummy library
        if (name !== null)
            lib.handle = $ir_load_lib(name);

        return lib;
    }


    /**
    FFI UTILITY FUNCTIONS
    */

    // A wrapper for the global symbol object, used by some FFI wrappers and generally handy
    // to have
    var c = FFILib("");

    // Functions used by the FFI library
    c.cfun("malloc", "*,i32");
    c.cfun("realloc", "*,*,i32");
    c.cfun("free", "void,*");

    /**
    TYPE UTILTIY FUNCTIONS
    */

    // It's common to want to pass a null ptr as an arg,
    // so a nice shortcut is provided by the FFI
    var nullPtr = $nullptr;

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
    function jsstrcpy(buff, jstr, len)
    {
        len = len || jstr.length;
        var i;

        for (i = 0; i < len; i++)
            $ir_store_u8(buff, i, $rt_str_get_data(jstr, i));

        $ir_store_u8(buff, len, 0);
        return buff;
    }

    /**
    Create a JS string from a C string
    If n is non-zero copy only n chars from the C string
    An offset can be provided, this is useful for grabbing part of a string, or grabbing a string out
    of a struct/array, etc
    */
    function string(cstr, n, offset)
    {
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
    Create a buffer
    */
    function cbuffer(len)
    {
        return c.malloc(len);
    }

    /**
    Check for a null ptr
    */
    function isNullPtr(x)
    {
        return x === $nullptr;
    }


    /**
    EXPORTS
    */
    exports = {
        c : c,
        FFILib : FFILib,
        string : string,
        cstr : cstr,
        jsstrcpy : jsstrcpy,
        isNullPtr : isNullPtr,
        nullPtr : nullPtr,
        cbuffer : cbuffer
    };

})();
