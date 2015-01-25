/* _________________________________________________________________________
 *
 *             Tachyon : A Self-Hosted JavaScript Virtual Machine
 *
 *
 *  This file is part of the Tachyon JavaScript project. Tachyon is
 *  distributed at:
 *  http://github.com/Tachyon-Team/Tachyon
 *
 *
 *  Copyright (c) 2011, Universite de Montreal
 *  All rights reserved.
 *
 *  This software is licensed under the following license (Modified BSD
 *  License):
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are
 *  met:
 *    * Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the Universite de Montreal nor the names of its
 *      contributors may be used to endorse or promote products derived
 *      from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 *  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 *  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 *  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL UNIVERSITE DE
 *  MONTREAL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * _________________________________________________________________________
 */

(function () {

function RegExpParser () {}

/**
Parses pattern and returns corresponding AST.
*/
RegExpParser.prototype.parse = function (
    pattern
)
{
    this.pattern = pattern;

    // Init current char cursor.
    this.index = -1;
    this.advance();
    this.lastGroupId = -1;

    // Parse root disjunction.
    return this.parseDisjunction(true, false);
}

/**
Returns current character code.
*/
RegExpParser.prototype.current = function ()
{
    return this.curCharCode;
}

/**
Look ahead one character code.
*/
RegExpParser.prototype.lookAhead = function ()
{
    return this.index === this.pattern.length - 1 ?
            null :
            this.pattern.charCodeAt(this.index + 1);
}

/**
Advance cursor one character.
*/
RegExpParser.prototype.advance = function ()
{
    this.curCharCode = ++this.index < this.pattern.length ?
                       this.pattern.charCodeAt(this.index) :
                       null;
}

RegExpParser.prototype.error = function (
    msg
)
{
    throw SyntaxError("RegExp parser error at " + this.index + " : " + msg);
}

/**
    Disjunction ::
        Alternative
        Alternative | Disjunction
*/
function RegExpDisjunction (
    captures,
    isRoot,
    groupId
)
{
    this.alternatives = [];
    this.captures = captures;
    this.isRoot= isRoot;
    this.groupId = groupId;
}

/**
    Disjunction pretty print.
*/
RegExpDisjunction.prototype.pp = function (
    level
)
{
    if (level === undefined)
        level = 0;

    var s = genLevel(level) + "Disjunction (" + (this.captures ? "capture)\n" : "no capture)\n");

    for (var i = 0; i < this.alternatives.length; ++i)
        s += this.alternatives[i].pp(level + 1);
    return s;
}

/**
    Parse a disjunction from the current position.
*/
RegExpParser.prototype.parseDisjunction = function (
    captures,
    isRoot
)
{
    var node = new RegExpDisjunction(captures, isRoot, ++(this.lastGroupId));

    while (true)
    {
        switch (this.current())
        {
            case null: // EOL
            if (node.isRoot)
                this.advance();
            return node;

            case 41: // ')'
            this.advance();
            if (this.isRoot)
                this.error("unmatched )");
            return node;

            case 124: // '|'
            this.advance();
            break;

            default:
            node.alternatives.push(this.parseAlternative());
            break;
        }
    }
}

/**
    Alternative ::
      [empty]
      Alternative Term
*/
function RegExpAlternative ()
{
    this.terms = [];
}

/**
    Alternative pretty print.
*/
RegExpAlternative.prototype.pp = function (
    level
)
{
    var s = genLevel(level) + "Alternative\n";

    for (var i = 0; i < this.terms.length; i++)
        s += this.terms[i].pp(level + 1);
    return s;
}

/**
    Parse an alternative from the current character.
*/
RegExpParser.prototype.parseAlternative = function ()
{
    var node = new RegExpAlternative();

    while (true)
    {
        switch (this.current())
        {
            case null: // EOL
            case 124: // '|'
            case 41: // ')'
            return node;

            default:
            node.terms.push(this.parseTerm());
        }
    }
}

/**
    Term ::
      Assertion
      Atom
      Atom Quantifier
*/
function RegExpTerm () {}

/**
    Term pretty print.
*/
RegExpTerm.prototype.pp = function (level)
{
    var s = genLevel(level) + "Term\n";

    if (this.prefix !== undefined)
        s += this.prefix.pp(level + 1);
    if (this.quantifier !== undefined)
        s += this.quantifier.pp(level + 1);
    return s;
}

/**
    Parse a term from the current character.
*/
RegExpParser.prototype.parseTerm = function ()
{
    var node = new RegExpTerm();

    switch (this.current())
    {
        case null: // EOL
        return node;

        // Assertion parsing.
        case 94: // '^'
        case 36: // '$'
        node.prefix = new RegExpAssertion(this.current(), true);
        this.advance();
        return node;

        // Sub-disjunction (either atom or assertion).
        case 40: // '('
        this.advance();
        if (this.current() === 63) // '?'
        {
            this.advance();
            if (this.current() === 61) // '='
            {
                this.advance();
                node.prefix = new RegExpAssertion(this.parseDisjunction(false, false), true);
            }
            else if (this.current() === 33) // '!'
            {
                this.advance();
                node.prefix = new RegExpAssertion(this.parseDisjunction(false, false), false);
            }
            else if (this.current() === 58) // ':'
            {
                this.advance();
                node.prefix = new RegExpAtom(this.parseDisjunction(false, false));
            }
            else
            {
                this.error("invalid group");
            }
        }
        else
        {
            node.prefix = new RegExpAtom(this.parseDisjunction(true, false));
        }
        break;

        // Escaped sequence
        case 92: // '\'
        this.advance();
        // \b and \B are word boundary assertion.
        if (this.current() === 98) // 'b'
        {
            this.advance();
            node.prefix = new RegExpAssertion(98, true);
        }
        else if (this.current() === 66) // 'B'
        {
            this.advance();
            node.prefix = new RegExpAssertion(98, false);
        }
        else
        {
            node.prefix = new RegExpAtom(this.parseAtomEscape());
        }
        break;

        // Atom
        case 46: // '.'
        // Equivalent to everything except newline.
        var cc = new RegExpCharacterClass(false);
        cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(10)));
        node.prefix = new RegExpAtom(cc);
        this.advance();
        break;

        case 41: // ')'
        return node;

        // CharacterClass
        case 91: // '['
        node.prefix = new RegExpAtom(this.parseCharacterClass());
        break;

        // Skip terminator and quantifier since it will be parsed just below.
        case 42: // '*'
        case 43: // '+'
        case 63: // '?'
        case 123: // '{'
        case 125: // '}'
        case 93: // ']'
        case 93: // '|'
        break;

        // PatternCharacter
        default:
        node.prefix = new RegExpAtom(new RegExpPatternCharacter(this.current()));
        this.advance();
        break;
    }

    // Quantifier reading.
    switch (this.current())
    {
        case 42: // '*'
        case 43: // '+'
        case 63: // '?'
        case 123: // '{'
        if (node.prefix === undefined || node.prefix instanceof RegExpAssertion)
            this.error("invalid quantifier without atom");
        else
            node.quantifier = this.parseQuantifier();
    }

    if (node.quantifier === undefined)
    {
        node.quantifier = new RegExpQuantifier();
        node.quantifier.greedy = true;
        node.quantifier.min = 1;
        node.quantifier.max = 1;
    }
    return node;
}

