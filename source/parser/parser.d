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

module parser.parser;

import std.stdio;
import std.file;
import std.utf;
import std.array;
import std.conv;
import std.regex;
import parser.lexer;
import parser.ast;
import parser.vars;

/**
Parsing error exception
*/
class ParseError : Error
{
    /// Source position
    SrcPos pos;

    this(string msg, SrcPos pos)
    {
        assert (pos !is null, "source position is null");

        super(msg);
        this.pos = pos;
    }

    override string toString()
    {
        return pos.toString() ~ ": " ~ this.msg;
    }
}

/**
Read and consume a separator token. A parse error
is thrown if the separator is missing.
*/
void readSep(TokenStream input, wstring sep)
{
    if (input.matchSep(sep) == false)
    {
        throw new ParseError(
            "expected \"" ~ to!string(sep) ~ "\" separator",
            input.getPos()
        );
    }
}

/**
Read and consume a keyword token. A parse error
is thrown if the keyword is missing.
*/
void readKw(TokenStream input, wstring keyword)
{
    if (input.matchKw(keyword) == false)
    {
        throw new ParseError(
            "expected \"" ~ to!string(keyword) ~ "\" keyword",
            input.getPos()
        );
    }
}

/**
Test if a semicolon is present or one could be automatically inserted
at the current position
*/
bool peekSemiAuto(TokenStream input)
{
    return (
        input.peekSep(";") == true ||
        input.peekSep("}") == true ||
        input.newline() == true ||
        input.eof() == true
    );
}

/**
Read and consume a semicolon or an automatically inserted semicolon
*/
void readSemiAuto(TokenStream input)
{
    if (input.matchSep(";") == false && peekSemiAuto(input) == false)
    {
        throw new ParseError(
            "expected semicolon or end of statement",
            input.getPos()
        );
    }
}

/**
Read an identifier token from the input
*/
IdentExpr readIdent(TokenStream input)
{
    auto t = input.read();

    if (t.type != Token.IDENT)
        throw new ParseError("expected identifier", t.pos);

    return new IdentExpr(t.stringVal, t.pos);
}

/**
Parse a source file
*/
ASTProgram parseFile(string fileName, bool isRuntime = false)
{
    string src = readText!(string)(fileName);
    return parseString(src, fileName, isRuntime);
}

/**
Parse a source string
*/
ASTProgram parseString(string src, string fileName = "", bool isRuntime = false)
{
    // Convert the string to UTF-16
    wstring wSrc = toUTF16(src);

    auto input = new TokenStream(wSrc, fileName);

    return parseProgram(input, isRuntime);
}

/**
Parse a top-level program node
*/
ASTProgram parseProgram(TokenStream input, bool isRuntime)
{
    SrcPos pos = input.getPos();

    auto stmtApp = appender!(ASTStmt[])();

    while (input.eof() == false)
    {
        ASTStmt stmt = parseStmt(input);
        stmtApp.put(stmt);
    }

    // Create the AST program node
    auto ast = new ASTProgram(stmtApp.data, pos, isRuntime);

    // Transform single expression statements into return statements
    void makeReturn(ASTStmt stmt)
    {
        auto blockStmt = cast(BlockStmt)ast.bodyStmt;
        if (blockStmt is null || blockStmt.stmts.length == 0)
            return;

        auto exprStmt = cast(ExprStmt)blockStmt.stmts[$-1];
        if (exprStmt is null)
            return;

        // If this is a named function, don't transform
        auto funExpr = cast(FunExpr)exprStmt.expr;
        if (funExpr && funExpr.name !is null)
            return;

        blockStmt.stmts[$-1] = new ReturnStmt(
            exprStmt.expr,
            exprStmt.pos
        );
    }

    // If the AST contains only an expression statement,
    // turn it into a return statement
    makeReturn(ast.bodyStmt);

    // Resolve variable declarations in the AST
    resolveVars(ast);

    return ast;
}

