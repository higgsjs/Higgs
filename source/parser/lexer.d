/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module parser.lexer;

import std.stdio;
import std.file;
import std.string;
import std.format;
import std.regex;
import std.conv;
import std.algorithm;
import std.array;

/**
Operator information structure
*/
struct OpInfo
{
    /// String representation
    wstring str;

    /// Operator arity
    int arity;

    /// Precedence level
    int prec;

    /// Associativity, left-to-right or right-to-left
    char assoc;

    /// Non-associative flag (e.g.: - and / are not associative)
    bool nonAssoc = false;
}

alias const(OpInfo)* Operator;

// Maximum operator precedence
const int MAX_PREC = 16;

// Comma operator precedence (least precedence)
const int COMMA_PREC = 0;

// In operator precedence
const int IN_PREC = 9;

/**
Operator table
*/
OpInfo[] operators = [

    // Member operator
    { "."w, 2, 16, 'l' },

    // Array indexing
    { "["w, 1, 16, 'l' },

    // New/constructor operator
    { "new"w, 1, 16, 'r' },

    // Function call
    { "("w, 1, 15, 'l' },

    // Postfix unary operators
    { "++"w, 1, 14, 'l' },
    { "--"w, 1, 14, 'l' },

    // Prefix unary operators
    { "+"w , 1, 13, 'r' },
    { "-"w , 1, 13, 'r' },
    { "!"w , 1, 13, 'r' },
    { "~"w , 1, 13, 'r' },
    { "++"w, 1, 13, 'r' },
    { "--"w, 1, 13, 'r' },
    { "typeof"w, 1, 13, 'r' },
    { "delete"w, 1, 13, 'r' },

    // Multiplication/division/modulus
    { "*"w, 2, 12, 'l' },
    { "/"w, 2, 12, 'l', true },
    { "%"w, 2, 12, 'l', true },

    // Addition/subtraction
    { "+"w, 2, 11, 'l' },
    { "-"w, 2, 11, 'l', true },

    // Bitwise shift
    { "<<"w , 2, 10, 'l' },
    { ">>"w , 2, 10, 'l' },
    { ">>>"w, 2, 10, 'l' },

    // Relational operators
    { "<"w         , 2, IN_PREC, 'l' },
    { "<="w        , 2, IN_PREC, 'l' },
    { ">"w         , 2, IN_PREC, 'l' },
    { ">="w        , 2, IN_PREC, 'l' },
    { "in"w        , 2, IN_PREC, 'l' },
    { "instanceof"w, 2, IN_PREC, 'l' },

    // Equality comparison
    { "=="w , 2, 8, 'l' },
    { "!="w , 2, 8, 'l' },
    { "==="w, 2, 8, 'l' },
    { "!=="w, 2, 8, 'l' },

    // Bitwise operators
    { "&"w, 2, 7, 'l' },
    { "^"w, 2, 6, 'l' },
    { "|"w, 2, 5, 'l' },

    // Logical operators
    { "&&"w, 2, 4, 'l' },
    { "||"w, 2, 3, 'l' },

    // Ternary conditional
    { "?"w, 3, 2, 'r' },

    // Assignment
    { "="w   , 2, 1, 'r' },
    { "+="w  , 2, 1, 'r' },
    { "-="w  , 2, 1, 'r' },
    { "*="w  , 2, 1, 'r' },
    { "/="w  , 2, 1, 'r' },
    { "%="w  , 2, 1, 'r' },
    { "&="w  , 2, 1, 'r' },
    { "|="w  , 2, 1, 'r' },
    { "^="w  , 2, 1, 'r' },
    { "<<="w , 2, 1, 'r' },
    { ">>="w , 2, 1, 'r' },
    { ">>>="w, 2, 1, 'r' },

    // Comma (sequencing), least precedence
    { ","w, 2, COMMA_PREC, 'l' },
];

/**
Separator tokens
*/
wstring[] separators = [
    ","w,
    ":"w,
    ";"w,
    "("w,
    ")"w,
    "["w,
    "]"w,
    "{"w,
    "}"w
];