/**
    Assertion ::
      ^
      $
      \b
      \B
      (?= Disjunction)
      (?! Disjunction)

      @params {Integer | RegExpDisjunction} value
*/
function RegExpAssertion(
    value,
    positive
)
{
    this.value = value;
    this.positive = positive;
}

RegExpAssertion.prototype.pp = function (level)
{
    var s = genLevel(level) + "Assertion (" + (this.positive ? "positive) " : "negative) ");

    if (this.value instanceof RegExpDisjunction)
        s += "\n" + this.value.pp(level + 1);
    else
        s += " " + this.value + "\n";
    return s;
}

/**
    Quantifier ::
        QuantifierPrefix
        QuantifierPrefix ?

    QuantifierPrefix ::
        *
        +
        ?
        { DecimalDigits }
        { DecimalDigits , }
        { DecimalDigits , DecimalDigits }
*/

function RegExpQuantifier ()
{
    this.min = 1;
    this.max = 1;
    this.greedy = true;
}

/**
    Quantifier pretty print.

    @params: {Integer} level, term's depth in the tree.
*/
RegExpQuantifier.prototype.pp = function(level)
{
    return genLevel(level) + "Quantifier (min " + this.min + ", max " + (this.max === -1 ? "inf" : this.max) + ")\n";
}

/**
    Parse quantifier from current character.
*/
RegExpParser.prototype.parseQuantifier = function ()
{
    var node = new RegExpQuantifier();

    switch (this.current())
    {
        case 42: // '*'
        node.min = 0;
        node.max = -1;
        this.advance();
        break;

        case 43: // '+'
        node.min = 1;
        node.max = -1;
        this.advance();
        break;

        case 63: // '?'
        node.min = 0;
        node.max = 1;
        this.advance();
        break;

        case 123: // '{'
        this.advance();
        // Parse min limit.
        if (this.current() >= 48 && this.current() <= 57) // 0-9
        {
            node.min = this.parseDecimalDigit();
        }
        else
        {
            this.error("ill formed quantifier");
        }

        if (this.current() === 44) // ','
        {
            this.advance();

            if (this.current() >= 48 && this.current() <= 57)
            {
                node.max = this.parseDecimalDigit();
            }
            else
            {
                node.max = -1; // infinity
            }
        }
        else
        {
            node.max = node.min;
        }

        // Should be closing }
        if (this.current() === 125)
        {
            this.advance();
        }
        else
        {
            this.error("ill formed quantifier");
        }
        break;
    }

    // Is the quantifier non greedy ?
    if (this.current() === 63) // '?'
    {
        this.advance();
        node.greedy = false;
    }
    return node;
}

/**
    Atom ::
        PatternCharacter
        .
        \ AtomEscape
        CharacterClass
        ( Disjunction )
        (?: Disjunction )

    @params: {Integer, RegExpDisjunction, RegExpAssertion} value
*/
function RegExpAtom(
    value
)
{
    this.value = value;
}

/**
    Atom pretty print.

    @params: {Integer} level, atom's depth in the tree.
*/
RegExpAtom.prototype.pp = function (
    level
)
{
    return genLevel(level) + "Atom\n" + this.value.pp(level + 1);
}

/**
    PatternCharacter

    @params: {Integer} value, character code.
*/
function RegExpPatternCharacter(
    value
)
{
    this.value = value;
}

/**
   PatternCharacter pretty print.
*/
RegExpPatternCharacter.prototype.pp = function (
    level
)
{
    return genLevel(level) + "PatternCharacter " + this.value + "\n";
}

/**
    BackReference
*/
function RegExpBackReference (
    index
)
{
    this.index = index;
}

/**
   BackReference pretty print.
*/
RegExpBackReference.prototype.pp = function (
    level
)
{
    return genLevel(level) + "BackReference : " + this.index + "\n";
}

function RegExpControlSequence (
    value
)
{
    this.value = value;
}

RegExpControlSequence.prototype.pp = function (
    level
)
{
    return genLevel(level) + "ControlSequence : " + this.value + "\n";
}

RegExpParser.prototype.parseAtomEscape = function ()
{
    var cc;

    if (this.current() >= 49 && this.current() <= 57)
    {
        return new RegExpBackReference( this.parseDecimalDigit() );
    }
    else
    {
        switch (this.current())
        {
            case 100: // 'd'
            // Decimal digits class.
            cc = new RegExpCharacterClass(true);
            this.advance();
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(48), new RegExpPatternCharacter(57)));
            return cc;

            case 68: // 'D' (anything but digits)
            cc = new RegExpCharacterClass(true);
            this.advance();
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(1), new RegExpPatternCharacter(47)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(58), new RegExpPatternCharacter(0xFFFF)));
            return cc;

            case 115: // 's' (whitespace)
            cc = new RegExpCharacterClass(true);
            this.advance();
            // Whitespace characters.
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(9)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(11)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(12)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(32)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(160)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(65279)));
            // Line terminator characters.
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(10)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(13)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(8232)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(8233)));
            return cc;

            case 83: // 'S' (anything but whitespace)
            cc = new RegExpCharacterClass(true);
            this.advance();
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(1), new RegExpPatternCharacter(8)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(14), new RegExpPatternCharacter(31)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(33), new RegExpPatternCharacter(159)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(161), new RegExpPatternCharacter(8231)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(8234), new RegExpPatternCharacter(0xFFFF)));
            return cc;

            case 119: // 'w' [A-Za-z0-9_]
            cc = new RegExpCharacterClass(true);
            this.advance();
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(65), new RegExpPatternCharacter(90)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(97), new RegExpPatternCharacter(122)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(48), new RegExpPatternCharacter(57)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(95)));
            return cc;

            case 87: // 'W' [^A-Za-z0-9_]
            cc = new RegExpCharacterClass(true);
            this.advance();
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(1), new RegExpPatternCharacter(47)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(58), new RegExpPatternCharacter(64)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(91), new RegExpPatternCharacter(94)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(96)));
            cc.classAtoms.push(new RegExpClassAtom(new RegExpPatternCharacter(123), new RegExpPatternCharacter(0xFFFF)));
            return cc;

            case 99: // 'c'
            // Parse control sequence.
            this.advance();
            if ((this.current() >= 65 && this.current() <= 90) || // A-Z
                (this.current() >= 97 && this.current() <= 122)) // a-z
            {
                var c = this.current();
                this.advance();
                return new RegExpControlSequence(new RegExpPatternCharacter(c));
            }
            else
            {
                this.error("invalid control sequence");
            }
            return node;

            case 120: // 'x'
            // Parse hexadecimal sequence.
            this.advance();
            return new RegExpPatternCharacter(this.parseHexadecimalSequence(2));

            case 117: // 'u'
            // Parse unicode hexadecimal sequence.
            this.advance();
            return new RegExpPatternCharacter(this.parseHexadecimalSequence(4));

            case 116: // 't'
            this.advance();
            return new RegExpPatternCharacter(9); // Tabulation

            case 110: // 'n'
            this.advance();
            return new RegExpPatternCharacter(10); // Line terminator

            case 118: // 'v'
            this.advance();
            return new RegExpPatternCharacter(11);

            case 102: // 'f'
            this.advance();
            return new RegExpPatternCharacter(12);

            case 114: // 'r'
            this.advance();
            return new RegExpPatternCharacter(13);

            case 48: // null character
            this.advance();
            return new RegExpPatternCharacter(0);

            default:
            var c = this.current();
            this.advance();
            return new RegExpPatternCharacter(c);
        }
    }
}