/**
Parse a statement
*/
ASTStmt parseStmt(TokenStream input)
{
    //writeln("parseStmt");

    /// Test if this is a label statement and backtrack
    bool isLabel(TokenStream input)
    {
        // Copy the starting input to allow backtracking
        auto startInput = new TokenStream(input);

        // On return, backtrack to the start
        scope(exit)
            input.backtrack(startInput);

        auto t = input.peek();
        if (t.type != Token.IDENT)
            return false;
        input.read();

        return input.matchSep(":");
    }

    // Get the current source position
    SrcPos pos = input.getPos();

    // Empty statement
    if (input.matchSep(";"))
    {
        return new ExprStmt(new TrueExpr(pos), pos);
    }

    // Block statement
    else if (input.matchSep("{"))
    {
        ASTStmt[] stmts;

        for (;;)
        {
            if (input.matchSep("}"))
                break;

            if (input.eof())
            {
                throw new ParseError(
                    "end of input in block statement",
                    input.getPos()
                );
            }

            stmts ~= [parseStmt(input)]; 
        }

        return new BlockStmt(stmts, pos);
    }

    // If statement
    else if (input.matchKw("if"))
    {
        input.readSep("(");
        ASTExpr testExpr = parseExpr(input);
        input.readSep(")");

        auto trueStmt = parseStmt(input);

        ASTStmt falseStmt;
        if (input.matchKw("else"))
            falseStmt = parseStmt(input);
        else
            falseStmt = new ExprStmt(new TrueExpr());

        return new IfStmt(testExpr, trueStmt, falseStmt, pos);
    }

    // While loop
    else if (input.matchKw("while"))
    {
        input.readSep("(");
        auto testExpr = parseExpr(input);
        input.readSep(")");
        auto bodyStmt = parseStmt(input);

        return new WhileStmt(testExpr, bodyStmt, pos);
    }

    // Do-while loop
    else if (input.matchKw("do"))
    {
        auto bodyStmt = parseStmt(input);
        if (input.matchKw("while") == false)
            throw new ParseError("expected while", input.getPos());
        input.readSep("(");
        auto testExpr = parseExpr(input);
        input.readSep(")");

        return new DoWhileStmt(bodyStmt, testExpr, pos);
    }

    // For or for-in loop
    else if (input.peekKw("for"))
    {
        return parseForStmt(input);
    }

    // Switch statement
    else if (input.matchKw("switch"))
    {
        input.readSep("(");
        auto switchExpr = parseExpr(input);
        input.readSep(")");
        input.readSep("{");

        ASTExpr[] caseExprs = [];
        ASTStmt[][] caseStmts = [];

        bool defaultSeen = false;
        ASTStmt[] defaultStmts = [];

        ASTStmt[]* curStmts = null;

        // For each case
        for (;;)
        {
            if (input.matchSep("}"))
            {
                break;
            }

            else if (input.matchKw("case"))
            {
                caseExprs ~= [parseExpr(input)];
                input.readSep(":");

                caseStmts ~= [[]];
                curStmts = &caseStmts[caseStmts.length-1];
            }

            else if (input.matchKw("default"))
            {
                input.readSep(":");
                if (defaultSeen is true)
                    throw new ParseError("duplicate default label", input.getPos());

                defaultSeen = true;
                curStmts = &defaultStmts;
            }

            else
            {
                if (curStmts is null)
                    throw new ParseError("statement before label", input.getPos());

                (*curStmts).assumeSafeAppend() ~= parseStmt(input);
            }
        }

        return new SwitchStmt(
            switchExpr, 
            caseExprs,
            caseStmts,
            defaultStmts,
            pos
        );
    }

    // Break statement
    else if (input.matchKw("break"))
    {
        auto label = input.peekSemiAuto()? null:input.readIdent();
        readSemiAuto(input);
        return new BreakStmt(label, pos);
    }

    // Continue statement
    else if (input.matchKw("continue"))
    {
        auto label = input.peekSemiAuto()? null:input.readIdent();
        readSemiAuto(input);
        return new ContStmt(label, pos);
    }

    // Return statement
    else if (input.matchKw("return"))
    {
        if (input.matchSep(";") || input.peekSemiAuto())
            return new ReturnStmt(null, pos);

        ASTExpr expr = parseExpr(input);
        readSemiAuto(input);
        return new ReturnStmt(expr, pos);
    }

    // Throw statement
    else if (input.matchKw("throw"))
    {
        ASTExpr expr = parseExpr(input);
        readSemiAuto(input);
        return new ThrowStmt(expr, pos);
    }

    // Try-catch-finally statement
    else if (input.matchKw("try"))
    {
        auto tryStmt = parseStmt(input);

        IdentExpr catchIdent = null;
        ASTStmt catchStmt = null;
        if (input.matchKw("catch"))
        {
            input.readSep("(");
            catchIdent = cast(IdentExpr)parseExpr(input);
            if (catchIdent is null)
                throw new ParseError("invalid catch identifier", catchIdent.pos);
            input.readSep(")");
            catchStmt = parseStmt(input);
        }

        ASTStmt finallyStmt = null;
        if (input.matchKw("finally"))
        {
            finallyStmt = parseStmt(input);
        }

        if (!catchStmt && !finallyStmt)
            throw new ParseError("no catch or finally block", input.getPos());

        return new TryStmt(
            tryStmt, 
            catchIdent, 
            catchStmt,
            finallyStmt
        );
    }

    // Variable declaration/initialization statement
    else if (input.matchKw("var"))
    {
        IdentExpr[] identExprs = [];
        ASTExpr[] initExprs = [];

        // For each declaration
        for (;;)
        {
            // If this is not the first declaration and there is no comma
            if (identExprs.length > 0 && input.matchSep(",") == false)
            {
                readSemiAuto(input);
                break;
            }

            auto name = input.read();
            if (name.type != Token.IDENT)
            {
                throw new ParseError(
                    "expected identifier in variable declaration",
                    name.pos
                );
            }
            IdentExpr identExpr = new IdentExpr(name.stringVal, name.pos);

            ASTExpr initExpr = null;
            auto op = input.peek();

            if (op.type == Token.OP && op.stringVal == "=")
            {
                input.read(); 
                initExpr = parseExpr(input, COMMA_PREC+1);
            }

            // If this is an assignment of an unnamed function to 
            // a variable, assign the function a name
            if (auto funExpr = cast(FunExpr)initExpr)
            {
                if (funExpr.name is null)
                    funExpr.name = identExpr;
            }

            identExprs ~= [identExpr];
            initExprs ~= [initExpr];
        }

        return new VarStmt(identExprs, initExprs, pos);
    }

    // Function declaration statement
    else if (input.peekKw("function"))
    {
        auto funExpr = parseAtom(input);

        // Weed out trailing semicolons
        if (input.peekSep(";"))
            input.read();

        return new ExprStmt(funExpr, pos);
    }

    // If this is a labelled statement
    else if (isLabel(input))
    {
        auto label = cast(IdentExpr)parseAtom(input);
        input.readSep(":");
        auto stmt = parseStmt(input);
        stmt.labels ~= label;

        return stmt;
    }

    // Peek at the token at the start of the expression
    auto startTok = input.peek();

    // Parse as an expression statement
    ASTExpr expr = parseExpr(input);

    // Peek at the token after the expression
    auto endTok = input.peek();

    // If the statement is empty
    if (endTok == startTok)
    {
        throw new ParseError(
            "empty statements must be terminated by semicolons",
            endTok.pos
        );
    }

    // Read the terminating semicolon
    readSemiAuto(input);

    return new ExprStmt(expr, pos);
}