/**
Keyword tokens
*/
wstring [] keywords = [
    "var"w,
    "function"w,
    "if"w,
    "else"w,
    "do"w,
    "while"w,
    "for"w,
    "break"w,
    "continue"w,
    "return"w,
    "switch"w,
    "case"w,
    "default"w,
    "throw"w,
    "try"w,
    "catch"w,
    "finally"w,
    "true"w,
    "false"w,
    "null"w
];

/**
Static module constructor to initialize the
separator, keyword and operator tables
*/
static this()
{
    // Sort the tables by decreasing string length
    sort!("a.str.length > b.str.length")(operators);
    sort!("a.length > b.length")(separators);
    sort!("a.length > b.length")(keywords);
}

/**
Find an operator by string, arity and associativity
*/
Operator findOperator(wstring op, int arity = 0, char assoc = '\0')
{
    for (size_t i = 0; i < operators.length; ++i)
    {
        Operator operator = &operators[i];

        if (operator.str != op)
            continue;

        if (arity != 0 && operator.arity != arity)
            continue;

        if (assoc != '\0' && operator.assoc != assoc)
            continue;

        return operator;
    }

    return null;
}

/**
Source code position
*/
class SrcPos
{
    /// File name
    string file;

    /// Line number
    int line;

    /// Column number
    int col;

    this(string file, int line, int col)
    {
        if (file is null)
            file = "";

        this.file = file;
        this.line = line;
        this.col = col;
    }

    override string toString()
    {
        return format("\"%s\"@%d:%d", file, line, col);
    }
}

/**
String stream, used to lex from strings
*/
struct StrStream
{
    /// Input string
    wstring str;

    /// File name
    string file;

    // Current index
    int index = 0;

    /// Current line number
    int line = 1;

    /// Current column
    int col = 1;

    this(wstring str, string file)
    {
        this.str = str;
        this.file = file;
    }

    /// Read a character and advance the current index
    auto readCh()
    {
        wchar ch = (index < str.length)? str[index]:'\0';

        index++;

        if (ch == '\n')
        {
            line++;
            col = 1;
        }
        else if (ch != '\r')
        {
            col++;
        }

        return ch;
    }

    /// Read a character without advancing the index
    auto peekCh()
    {
        wchar ch = (index < str.length)? str[index]:'\0';
        return ch;
    }

    /// Test for a match with a given string, the string is consumed if matched
    bool match(wstring str)
    {
        if (index + str.length > this.str.length)
            return false;

        if (str != this.str[index .. index+str.length])
            return false;

        // Consume the characters
        for (int i = 0; i < str.length; ++i)
            readCh();

        return true;
    }

    /// Test for a match with a regupar expression
    auto match(StaticRegex!(wchar) re)
    {
        auto m = std.regex.match(str[index .. str.length], re);

        if (m.captures.empty == false)
            for (int i = 0; i < m.captures[0].length; ++i)
                readCh();

        return m;
    }

    /// Get a position object for the current index
    SrcPos getPos()
    {
        return new SrcPos(file, line, col);
    }
}

bool whitespace(wchar ch)
{
    return (ch == '\r' || ch == '\n' || ch == ' ' || ch == '\t');
}