/**
    Parse an hexadecimal sequence of <size> characters and
    returns its decimal value.
*/
RegExpParser.prototype.parseHexadecimalSequence = function (
    size
)
{
    var value = 0;

    while (size-- > 0)
    {
        if (this.current() >= 48 && this.current() <= 57) // 0-9
        {
           value = value * 16 + (this.current() - 48);
        }
        else if (this.current() >= 65 && this.current() <= 70) // A-F
        {
           value = value * 16 + (this.current() - 55);
        }
        else if (this.current() >= 97 && this.current() <= 102) // a-f
        {
           value = value * 16 + (this.current() - 87);
        }
        else
        {
            this.error("invalid hexadecimal sequence");
        }
        this.advance();
    }

    return value;
}

/**
    CharacterClass
*/
function RegExpCharacterClass (
    positive
)
{
    this.classAtoms = [];
    this.positive = positive;
}

RegExpCharacterClass.prototype.pp = function (level)
{
    var s = genLevel(level) + "CharacterClass " + (this.positive ? "inclusive" : "exclusive") + "\n";

    for (var i = 0; i < this.classAtoms.length; ++i)
        s += this.classAtoms[i].pp(level + 1);
    return s;
}

RegExpParser.prototype.parseCharacterClass = function ()
{
    var node = new RegExpCharacterClass(true);

    this.advance(); // consume [

    if (this.current() === 94) // '^'
    {
        // Set the character class type to exclusive if it starts with [^
        this.advance();
        node.positive = false;
    }

    while (true)
    {
        switch (this.current())
        {
            case null: // EOL
            this.error("unclosed character class");
            return node;

            case 93: // ']'
            this.advance();
            return node;

            default:
            node.classAtoms.push(this.parseClassAtom());
        }
    }
}

function RegExpClassAtom (
    min,
    max
)
{
    this.min = min;
    this.max = max;
}

/**
    ClassAtom pretty print.
*/
RegExpClassAtom.prototype.pp = function (level)
{
    var s = genLevel(level) + "ClassAtom\n";

    if (this.min === undefined)
        s += "all\n";
    else
        s += this.min.pp(level + 1);
    if (this.max !== undefined)
        s += this.max.pp(level + 1);
    return s;
}

RegExpParser.prototype.parseClassAtom = function ()
{
    var node = new RegExpClassAtom();

    switch (this.current())
    {
        case 92: // '\'
        this.advance();
        node.min = this.parseAtomEscape();
        break;

        case 93: // ']'
        break;

        default:
        node.min = new RegExpPatternCharacter(this.current());
        this.advance();
    }

    if (this.current() === 45 && this.lookAhead() !==  93) // '-]'
    {
        this.advance();
        switch (this.current())
        {
            case 92: // '\'
            this.advance();
            node.max = this.parseAtomEscape();
            break;

            default:
            node.max = new RegExpPatternCharacter(this.current());
            this.advance();
        }
    }
    return node;
}

RegExpParser.prototype.parseDecimalDigit = function ()
{
    var value = 0;

    while (this.current() >= 48 && this.current() <= 57) // 0-9
    {
       value = (value * 10) + this.current() - 48;
       this.advance();
    }
    return value;
}

/**
    Generate level string for pretty print
*/
function genLevel (
    level
)
{
    var s = "";

    for (var i = 0; i < level; i++)
        s += " | ";
    if (level > 0)
        s += " ";
    return s;
}

/**
Cache of patterns and flags to parsed regular expressions
*/
var reCache = new Map();

function RegExp (
    pattern,
    flags
)
{
    // Try to find a cached regexp object for these arguments
    var flagsMap = reCache.get(pattern);
    if (flagsMap !== undefined)
    {
        var cached = flagsMap.get(flags);
        if (cached !== undefined)
            return cached;
    }

    if (pattern instanceof RegExp)
        return pattern;

    if (!(this instanceof RegExp))
        return new RegExp(pattern, flags);

    this.source = (pattern === undefined ? "" : pattern);
    this.global = false;
    this.ignoreCase = false;
    this.multiline = false;
    this.lastIndex = 0;

    // Extract flags
    if (flags !== undefined)
    {
        for (var i = 0; i < flags.length; ++i)
        {
            if (flags.charCodeAt(i) === 103) // 'g'
            {
                this.global = true;
            }
            else if (flags.charCodeAt(i) === 105) // 'i'
            {
                this.ignoreCase = true;
            }
            else if (flags.charCodeAt(i) === 109) // 'm'
            {
                this.multiline = true;
            }
        }
    }

    // Parse pattern and compile it to an automata
    var ast = new RegExpParser().parse(pattern);

    var prop = {
        value: astToAutomata(ast, this.global, this.ignoreCase, this.multiline),
        writable: false,
        configurable: false,
        enumerable: false
    };

    Object.defineProperty(this, "_automata", prop);

    // Cache the parsed regular expression object
    var flagsMap = reCache.get(pattern);
    if (flagsMap === undefined)
    {
        flagsMap = new Map();
        reCache.set(pattern, flagsMap);
    }
    flagsMap.set(flags, this);
}

/**
    Execution context
*/
function RegExpContext (
    input,
    captures
)
{
    this.input = input;
    this.index = 0;
    this.currentCharCode = input.charCodeAt(0);
    this.captures = captures;
    this.backtrackStack = [];
}

/**
    Advance one character in the input
*/
RegExpContext.prototype.consume = function ()
{
    this.setIndex(++this.index);
}

/**
    Set context to given index.
*/
RegExpContext.prototype.setIndex = function (
    index
)
{
    this.index = index;
    this.currentCharCode = this.input.charCodeAt(this.index);
}

/**
    Returns true if context is at the end of input, false otherwise.
*/
RegExpContext.prototype.endOfInput = function ()
{
    return this.index >= this.input.length;
}

/**
    Returns the node on top of teh backtrack stack.
*/
RegExpContext.prototype.getBTNode = function ()
{
    return this.backtrackStack[this.backtrackStack.length - 1];
}

/**
    Capture stucture.
*/
function RegExpCapture ()
{
    this.start = -1;
    this.end = -1;
}

/**
    Group stucture.
*/
function RegExpGroup (
    capture
)
{
    this.capture = capture;
    this.subcaptures = [];
}

/**
    Save inner captures state of the group into an array of integers.
*/
RegExpGroup.prototype.dumpState = function ()
{
    var state;

    if (this.capture)
    {
        state = new Array(this.subcaptures.length * 2 + 2);
        state[0] = this.capture.start;
        state[1] = this.capture.end;
        // Add every subcaptures.
        for (var i = 0, j = 2; i < this.subcaptures.length; ++i, j += 2)
        {
            state[j] = this.subcaptures[i].start;
            state[j + 1] = this.subcaptures[i].end;
        }
    }
    else
    {
        state = new Array(this.subcaptures.length * 2);
        // Add every subcaptures.
        for (var i = 0, j = 0; i < this.subcaptures.length; ++i, j += 2)
        {
            state[j] = this.subcaptures[i].start;
            state[j + 1] = this.subcaptures[i].end;
        }
    }
    return state;
}