/**
Parse a for or for-in loop statement
*/
ASTStmt parseForStmt(TokenStream input)
{
    /// Test if this is a for-in statement and backtrack
    bool isForIn(TokenStream input)
    {
        // Copy the starting input to allow backtracking
        auto startInput = new TokenStream(input);

        // On return, backtrack to the start
        scope(exit)
            input.backtrack(startInput);

        // Test if there is a variable declaration
        auto hasDecl = input.matchKw("var");

        if (input.peekSep(";"))
            return false;

        // Parse the first expression, stop at comma if there is a declaration
        auto firstExpr = parseExpr(input, hasDecl? (COMMA_PREC+1):COMMA_PREC);

        if (input.peekSep(";"))
            return false;

        if (auto binExpr = cast(BinOpExpr)firstExpr)
            if (binExpr.op.str == "in")
                return true;

        return false;
    }

    // Get the current position
    auto pos = input.getPos();

    // Read the for keyword and the opening parenthesis
    input.readKw("for");
    input.readSep("(");

    // If this is a regular for-loop statement
    if (isForIn(input) == false)
    {
        // Parse the init statement
        auto initStmt = parseStmt(input);
        if (cast(VarStmt)initStmt is null && cast(ExprStmt)initStmt is null)
            throw new ParseError("invalid for-loop init statement", initStmt.pos);

        // Parse the test expression
        pos = input.getPos();
        ASTExpr testExpr;
        if (input.matchSep(";"))
        {
            testExpr = new TrueExpr(pos);
        }
        else
        {
            testExpr = parseExpr(input);
            input.readSep(";");
        }

        // Parse the inccrement expression
        pos = input.getPos();
        ASTExpr incrExpr;
        if (input.matchSep(")"))
        {
            incrExpr = new TrueExpr(pos);
        }
        else
        {
            incrExpr = parseExpr(input);
            input.readSep(")");
        }

        // Parse the loop body
        auto bodyStmt = parseStmt(input);

        return new ForStmt(initStmt, testExpr, incrExpr, bodyStmt, pos);
    }

    // This is a for-in statement
    else
    {
        auto hasDecl = input.matchKw("var");
        auto varExpr = parseExpr(input, IN_PREC+1);
        if (hasDecl && cast(IdentExpr)varExpr is null)
            throw new ParseError("invalid variable expression in for-in loop", pos);

        auto inTok = input.peek();
        if (inTok.type != Token.OP || inTok.stringVal != "in")
            throw new ParseError("expected \"in\" keyword", input.getPos());
        input.read();

        auto inExpr = parseExpr(input);

        input.readSep(")");

        // Parse the loop body
        auto bodyStmt = parseStmt(input);

        return new ForInStmt(hasDecl, varExpr, inExpr, bodyStmt, pos);
    }
}