bool alpha(wchar ch)
{
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

bool digit(wchar ch)
{
    return (ch >= '0' && ch <= '9');
}

bool identStart(wchar ch)
{
    return alpha(ch) || ch == '_' || ch == '$';
}

bool identPart(wchar ch)
{
    return identStart(ch) || digit(ch);
}

/**
Source token value
*/
struct Token
{
    alias int Type;
    enum : Type
    {
        OP,
        SEP,
        IDENT,
        KEYWORD,
        INT,
        FLOAT,
        STRING,
        REGEXP,
        EOF,
        ERROR
    }

    /// Token type
    Type type;

    /// Token value
    union
    {
        long intVal;
        double floatVal;
        wstring stringVal;
        struct { wstring regexpVal; wstring flagsVal; }
    }

    /// Source position
    SrcPos pos;

    this(Type type, long val, SrcPos pos)
    {
        assert (type == INT);

        this.type = type;
        this.intVal = val;
        this.pos = pos;
    }

    this(Type type, double val, SrcPos pos)
    {
        assert (type == FLOAT);

        this.type = type;
        this.floatVal = val;
        this.pos = pos;
    }

    this(Type type, wstring val, SrcPos pos)
    {
        assert (
            type == OP      ||
            type == SEP     ||
            type == IDENT   ||
            type == KEYWORD ||
            type == STRING  ||
            type == ERROR
        );

        this.type = type;
        this.stringVal = val;
        this.pos = pos;
    }

    this(Type type, wstring re, wstring flags, SrcPos pos)
    {
        assert (type == REGEXP);

        this.type = type;
        this.regexpVal = re;
        this.flagsVal = flags;
        this.pos = pos;
    }

    this(Type type, SrcPos pos)
    {
        assert (type == EOF);

        this.type = type;
        this.pos = pos;
    }

    string toString()
    {
        switch (type)
        {

            case OP:        return format("operator:%s"  , stringVal);
            case SEP:       return format("separator:%s" , stringVal);
            case IDENT:     return format("identifier:%s", stringVal);
            case KEYWORD:   return format("keyword:%s"   , stringVal);
            case INT:       return format("int:%s"       , intVal);
            case FLOAT:     return format("float:%f"     , floatVal);
            case STRING:    return format("string:%s"    , stringVal);
            case REGEXP:    return format("regexp:/%s/%s", regexpVal, flagsVal);
            case ERROR:     return format("error:%s"     , stringVal);
            case EOF:       return "EOF";

            default:
            return "token";
        }
    }
}

/**
Lexer flags, used to parameterize lexical analysis
*/
alias uint LexFlags;
const LexFlags LEX_MAYBE_RE = 1 << 0;

/**
Lexer error exception
*/
class LexError : Error
{
    this(wstring msg, SrcPos pos)
    {
        this.msg = msg;
        this.pos = pos;

        super(to!string(msg));
    }

    wstring msg;
    SrcPos pos;
}

/**
Read a string constant from a stream
*/
wstring getString(ref StrStream stream, wchar stopChar)
{
    wstring str = "";

    // Until the end of the string
    CHAR_LOOP: 
    for (;;)
    {
        wchar ch = stream.readCh();

        if (ch == stopChar)
            break;

        // End of file
        if (ch == '\0')
        {
            throw new LexError(
                "EOF in literal",
                stream.getPos()
            );
        }

        // Escape sequence
        if (ch == '\\')
        {
            // Hexadecimal escape sequence regular expressions
            enum hexRegex = ctRegex!(`^x([0-9|a-f|A-F]{2})`w);
            enum uniRegex = ctRegex!(`^u([0-9|a-f|A-F]{4})`w);

            // Try to match a hexadecimal escape sequence
            auto m = stream.match(hexRegex);
            if (m.empty == true)
                m = stream.match(uniRegex);
            if (m.empty == false)
            {
                auto hexStr = m.captures[1];

                int charCode;
                formattedRead(hexStr, "%x", &charCode);

                str ~= cast(wchar)charCode;

                continue CHAR_LOOP;
            }

            // Octal escape sequence regular expression
            enum octRegex = ctRegex!(`^([0-7][0-7]?[0-7]?)`w);

            // Try to match an octal escape sequence
            m = stream.match(octRegex);
            if (m.empty == false)
            {
                auto octStr = m.captures[1];

                int charCode;
                formattedRead(octStr, "%o", &charCode);

                str ~= cast(char)charCode;

                continue CHAR_LOOP;
            }

            auto code = stream.readCh();

            switch (code)
            {
                case 'r' : str ~= '\r'; break;
                case 'n' : str ~= '\n'; break;
                case 'v' : str ~= '\v'; break;
                case 't' : str ~= '\t'; break;
                case 'f' : str ~= '\f'; break;
                case 'b' : str ~= '\b'; break;
                case 'a' : str ~= '\a'; break;
                case '\\': str ~= '\\'; break;
                case '\"': str ~= '\"'; break;
                case '\'': str ~= '\''; break;

                // Multiline string continuation
                case '\n': break;

                // By default, add the escape character as is
                default:
                str ~= code;
            }
        }

        // Normal character
        else
        {
            str ~= ch;
        }
    }

    return str;
}

/**
Get the first token from a stream
*/
Token getToken(ref StrStream stream, LexFlags flags)
{
    wchar ch;

    // Consume whitespace and comments
    for (;;)
    {
        ch = stream.peekCh();

        // Whitespace characters
        if (whitespace(ch))
        {
            stream.readCh();
        }

        // Single-line comment
        else if (stream.match("//"))
        {
            for (;;)
            {
                ch = stream.readCh();
                if (ch == '\n' || ch == '\0')
                    break;
            }
        }

        // Multi-line comment
        else if (stream.match("/*"))
        {
            for (;;)
            {
                if (stream.match("*/"))
                    break;
                if (stream.peekCh() == '\0')
                    return Token(
                        Token.ERROR,
                        "end of stream in multi-line comment", 
                        stream.getPos()
                    );
                ch = stream.readCh();
            }
        }

        // Otherwise
        else
        {
            break;
        }
    }

    // Get the position at the start of the token
    SrcPos pos = stream.getPos();

    // Hexadecimal number
    if (stream.match("0x"))
    {
        enum hexRegex = ctRegex!(`^[0-9|a-f|A-F]+`w);
        auto m = stream.match(hexRegex);

        if (m.empty)
        {
            return Token(
                Token.ERROR,
                "invalid hex number", 
                pos
            );
        }

        auto hexStr = m.captures[0];
        long val;
        formattedRead(hexStr, "%x", &val);

        return Token(Token.INT, val, pos);
    }

    // Number
    if (digit(ch))
    {
        enum fpRegex = ctRegex!(`^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?`w);
    
        auto m = stream.match(fpRegex);
        assert (m.empty == false);
        auto numStr = m.captures[0];        

        // If this is a floating-point number
        if (countUntil(numStr, '.') != -1 ||
            countUntil(numStr, 'e') != -1 ||
            countUntil(numStr, 'E') != -1)
        {
            double val = to!(double)(numStr);
            return Token(Token.FLOAT, val, pos);
        }

        // Integer number
        else
        {
            long val = to!(long)(numStr);
            return Token(Token.INT, val, pos);
        }
    }

    // String constant
    if (ch == '"' || ch == '\'')
    {
        auto openChar = stream.readCh();

        try
        {
            auto str = getString(stream, openChar);
            return Token(Token.STRING, str, pos);
        }

        catch (LexError err)
        {
            return Token(Token.ERROR, err.msg, err.pos);
        }
    }

    // End of file
    if (ch == '\0')
    {
        return Token(Token.EOF, pos);
    }

    // Identifier or keyword
    if (identStart(ch))
    {
        stream.readCh();
        wstring identStr = ""w ~ ch;

        for (;;)
        {
            ch = stream.peekCh();
            if (identPart(ch) == false)
                break;
            stream.readCh();
            identStr ~= ch;
        }

        // Try matching all keywords
        if (countUntil(keywords, identStr) != -1)
            return Token(Token.KEYWORD, identStr, pos);

        // Try matching all operators
        foreach (op; operators)
            if (identStr == op.str)
                return Token(Token.OP, identStr, pos);

        return Token(Token.IDENT, identStr, pos);
    }

    // Regular expression
    if ((flags & LEX_MAYBE_RE) && ch == '/')
    {
        // Read the opening slash
        stream.readCh();

        // Read the pattern
        wstring reStr = "";
        for (;;)
        {
            ch = stream.readCh();

            if (ch == '\\' && stream.peekCh() == '/')
            {
                stream.readCh();
                reStr ~= "\\/"w;
                continue;
            }

            if (ch == '/')
                break;

            // End of file
            if (ch == '\0')
                return Token(Token.ERROR, "EOF in literal", stream.getPos());

            reStr ~= ch;
        }

        // Read the flags
        wstring reFlags = "";
        for (;;)
        {
            ch = stream.peekCh();

            if (ch != 'i' && ch != 'g' && ch != 'm' && ch != 'y')
                break;

            stream.readCh();

            reFlags ~= ch;
        }

        //writefln("reStr: \"%s\"", reStr);

        return Token(Token.REGEXP, reStr, reFlags, pos);
    }

    // Try matching all separators    
    foreach (sep; separators)
        if (stream.match(sep))
            return Token(Token.SEP, sep, pos);

    // Try matching all operators
    foreach (op; operators)
        if (stream.match(op.str))
            return Token(Token.OP, op.str, pos);

    // Invalid character
    int charVal = stream.readCh();
    wstring charStr;
    if (charVal >= 33 && charVal <= 126)
        charStr ~= "'"w ~ cast(wchar)charVal ~ "', "w;
    charStr ~= to!wstring(format("0x%04x", charVal));
    return Token(
        Token.ERROR,
        "unexpected character ("w ~ charStr ~ ")"w, 
        pos
    );
}

/**
Token stream, to simplify parsing
*/
class TokenStream
{
    /// String stream before the next token
    private StrStream preStream;

    /// String stream after the next token
    private StrStream postStream;

    /// Flag indicating a newline occurs before the next token
    private bool nlPresent;

    /// Next token to be read
    private Token nextToken;

    // Next token available flag
    private bool tokenAvail;

    // Lexer flags used when reading the next token
    private LexFlags lexFlags;

    /**
    Constructor to tokenize a string
    */
    this(wstring str, string file)
    {
        this.preStream = StrStream(str, file);

        this.tokenAvail = false;
        this.nlPresent = false;
    }

    /**
    Copy constructor for this token stream. Allows for backtracking
    */
    this(TokenStream that)
    {
        // Copy the string streams
        this.preStream = that.preStream;
        this.postStream = that.postStream;

        this.nlPresent = that.nlPresent;
        this.nextToken = that.nextToken;
        this.tokenAvail = that.tokenAvail;
        this.lexFlags = that.lexFlags;
    }

    /**
    Method to backtrack to a previous state
    */
    void backtrack(TokenStream that)
    {
        // Copy the string streams
        this.preStream = that.preStream;
        this.postStream = that.postStream;

        this.nlPresent = that.nlPresent;
        this.nextToken = that.nextToken;
        this.tokenAvail = that.tokenAvail;
        this.lexFlags = that.lexFlags;
    }

    SrcPos getPos()
    {
        return preStream.getPos();
    }

    Token peek(LexFlags lexFlags = 0)
    {
        if (tokenAvail is false || this.lexFlags != lexFlags)
        {
            postStream = preStream;
            nextToken = getToken(postStream, lexFlags);
            tokenAvail = true;
            lexFlags = lexFlags;
        }

        return nextToken;
    }

    Token read(LexFlags flags = 0)
    {
        auto t = peek(flags);

        // Cannot read the last (EOF) token
        assert (t.type != Token.EOF, "cannot read final EOF token");

        // Read the token
        preStream = postStream;
        tokenAvail = false;

        // Test if a newline occurs before the new front token
        nlPresent = (peek.pos.line > t.pos.line);

        return t;
    }

    bool newline()
    {
        return nlPresent;
    }

    bool peekKw(wstring keyword)
    {
        auto t = peek();
        return (t.type == Token.KEYWORD && t.stringVal == keyword);
    }

    bool peekSep(wstring sep)
    {
        auto t = peek();
        return (t.type == Token.SEP && t.stringVal == sep);
    }

    bool matchKw(wstring keyword)
    {
        if (peekKw(keyword) == false)
            return false;
        read();

        return true;
    }

    bool matchSep(wstring sep)
    {
        if (peekSep(sep) == false)
            return false;
        read();

        return true;
    }

    bool eof()
    {
        return peek().type == Token.EOF;
    }
}