/**
    Restore captures state from an integer array.
*/
RegExpGroup.prototype.restoreState = function (
    state
)
{
    if (this.capture)
    {
        this.capture.start = state[0];
        this.capture.end = state[1];
        for (var i = 0, j = 2; i < this.subcaptures.length; ++i, j += 2)
        {
            this.subcaptures[i].start = state[j];
            this.subcaptures[i].end = state[j + 1];
        }
    }
    else
    {
        for (var i = 0, j = 0; i < this.subcaptures.length; ++i, j += 2)
        {
            this.subcaptures[i].start = state[j];
            this.subcaptures[i].end = state[j + 1];
        }
    }
}

/**
    Set every inner capture and subcaptures to empty (-1, -1).
*/
RegExpGroup.prototype.clear = function ()
{
    if (this.capture)
    {
        this.capture.start = -1;
        this.capture.end = -1;
    }

    for (var i = 0; i < this.subcaptures.length; ++i)
        this.subcaptures[i].start = this.subcaptures[i].end = -1;
}

/**
    Basic automata actions.
*/

/**
    Basic node : one out transition, not final by default.
*/
function RegExpNode (
    transition
)
{
    this.transition = transition;
    this._final = false;
}

/**
    Basic node step : simply execute out transition.
*/
RegExpNode.prototype.step = function (
    context
)
{
    return this.transition.exec(context);
}

/**
    Basic transition : one destination node.
*/
function RegExpTransition (
    destNode
)
{
    this.destNode = destNode;
}

/**
    Basic transition exec : simply returns destination node.
*/
RegExpTransition.prototype.exec = function (
    context
)
{
    return this.destNode;
}

/**
    Group automata actions.
*/

function RegExpGroupNode (
    group
)
{
    this.group = group;
    this.nextPath = 0;
    this.transitions = [];
    this.groupBacktrackStack = [];
    this.contextIndex = -1;
    this._final = false;
}

RegExpGroupNode.prototype.addAlternative = function (
    alternativeTransition
)
{
    this.transitions.push(alternativeTransition);
}

RegExpGroupNode.prototype.reset = function ()
{
    this.group.clear();
    this.nextPath = 0;
}

RegExpGroupNode.prototype.step = function (
    context
)
{
    while (this.nextPath < this.transitions.length)
    {
        var next = this.transitions[this.nextPath].exec(context);
        if (next !== null)
            return next;
        ++this.nextPath;
    }

    return null;
}

RegExpGroupNode.prototype.backtrack = function (
    context
)
{
    // Restore index & captures from captures stack.
    var state = this.groupBacktrackStack[this.groupBacktrackStack.length - 1];

    // Restore index
    if (!this.group.capture || this.group.capture !== context.captures[0])
        context.setIndex(state[0]);
    else
        context.setIndex(0);

    // Set next path.
    if (++(this.nextPath) >= this.transitions.length)
    {
        if (!this.group.capture || this.group.capture !== context.captures[0])
            this.group.restoreState(state[1]);
        else
            this.group.clear();
        this.groupBacktrackStack.pop();
        context.backtrackStack.pop();
        return false;
    }

    this.group.clear();
    if (this.group.capture)
        this.group.capture.start = context.index;

    return true;
}

function RegExpGroupOpenTransition (
    destNode,
    group
)
{
    this.destNode = destNode;
    this.group = group;
}

RegExpGroupOpenTransition.prototype.exec = function (
    context
)
{
    // Save state.
    if (!this.group.capture || this.group.capture !== context.captures[0])
    {
        var state = new Array(2);
        state[0] = context.index;
        state[1] = this.group.dumpState();

        this.destNode.groupBacktrackStack.push(state);
    }

    // Reset node path and captures.
    this.destNode.reset();

    // Set start index for this group's capture.
    if (this.group.capture)
        this.group.capture.start = context.index;

    // Push group node onto backtrack stack.
    context.backtrackStack.push(this.destNode);

    return this.destNode;
}

function RegExpGroupCloseTransition (
    destNode,
    group
)
{
    this.destNode = destNode;
    this.group = group;
}

RegExpGroupCloseTransition.prototype.exec = function (
    context
)
{
    if (this.group.capture)
        this.group.capture.end = context.index;

    return this.destNode;
}

/***********************************************************************
    Character match automata actions.
***********************************************************************/

function RegExpCharMatchTransition (
    destNode,
    charCode
)
{
    this.destNode = destNode;
    this.charCode = charCode;
}

RegExpCharMatchTransition.prototype.exec = function (
    context
)
{
    if (this.charCode === context.currentCharCode)
    {
        context.consume();
        return this.destNode;
    }
    return null;
}

function RegExpCharSetMatchTransition (
    destNode,
    ranges
)
{
    this.destNode = destNode;
    this.ranges = ranges;
}

RegExpCharSetMatchTransition.prototype.exec = function (
    context
)
{
    if (context.endOfInput())
        return null;

    for (var i = 0; i < this.ranges.length; ++i)
    {
        if (context.currentCharCode >= this.ranges[i][0] &&
            context.currentCharCode <= this.ranges[i][1])
        {
            context.consume();
            return this.destNode;
        }
    }
    return null;
}

function RegExpCharExSetMatchTransition (
    destNode,
    ranges
)
{
    this.destNode = destNode;
    this.ranges = ranges;
}

RegExpCharExSetMatchTransition.prototype.exec = function (
    context
)
{
    if (context.endOfInput())
        return null;

    for (var i = 0; i < this.ranges.length; ++i)
    {
        if (context.currentCharCode >= this.ranges[i][0] &&
            context.currentCharCode <= this.ranges[i][1])
        {
            return null;
        }
    }
    context.consume();
    return this.destNode;
}

function RegExpBackRefMatchTransition (
    destNode,
    capture
)
{
    this.destNode = destNode;
    this.capture = capture;
}

RegExpBackRefMatchTransition.prototype.exec = function (
    context
)
{
    if (this.capture.start < 0)
    {
        return this.destNode;
    }

    for (var i = this.capture.start; i < this.capture.end; ++i)
    {
        if (context.endOfInput() ||
            context.currentCharCode !== context.input.charCodeAt(i))
        {
            return null;
        }
        context.consume();
    }

    return this.destNode;
}

/***********************************************************************
    Loop automata actions.
***********************************************************************/

function RegExpLoopOpenTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpLoopOpenTransition.prototype.exec = function (
    context
)
{
    this.destNode.reset();
    this.destNode.baseIndex = context.index;
    context.backtrackStack.push(this.destNode);
    return this.destNode;
}

/***********************************************************************
    Greedy character match loop automata actions.
***********************************************************************/

function RegExpCharMatchLoopNode (
    max,
    loopTransition,
    exitTransition
)
{
    this.max = max;
    this.times = 0;
    this.baseIndex = -1;
    this._final = false;

    this.loopTransition = loopTransition;
    this.exitTransition = exitTransition;

    this.nextTransition = loopTransition;
}

RegExpCharMatchLoopNode.prototype.reset = function ()
{
    this.times = 0;
    this.baseIndex = -1;

    this.nextTransition = this.loopTransition;
}

RegExpCharMatchLoopNode.prototype.step = function (
    context
)
{
    var next = this.nextTransition.exec(context);

    if (next === null &&
        this.nextTransition !== this.exitTransition)
    {
        next = this.exitTransition.exec(context);
    }
    return next;
}