/**
Parse an expression
*/
ASTExpr parseExpr(TokenStream input, int minPrec = 0)
{
    // Expression parsing using the precedence climbing algorithm
    //    
    // The first call has min precedence 0
    //
    // Each call loops to grab everything of the current precedence or
    // greater and builds a left-sided subtree out of it, associating
    // operators to their left operand
    //
    // If an operator has less than the current precedence, the loop
    // breaks, returning us to the previous loop level, this will attach
    // the atom to the previous operator (on the right)
    //
    // If an operator has the mininum precedence or greater, it will
    // associate the current atom to its left and then parse the rhs

    //writeln("parseExpr");

    // Parse the first atom
    ASTExpr lhsExpr = parseAtom(input);

    for (;;)
    {
        // Peek at the current token
        Token cur = input.peek();

        // If the token is not an operator or separator, break out
        if (cur.type != Token.OP && cur.type != Token.SEP)
            break;

        //writefln("op str: %s", cur.stringVal);

        // Attempt to find a corresponding operator
        auto op = findOperator(cur.stringVal, 2);
        if (op is null)
            op = findOperator(cur.stringVal, 1, 'l');
        if (op is null && cur.stringVal == "?")
            op = findOperator(cur.stringVal, 3);

        // If no operator matches, break out
        if (op is null)
            break;

        // If the new operator has lower precedence, break out
        if (op.prec < minPrec)
            break;

        //writefln("binary op: %s", cur.stringVal);

        // Compute the minimal precedence for the recursive call (if any)
        int nextMinPrec = (op.assoc == 'l')? (op.prec + 1):op.prec;

        // If this is a function call expression
        if (cur.stringVal == "(")
        {
            // Parse the argument list and create the call expression
            auto argExprs = parseExprList(input, "(", ")");
            lhsExpr = new CallExpr(lhsExpr, argExprs, lhsExpr.pos);
        }

        // If this is an array indexing expression
        else if (input.matchSep("["))
        {
            auto indexExpr = parseExpr(input);
            input.readSep("]");
            lhsExpr = new IndexExpr(lhsExpr, indexExpr, lhsExpr.pos);
        }

        // If this is a member expression
        else if (op.str == ".")
        {
            input.read();

            // Parse the identifier string
            auto tok = input.read();
            if (!(tok.type is Token.IDENT) &&
                !(tok.type is Token.KEYWORD) &&
                !(tok.type is Token.OP && ident(tok.stringVal)))
            {
                throw new ParseError(
                    "invalid member identifier \"" ~ tok.toString() ~ "\"", 
                    tok.pos
                );
            }
            auto stringExpr = new StringExpr(tok.stringVal, tok.pos);

            // Produce an indexing expression
            lhsExpr = new IndexExpr(lhsExpr, stringExpr, lhsExpr.pos);
        }

        // If this is the ternary conditional operator
        else if (cur.stringVal == "?")
        {
            // Consume the current token
            input.read();

            auto trueExpr = parseExpr(input);
            input.readSep(":");
            auto falseExpr = parseExpr(input, op.prec-1);

            lhsExpr = new CondExpr(lhsExpr, trueExpr, falseExpr, lhsExpr.pos);
        }

        // If this is a binary operator
        else if (op.arity == 2)
        {
            // Consume the current token
            input.read();

            // Recursively parse the rhs
            ASTExpr rhsExpr = parseExpr(input, nextMinPrec);

            // Convert expressions of the form "x <op>= y" to "x = x <op> y"
            auto eqOp = findOperator("=", 2, 'r');
            if (op.str.length >= 2 && op.str.back == '=' && op.prec == eqOp.prec)
            {
                auto rhsOp = findOperator(op.str[0..op.str.length-1], 2);
                assert (rhsOp !is null);
                rhsExpr = new BinOpExpr(rhsOp, lhsExpr, rhsExpr, rhsExpr.pos);
                op = eqOp;
            }

            // If this is an assignment of a function to something,
            // try to assign the function a name
            if (auto funExpr = cast(FunExpr)rhsExpr)
            {
                if (op.str == "=" && funExpr.name is null)
                {
                    wstring nameStr;

                    for (auto curExpr = lhsExpr; curExpr !is null;)
                    {
                        wstring subStr;

                        if (auto idxExpr = cast(IndexExpr)curExpr)
                        {
                            if (auto strExpr = cast(StringExpr)idxExpr.index)
                                subStr = strExpr.val;
                            curExpr = idxExpr.base;
                        }
                        else if (auto identExpr = cast(IdentExpr)curExpr)
                        {
                            subStr = identExpr.name;
                            curExpr = null;
                        }
                        else
                        {
                            nameStr = ""w;
                            break;
                        }

                        nameStr = subStr ~ (nameStr? "_"w:"") ~ nameStr;
                    }

                    if (nameStr)
                        funExpr.name = new IdentExpr(nameStr, funExpr.pos);
                }
            }

            // Update lhs with the new value
            lhsExpr = new BinOpExpr(op, lhsExpr, rhsExpr, lhsExpr.pos);
        }

        // If this is a unary operator
        else if (op.arity == 1)
        {
            // Consume the current token
            input.read();

            // Update lhs with the new value
            lhsExpr = new UnOpExpr(op, lhsExpr, lhsExpr.pos);
        }

        else
        {
            assert (false, "unhandled operator");
        }
    }

    //writeln("leaving parseExpr");

    // Return the parsed expression
    return lhsExpr;
}