RegExpCharMatchLoopNode.prototype.backtrack = function (
    context
)
{
    if (this.times > 0)
    {
        context.setIndex(this.baseIndex + --(this.times));
        this.nextTransition = this.exitTransition;
        return true;
    }
    context.backtrackStack.pop();
    return false;
}

function RegExpCharMatchLoopTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpCharMatchLoopTransition.prototype.exec = function (
    context
)
{
    if (++(this.destNode.times) >= this.destNode.max &&
        this.destNode.max > 0)
    {
        this.destNode.nextTransition = this.destNode.exitTransition;
    }
    return this.destNode;
}

/***********************************************************************
    Non greedy character match loop automata actions.
***********************************************************************/

function RegExpCharMatchNonGreedyLoopNode (
    max,
    loopTransition,
    exitTransition
)
{
    this.max = max;
    this.times = 0;
    this.baseIndex = -1;
    this._final = false;

    this.loopTransition = loopTransition;
    this.exitTransition = exitTransition;

    this.nextTransition = exitTransition;
}

RegExpCharMatchNonGreedyLoopNode.prototype.reset = function ()
{
    this.times = 0;
    this.baseIndex = -1;

    this.nextTransition = this.exitTransition;
}

RegExpCharMatchNonGreedyLoopNode.prototype.step = function (
    context
)
{
    var next = this.nextTransition.exec(context);

    if (next === null && this.nextTransition !== this.loopTransition)
        next = this.loopTransition.exec(context);
    return next;
}

RegExpCharMatchNonGreedyLoopNode.prototype.backtrack = function (
    context
)
{
    if (this.times < this.max || this.max < 0)
    {
        context.setIndex(this.baseIndex + this.times);
        this.nextTransition = this.loopTransition;
        return true;
    }
    context.backtrackStack.pop();
    return false;
}

function RegExpCharMatchNonGreedyLoopTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpCharMatchNonGreedyLoopTransition.prototype.exec = function (
    context
)
{
    ++(this.destNode.times);
    this.destNode.nextTransition = this.destNode.exitTransition;

    return this.destNode;
}

/***********************************************************************
    Greedy group loop automata actions.
***********************************************************************/

function RegExpGroupLoopNode (
    max,
    loopTransition,
    exitTransition
)
{
    this.max = max;
    this.times = 0;
    this._final = false;
    this.contextIndex = -1;

    this.loopTransition = loopTransition;
    this.exitTransition = exitTransition;

    this.nextTransition = loopTransition;
}

RegExpGroupLoopNode.prototype.reset = function ()
{
    this.times = 0;
    this.nextTransition = this.loopTransition;
}

RegExpGroupLoopNode.prototype.step = function (
    context
)
{
    if (this.nextTransition === this.loopTransition)
        ++this.times;

    return this.nextTransition.exec(context);
}

RegExpGroupLoopNode.prototype.backtrack = function (
    context
)
{
    context.backtrackStack.pop();

    if (this.times > 0)
    {
        --(this.times);
        this.nextTransition = this.exitTransition;
        return true;
    }
    return false;
}

function RegExpGroupLoopOpenTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpGroupLoopOpenTransition.prototype.exec = function (
    context
)
{
    context.backtrackStack.push(this.destNode);
    this.destNode.reset();
    return this.destNode;
}

function RegExpGroupLoopTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpGroupLoopTransition.prototype.exec = function (
    context
)
{
    if (this.destNode.contextIndex === context.index)
        return null;

    if (this.destNode.times >= this.destNode.max && this.destNode.max > 0)
    {
        this.destNode.nextTransition = this.destNode.exitTransition;
    }
    else
    {
        context.backtrackStack.push(this.destNode);
        this.destNode.contextIndex = context.index;
    }

    return this.destNode;
}

/***********************************************************************
    Non greedy group loop automata actions.
***********************************************************************/

function RegExpGroupNonGreedyLoopNode (
    max,
    loopTransition,
    exitTransition
)
{
    this.max = max;
    this.times = 0;
    this._final = false;
    this.contextIndex = -1;

    this.loopTransition = loopTransition;
    this.exitTransition = exitTransition;

    this.nextTransition = exitTransition;
}

RegExpGroupNonGreedyLoopNode.prototype.reset = function ()
{
    this.times = 0;
    this.nextTransition = this.exitTransition;
}

RegExpGroupNonGreedyLoopNode.prototype.step = function (
    context
)
{
    if (this.nextTransition === this.loopTransition)
        ++this.times;

    return this.nextTransition.exec(context);
}

RegExpGroupNonGreedyLoopNode.prototype.backtrack = function (
    context
)
{
    context.backtrackStack.pop();

    if (this.times > 0)
    {
        --(this.times);
        this.nextTransition = this.loopTransition;
        return true;
    }
    return false;
}

function RegExpGroupNonGreedyLoopTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpGroupNonGreedyLoopTransition.prototype.exec = function (
    context
)
{
    if (this.destNode.contextIndex === context.index)
        return null;

    if (this.destNode.times >= this.destNode.max && this.destNode.max > 0)
        this.destNode.nextTransition = this.destNode.exitTransition;

    context.backtrackStack.push(this.destNode);

    this.destNode.contextIndex = context.index;

    return this.destNode;
}

/***********************************************************************
    Greedy backreference loop automata actions.
***********************************************************************/

function RegExpBackRefLoopNode (
    max,
    loopTransition,
    exitTransition
)
{
    this.max = max;
    this.times = 0;
    this._final = false;
    this.indexBacktrackStack = [];

    this.loopTransition = loopTransition;
    this.exitTransition = exitTransition;

    this.nextTransition = loopTransition;
}

RegExpBackRefLoopNode.prototype.reset = function ()
{
    this.times = 0;
    this.nextTransition = this.loopTransition;
}

RegExpBackRefLoopNode.prototype.step = function (
    context
)
{
    this.indexBacktrackStack.push(context.index);

    if (this.nextTransition === this.loopTransition)
        ++this.times;

    return this.nextTransition.exec(context);
}

RegExpBackRefLoopNode.prototype.backtrack = function (
    context
)
{
    context.setIndex(this.indexBacktrackStack.pop());

    if (this.times > 0)
    {
        --(this.times);
        this.nextTransition = this.exitTransition;
        return true;
    }

    context.backtrackStack.pop();
    return false;
}

function RegExpBackRefLoopTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpBackRefLoopTransition.prototype.exec = function (
    context
)
{
    if (this.destNode.indexBacktrackStack[this.destNode.indexBacktrackStack.length - 1] === context.index)
        return null;

    if (this.destNode.times >= this.destNode.max && this.destNode.max > 0)
        this.destNode.nextTransition = this.destNode.exitTransition;

    return this.destNode;
}

function RegExpBackRefLoopOpenTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpBackRefLoopOpenTransition.prototype.exec = function (
    context
)
{
    this.destNode.reset();
    context.backtrackStack.push(this.destNode);
    return this.destNode;
}

/***********************************************************************
    Greedy backreference loop automata actions.
***********************************************************************/

function RegExpBackRefNonGreedyLoopNode (
    max,
    loopTransition,
    exitTransition
)
{
    this.max = max;
    this.times = 0;
    this._final = false;
    this.indexBacktrackStack = [];

    this.loopTransition = loopTransition;
    this.exitTransition = exitTransition;

    this.nextTransition = exitTransition;
}

RegExpBackRefNonGreedyLoopNode.prototype.reset = function ()
{
    this.times = 0;
    this.nextTransition = this.exitTransition;
}

RegExpBackRefNonGreedyLoopNode.prototype.step = function (
    context
)
{
    this.indexBacktrackStack.push(context.index);

    if (this.nextTransition === this.loopTransition)
        ++this.times;

    return this.nextTransition.exec(context);
}

RegExpBackRefNonGreedyLoopNode.prototype.backtrack = function (
    context
)
{
    context.setIndex(this.indexBacktrackStack.pop());

    if (++this.times < max)
    {
        this.nextTransition = this.loopTransition;
        return true;
    }

    context.backtrackStack.pop();
    return false;
}

function RegExpBackRefNonGreedyLoopTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpBackRefNonGreedyLoopTransition.prototype.exec = function (
    context
)
{
    if (this.destNode.indexBacktrackStack[this.destNode.indexBacktrackStack.length - 1] === context.index)
        return null;

    this.destNode.nextTransition = this.destNode.exitTransition;

    return this.destNode;
}

function RegExpBackRefNonGreedyLoopOpenTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpBackRefNonGreedyLoopOpenTransition.prototype.exec = function (
    context
)
{
    this.destNode.reset();
    context.backtrackStack.push(this.destNode);
    return this.destNode;
}

/***********************************************************************
    Basic assertion automata actions.
***********************************************************************/

function RegExpBOLAssertionTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpBOLAssertionTransition.prototype.exec = function (
    context
)
{
    if (context.index === 0)
        return this.destNode;

    return null;
}

function RegExpMultilineBOLAssertionTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpMultilineBOLAssertionTransition.prototype.exec = function (
    context
)
{
    if (context.index === 0)
        return this.destNode;

    if (context.input.charCodeAt(context.index - 1) === 10 ||
        context.input.charCodeAt(context.index - 1) === 13 ||
        context.input.charCodeAt(context.index - 1) === 8232 ||
        context.input.charCodeAt(context.index - 1) === 8233)
    {
        return this.destNode;
    }

    return null;
}

function RegExpEOLAssertionTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpEOLAssertionTransition.prototype.exec = function (
    context
)
{
    if (context.endOfInput())
        return this.destNode;
    return null;
}

function RegExpMultilineEOLAssertionTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpMultilineEOLAssertionTransition.prototype.exec = function (
    context
)
{
    if (context.endOfInput())
        return this.destNode;

    if (context.currentCharCode === 10 || context.currentCharCode === 13 ||
        context.currentCharCode === 8232 || context.currentCharCode === 8233)
    {
        return this.destNode;
    }
    return null;
}

function RegExpWordBoundaryAssertionTransition (
    destNode,
    positive
)
{
    this.destNode = destNode;
    this.positive = positive;
}

RegExpWordBoundaryAssertionTransition.prototype.exec = function (
    context
)
{
    var a = this.isWordChar(context.input.charCodeAt(context.index - 1));
    var b = this.isWordChar(context.currentCharCode);
    if ((a !== b) && this.positive)
        return this.destNode;
    else if ((a === b) && !this.positive)
        return this.destNode;
    return null;
}

RegExpWordBoundaryAssertionTransition.prototype.isWordChar = function (
    charCode
)
{
    return ((charCode >= 97 && charCode <= 122) ||
            (charCode >= 65 && charCode <= 90) ||
            (charCode >= 48 && charCode <= 57) ||
            charCode === 95);
}

/***********************************************************************
    Lookahead automata actions.
***********************************************************************/

function RegExpLookaheadNode (
    group,
    positive,
    lookaheadTransition,
    exitTransition
)
{
    this.contextIndex = -1;
    this.group = group;
    this.positive = positive;
    this.lookaheadTransition = lookaheadTransition;
    this.exitTransition = exitTransition;
    this.reset();
}

RegExpLookaheadNode.prototype.reset = function ()
{
    this.matched = false;
    this.nextTransition = this.lookaheadTransition;
}

RegExpLookaheadNode.prototype.step = function (
    context
)
{
    // Lookahead disjunction match has ended.
    if (this.nextTransition === this.exitTransition)
    {
        // Delete backtracking informations that might have been stored
        // into the lookahead disjunction match as we must not backtrack
        // back into an assertion (15.10.2.8 NOTE 2).
        while (context.getBTNode() !== this)
            context.backtrackStack.pop();

        // Restore context index.
        context.setIndex(this.contextIndex);

        if (this.positive && this.matched || !this.positive && !this.matched)
            return this.exitTransition.exec(context);
        else
            return null;
    }
    // Execute the lookahead disjunction match.
    return this.nextTransition.exec(context);
}

RegExpLookaheadNode.prototype.backtrack = function (
    context
)
{
    // Backtracked from outside the inner lookahead disjunction.
    if (this.nextTransition === this.exitTransition)
    {
        // Clear all captures.
        this.group.clear();

        context.backtrackStack.pop();
        return false;
    }
    // Backtracked while inside the lookahead dijunction (failed to match the assertion).
    else
    {
        this.nextTransition = this.exitTransition;
        return true;
    }
}

function RegExpLookaheadOpenTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpLookaheadOpenTransition.prototype.exec = function (
    context
)
{
    this.destNode.reset();
    this.destNode.contextIndex = context.index;
    context.backtrackStack.push(this.destNode);
    return this.destNode;
}

function RegExpLookaheadMatchTransition (
    destNode
)
{
    this.destNode = destNode;
}

RegExpLookaheadMatchTransition.prototype.exec = function (
    context
)
{
    this.destNode.matched = true;
    this.destNode.nextTransition = this.destNode.exitTransition;
    return this.destNode;
}

/**
    Automata structure.
*/

function RegExpAutomata (
    headNode,
    captures
)
{
    this.headNode = headNode;
    this.captures = captures;
}

function AstToAutomataContext (
    groups,
    global,
    ignoreCase,
    multiline
)
{
    this.groups = groups;
    this.global = global;
    this.ignoreCase = ignoreCase;
    this.multiline = multiline;
}

/**
    Preemptly build group and captures structures from a regexp ast.
    The result is stored into <groups> arguments of type Array.
*/
function buildGroups (
    ast,
    groups,
    parents
)
{
    if (ast instanceof RegExpDisjunction)
    {
        var capture;

        if (ast.captures)
        {
            // Create a new capture object and register it to its parents
            capture = new RegExpCapture();

            for (var i = 0; i < parents.length; ++i)
                parents[i].subcaptures.push(capture);
        }

        // Create a new group object for this disjunction.
        var group = new RegExpGroup(capture);
        parents.push(group);
        groups[ast.groupId] = group;

        // Build groups for each alternatives.
        for (var i = 0; i < ast.alternatives.length; ++i)
            buildGroups(ast.alternatives[i], groups, parents);
        parents.pop();
    }
    else if (ast instanceof RegExpAlternative)
    {
        // Build groups for each terms.
        for (var i = 0; i < ast.terms.length; ++i)
        {
            buildGroups(ast.terms[i], groups, parents);
        }
    }
    else if (ast instanceof RegExpTerm)
    {
        // Call recursively if inner atom or assertion is a dijunction.
        if (ast.prefix.value instanceof RegExpDisjunction)
        {
            buildGroups(ast.prefix.value, groups, parents);
        }
    }
}