/**
Parse an atomic expression
*/
ASTExpr parseAtom(TokenStream input)
{
    //writeln("parseAtom");

    Token t = input.peek(LEX_MAYBE_RE);
    SrcPos pos = t.pos;

    // End of file
    if (input.eof())
    {
        throw new ParseError("end of input inside expression", pos);
    }

    // Parenthesized expression
    else if (input.matchSep("("))
    {
        ASTExpr expr = parseExpr(input);
        input.readSep(")");
        return expr;
    }

    // Array literal
    else if (t.type == Token.SEP && t.stringVal == "[")
    {
        auto exprs = parseExprList(input, "[", "]");
        return new ArrayExpr(exprs, pos);
    }

    // Object literal
    else if (input.matchSep("{"))
    {
        StringExpr[] names = [];
        ASTExpr[] values = [];

        for (;;)
        {
            if (input.matchSep("}"))
                break;

            if (values.length > 0 && input.matchSep(",") == false)
                throw new ParseError("expected comma", input.getPos());

            auto tok = input.read();
            StringExpr stringExpr = null;
            if (tok.type is Token.IDENT ||
                tok.type is Token.KEYWORD ||
                tok.type is Token.STRING)
                stringExpr = new StringExpr(tok.stringVal, tok.pos);
            if (tok.type is Token.OP && ident(tok.stringVal))
                stringExpr = new StringExpr(tok.stringVal, tok.pos);
            else if (tok.type is Token.INT)
                stringExpr = new StringExpr(to!wstring(tok.intVal), tok.pos);

            if (!stringExpr)
                throw new ParseError("invalid property name", tok.pos);
            names ~= [stringExpr];

            input.readSep(":");

            // Parse an expression with priority above the comma operator
            auto valueExpr = parseExpr(input, COMMA_PREC+1);
            values ~= [valueExpr];
        }

        return new ObjectExpr(names, values, pos);
    }

    // Regular expression literal
    else if (t.type == Token.REGEXP)
    {
        input.read();
        return new RegexpExpr(t.regexpVal, t.flagsVal, pos);
    }

    // New expression
    else if (t.type == Token.OP && t.stringVal == "new")
    {
        // Consume the "new" token
        input.read();

        // Parse the base expression
        auto op = findOperator(t.stringVal, 1, 'r');
        auto baseExpr = parseExpr(input, op.prec);

        // Parse the argument list (if present, otherwise assumed empty)
        auto argExprs = input.peekSep("(")? parseExprList(input, "(", ")"):[];

        // Create the new expression
        return new NewExpr(baseExpr, argExprs, t.pos);
    }

    // Function expression
    // function (params) body
    else if (input.matchKw("function"))
    {
        auto nextTok = input.peek();
        auto nameExpr = (nextTok.type != Token.SEP)? parseAtom(input):null;
        auto funcName = cast(IdentExpr)nameExpr;
        if (nameExpr && !funcName)
            throw new ParseError("invalid function name", nameExpr.pos);

        auto params = parseParamList(input);

        auto bodyStmt = parseStmt(input);

        return new FunExpr(funcName, params, bodyStmt, pos);
    }

    // Identifier/symbol literal
    else if (t.type == Token.IDENT)
    {
        input.read();
        return new IdentExpr(t.stringVal, pos);
    }

    // Integer literal
    else if (t.type == Token.INT)
    {
        input.read();
        return new IntExpr(t.intVal, pos);
    }

    // Floating-point literal
    else if (t.type == Token.FLOAT)
    {
        input.read();
        return new FloatExpr(t.floatVal, pos);
    }

    // String literal
    else if (t.type == Token.STRING)
    {
        input.read();
        return new StringExpr(t.stringVal, pos);
    }

    // True boolean constant
    else if (input.matchKw("true"))
    {
        return new TrueExpr(pos);
    }

    // False boolean constant
    else if (input.matchKw("false"))
    {
        return new FalseExpr(pos);
    }

    // Null constant
    else if (input.matchKw("null"))
    {
        return new NullExpr(pos);
    }

    // Unary expressions
    else if (t.type == Token.OP)
    {
        //writefln("unary op: %s", t.stringVal);

        auto op = findOperator(t.stringVal, 1, 'r');
        if (!op)
        {
            throw new ParseError(
                "invalid unary operator \"" ~ to!string(t.stringVal) ~ "\"", 
                pos
            );
        }

        // Consume the operator
        input.read();

        // Parse the right subexpression
        ASTExpr expr = parseExpr(input, op.prec);

        // If this is a negated integer
        if (op.str == "-"w)
        {
            if (auto intExpr = cast(IntExpr)expr)
            {
                // Negative zero cannot be represented as integer
                if (intExpr.val is 0)
                    return new FloatExpr(-0.0, intExpr.pos);

                // Negate the integer value
                return new IntExpr(-intExpr.val, intExpr.pos);
            }
        }

        // Return the unary expression
        return new UnOpExpr(op, expr, pos);
    }

    throw new ParseError("unexpected token: " ~ t.toString(), pos);
}