/**
    Translate a regexp ast into a regexp automata structure with the given flags.
*/
function astToAutomata (
    ast,
    global,
    ignoreCase,
    multiline
)
{
    var headNode = new RegExpNode();
    var groups = [];
    var context;

    buildGroups(ast, groups, []);

    // Create context with flags.
    context = new AstToAutomataContext(groups, global, ignoreCase, multiline);

    // Set the transition of the head node to the result of the
    // compilation of the root disjunction.
    headNode.transition = disjunctionToAutomata(ast, false, context);

    // Create captures array formed by the capture object of the root group
    // and all its subcaptures.
    var rootGroup = groups[ast.groupId];
    var captures = [ rootGroup.capture ].concat(rootGroup.subcaptures);

    return new RegExpAutomata(headNode, captures);
}

/**
    Compile a RegExpDisjunction ast node to a sub automata.

                 +---------------+
                 |  Alternative  |  3.
                 +---------------+ \
      1.     _                      -->  _   5.
    ------> |_|        ...              |_| ------>
             2.                     -->  4.
                 +---------------+ /
                 |  Alternative  |  3.
                 +---------------+


    1. RegExpGroupOpenTransition
    2. RegExpGroupNode
    3. RegExpGroupCloseTransition
    4. RegExpNode
    5. nextTransition
*/
function disjunctionToAutomata (
    astNode,
    nextTransition,
    context
)
{
    // Get group object from context.
    var group = context.groups[astNode.groupId];

    var openNode = new RegExpGroupNode(group);
    var closeNode = new RegExpNode();

    var openTransition = new RegExpGroupOpenTransition(openNode, group);
    var closeTransition = new RegExpGroupCloseTransition(closeNode, group);

    // Add the result of the compilation of each alternatives to the group node.
    if (astNode.alternatives.length > 0)
        for (var i = 0; i < astNode.alternatives.length; ++i)
            openNode.addAlternative(alternativeToAutomata(astNode.alternatives[i], closeTransition, context));
    else
        // Add directly closeTransition if no alternative to compile.
        openNode.addAlternative(closeTransition);

    // Set close node final if no next transition.
    if (nextTransition)
    {
        closeNode.transition = nextTransition;
    }
    else
    {
        closeNode.transition = new RegExpTransition(null);
        closeNode._final = true;
    }

    return openTransition;
}

/**
    Compile a RegExpAlternative ast node to a sub automata.

    +------+     +------+   1.
    | Term | ... | Term |  ----->
    +------+     +------+

    1. nextTransition
*/
function alternativeToAutomata (
    astNode,
    nextTransition,
    context
)
{
    // Concatenate the result of the compilation of each terms.
    for (var i = astNode.terms.length; i > 0; --i)
        nextTransition = termToAutomata(astNode.terms[i - 1], nextTransition, context);
    return nextTransition;
}

/**
    Compile a RegExpTerm ast node to a sub automata.

    If value is RegExpAtom.

                                        3.
                                    -----------
                                  /             \
                                 |               |
    +------+     +------+   1.   _   +------+   /
    | Atom | ... | Atom | ----> |_|  | Atom | --
    +------+     +------+        2.  +------+
          min times              |
                                  \     4.
                                   ------------>

    1. RegExp(CharMatch|Group|BackRef)LoopOpenTransition
    2. RegExp(CharMatch|Group|BackRef)LoopNode
    3. RegExp(CharMatch|Group|BackRef)LoopTransition
    4. nextTransition

*/
function termToAutomata (
    astNode,
    nextTransition,
    context
)
{
    if (astNode.prefix instanceof RegExpAtom)
    {
        var min = astNode.quantifier.min;
        var max = astNode.quantifier.max;

        if (max < 0 || max > min)
        {
            if (astNode.prefix.value instanceof RegExpPatternCharacter ||
                astNode.prefix.value instanceof RegExpCharacterClass)
            {
                if (astNode.quantifier.greedy)
                {
                    var loopTransition = new RegExpCharMatchLoopTransition();
                    var loopNode = new RegExpCharMatchLoopNode(max - min, atomToAutomata(astNode.prefix, loopTransition, context), nextTransition);
                    loopTransition.destNode = loopNode;
                    nextTransition = new RegExpLoopOpenTransition(loopNode);
                }
                else
                {
                    var loopTransition = new RegExpCharMatchNonGreedyLoopTransition();
                    var loopNode = new RegExpCharMatchNonGreedyLoopNode(max - min, atomToAutomata(astNode.prefix, loopTransition, context), nextTransition);
                    loopTransition.destNode = loopNode;
                    nextTransition = new RegExpLoopOpenTransition(loopNode);
                }
            }
            else if (astNode.prefix.value instanceof RegExpDisjunction)
            {
                if (astNode.quantifier.greedy)
                {
                    var loopTransition = new RegExpGroupLoopTransition();
                    var loopNode = new RegExpGroupLoopNode(max - min, atomToAutomata(astNode.prefix, loopTransition, context), nextTransition);
                    loopTransition.destNode = loopNode;
                    nextTransition = new RegExpGroupLoopOpenTransition(loopNode);
                }
                else
                {
                    var loopTransition = new RegExpGroupNonGreedyLoopTransition();
                    var loopNode = new RegExpGroupNonGreedyLoopNode(max - min, atomToAutomata(astNode.prefix, loopTransition, context), nextTransition);
                    loopTransition.destNode = loopNode;
                    nextTransition = new RegExpGroupNonGreedyLoopOpenTransition(loopNode);
                }
            }
            else if (astNode.prefix.value instanceof RegExpBackReference)
            {
                if (astNode.quantifier.greedy)
                {
                    var loopTransition = new RegExpBackRefLoopTransition();
                    var loopNode = new RegExpBackRefLoopNode(max - min, atomToAutomata(astNode.prefix, loopTransition, context), nextTransition);
                    loopTransition.destNode = loopNode;
                    nextTransition = new RegExpBackRefLoopOpenTransition(loopNode);
                }
                else
                {
                    var loopTransition = new RegExpBackRefNonGreedyLoopTransition();
                    var loopNode = new RegExpBackRefNonGreedyLoopNode(max - min, atomToAutomata(astNode.prefix, loopTransition, context), nextTransition);
                    loopTransition.destNode = loopNode;
                    nextTransition = new RegExpBackRefNonGreedyLoopOpenTransition(loopNode);
                }
            }
        }

        // Concatenate atom <min> times.
        for (var i = 0; i < min; ++i)
            nextTransition = atomToAutomata(astNode.prefix, nextTransition, context);
    }
    else if (astNode.prefix instanceof RegExpAssertion)
    {
        nextTransition = assertionToAutomata(astNode.prefix, nextTransition, context);
    }
    return nextTransition;
}

function getRangeFromCharClass(atomAstNode, context)
{
    var ranges = [];

    for (var i = 0; i < atomAstNode.classAtoms.length; ++i)
    {
        if (context.ignoreCase)
        {
            var ca = atomAstNode.classAtoms[i];

            if (ca.max === undefined)
            {
                if (ca.min.value >= 97 && ca.min.value <= 122)
                {
                    ranges.push([ca.min.value, ca.min.value]);
                    ranges.push([ca.min.value - 32, ca.min.value - 32]);
                }
                else if (ca.min.value >= 65 && ca.min.value <= 90)
                {
                    ranges.push([ca.min.value, ca.min.value]);
                    ranges.push([ca.min.value + 32, ca.min.value + 32]);
                }
                else
                {
                    ranges.push([ca.min.value, ca.min.value]);
                }
            }
            else
            {
                ranges.push(ca.max === undefined ? [ca.min.value, ca.min.value] : [ca.min.value, ca.max.value]);
            }
        }
        else
        {
            var ca = atomAstNode.classAtoms[i];
            if (ca.min instanceof RegExpCharacterClass)
            {
                ranges = ranges.concat(getRangeFromCharClass(ca.min, context));
            }
            else
            {
                ranges.push(ca.max === undefined ? [ca.min.value, ca.min.value] : [ca.min.value, ca.max.value]);
            }
        }
    }
    return ranges;
}

/**
    Compile a RegExpTerm ast node to a sub automata.
*/
function atomToAutomata (
    astNode,
    nextTransition,
    context
)
{
    var node = new RegExpNode();
    var atomAstNode = astNode.value;

    node.transition = nextTransition;

    /**
        RegExpPatternCharacter

          1.    _   3.
        -----> |_| ---->
                2.

        1. RegExpCharMatchTransition
        2. RegExpNode
        3. nextTransition
    */
    if (atomAstNode instanceof RegExpPatternCharacter)
    {
        var charCode = atomAstNode.value;

        if (context.ignoreCase)
            if (charCode >= 97 && charCode <= 122) // a-z
                nextTransition = new RegExpCharSetMatchTransition(node, [[charCode - 32, charCode - 32], [charCode, charCode]]);
            else if (charCode >= 65 && charCode <= 90) // A-Z
                nextTransition = new RegExpCharSetMatchTransition(node, [[charCode + 32, charCode + 32], [charCode, charCode]]);
            else
                nextTransition = new RegExpCharMatchTransition(node, charCode);
        else
            nextTransition = new RegExpCharMatchTransition(node, charCode);
    }
    /**
        RegExpCharacterClass

          1.    _   3.
        -----> |_| ---->
                2.

        1. (RegExpCharSetMatchTransition|RegExpExCharSetMatchTransition)
        2. RegExpNode
        3. nextTransition
    */
    else if (atomAstNode instanceof RegExpCharacterClass)
    {

        var ranges = getRangeFromCharClass(atomAstNode, context);
        if (atomAstNode.positive)
            nextTransition  = new RegExpCharSetMatchTransition(node, ranges);
        else
            nextTransition = new RegExpCharExSetMatchTransition(node, ranges);
    }
    /**
        RegExpBackReference

          1.    _   3.
        -----> |_| ---->
                2.

        1. RegExpBackRefMatchTransition
        2. RegExpNode
        3. nextTransition
    */
    else if (atomAstNode instanceof RegExpBackReference)
    {
        var rootGroup = context.groups[0];
        nextTransition = new RegExpBackRefMatchTransition(node, rootGroup.subcaptures[atomAstNode.index - 1]);
    }
    else if (atomAstNode instanceof RegExpDisjunction)
    {
        nextTransition = disjunctionToAutomata(atomAstNode, nextTransition, context);
    }

    return nextTransition;
}

function assertionToAutomata (
    astNode,
    nextTransition,
    context
)
{
    if (astNode.value instanceof RegExpDisjunction)
    {
        var group = context.groups[astNode.value.groupId];
        var exitTransition = new RegExpLookaheadMatchTransition();
        var node = new RegExpLookaheadNode(group, astNode.positive, disjunctionToAutomata(astNode.value, exitTransition, context), nextTransition);
        exitTransition.destNode = node;
        nextTransition = new RegExpLookaheadOpenTransition(node);
    }
    else
    {
        var node = new RegExpNode();
        node.transition = nextTransition;

        if (astNode.value === 94) // '^'
        {
            if (context.multiline)
                nextTransition = new RegExpMultilineBOLAssertionTransition(node);
            else
                nextTransition = new RegExpBOLAssertionTransition(node);
        }
        else if (astNode.value === 36) // '$'
        {
            if (context.multiline)
                nextTransition = new RegExpMultilineEOLAssertionTransition(node);
            else
                nextTransition = new RegExpEOLAssertionTransition(node);
        }
        else if (astNode.value === 98) // 'b' | 'B'
        {
            nextTransition = new RegExpWordBoundaryAssertionTransition(node, astNode.positive);
        }
    }
    return nextTransition;
}

RegExp.prototype.toString = function ()
{
    return this.source;
}

/**
    15.10.6.2 RegExp.prototype.exec(string)
*/
RegExp.prototype.exec = function (
    input
)
{
    var context = new RegExpContext(input, this._automata.captures);
    var padding = 0;
    var currentNode = this._automata.headNode;
    var nextNode = currentNode;

    do {
        currentNode = this._automata.headNode;
        context.setIndex(this.lastIndex + padding);

        while (true)
        {
            nextNode = currentNode.step(context);

            // No next step
            if (nextNode === null)
            {
                // Return the match if the current node is final.
                if (currentNode._final)
                {
                    // Update last index propertie if global.
                    if (this.global)
                        this.lastIndex = context.index;

                    // Build match array.
                    var matches = new Array(this._automata.captures.length);
                    for (var i = 0; i < this._automata.captures.length; ++i)
                    {
                        var capture = this._automata.captures[i];

                        if (capture.start >= 0)
                            matches[i] = input.substring(capture.start, capture.end);
                        else
                            matches[i] = undefined;
                    }
                    return matches;
                }

                // Backtrack context until a backtrack succeded or backtrack stack is empty.
                do {
                    nextNode = context.getBTNode();
                } while (nextNode && !nextNode.backtrack(context));

                // If backtracking failed, try again with the input padded one character.
                if (!nextNode)
                {
                    ++padding;
                    break;
                }
            }

            currentNode = nextNode;
        }
    } while (this.lastIndex + padding < input.length);

    this.lastIndex = 0;
    return null;
}

RegExp.prototype.test = function (
    input
)
{
    var context = new RegExpContext(input, this._automata.captures);
    var padding = 0;
    var currentNode = this._automata.headNode;
    var nextNode = currentNode;

    do
    {
        currentNode = this._automata.headNode;
        context.setIndex(this.lastIndex + padding);
        while (true)
        {
            nextNode = currentNode.step(context);
            if (nextNode === null)
            {
                if (currentNode._final)
                {
                    if (this.global)
                        this.lastIndex = context.index;
                    return true;
                }

                // Backtrack context until a backtrack succeded or backtrack stack is empty.
                do {
                    nextNode = context.getBTNode();
                } while (nextNode && !nextNode.backtrack(context));

                if (!nextNode)
                {
                    ++padding;
                    break;
                }
            }

            currentNode = nextNode;
        }
    } while (this.lastIndex + padding < input.length);

    this.lastIndex = 0;
    return false;
}

/// Export the RegExp constructor
this.RegExp = RegExp;

})();

/**
Private name for the RegExp class
The global RegExp name may be redefined
*/
$ir_obj_def_const(this, '$rt_RegExp', RegExp, false);

/*
Runtime function to get a regular expresson object
*/
function $rt_getRegExp(pattern, flags)
{
    return new $rt_RegExp(pattern, flags);
}