/**
Parse a list of expressions
*/
ASTExpr[] parseExprList(TokenStream input, wstring openSep, wstring closeSep)
{
    input.readSep(openSep);

    ASTExpr[] exprs;

    for (;;)
    {
        if (input.matchSep(closeSep))
            break;

        // If this is not the first element and there
        // is no comma separator, throw an error
        if (exprs.length > 0 && input.matchSep(",") == false)
            throw new ParseError("expected comma", input.getPos());

        // Handle missing array element syntax
        if (openSep == "[")
        {
            if (input.matchSep(closeSep))
                break;

            if (input.peekSep(",")) 
            {
                exprs ~= new IdentExpr("undefined", input.getPos());
                continue;
            }
        }

        // Parse the current element
        exprs ~= parseExpr(input, COMMA_PREC+1);
    }

    return exprs;
}

/**
Parse a function declaration's parameter list
*/
IdentExpr[] parseParamList(TokenStream input)
{
    input.readSep("(");

    IdentExpr[] exprs;

    for (;;)
    {
        if (input.matchSep(")"))
            break;

        if (exprs.length > 0 && input.matchSep(",") == false)
            throw new ParseError("expected comma", input.getPos());

        auto expr = parseAtom(input);
        auto ident = cast(IdentExpr)expr;
        if (ident is null)
            throw new ParseError("invalid parameter", expr.pos);

        exprs ~= ident;
    }

    return exprs;
}

