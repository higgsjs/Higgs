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

module parser.parser;

import std.stdio;
import std.file;
import std.utf;
import std.array;
import std.conv;
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
        super(msg);

        this.pos = pos;
    }

    string toString()
    {
        return pos.toString() ~ ": " ~ this.msg;
    }
}

/**
Read and consume a separator token. A parse error
is thrown is the separator is missing.
*/
void readSep(TokenStream input, wstring sep)
{
    if (input.matchSep(sep) == false)
    {
        throw new ParseError(
            "expected \"" ~ to!string(sep) ~ "\"",
            input.getPos()
        );
    }
}

/**
Test if a semicolon could be automatically inserted at the current position
*/
bool autoSemicolon(TokenStream input)
{
    auto curTok = input.peek();

    return (
        (curTok.type == Token.SEP && curTok.stringVal == "}") ||
        input.newline() == true ||
        input.eof() == true
    );
}

/**
Read and consume a semicolon or an automatically inserted semicolon
*/
void readSemiAuto(TokenStream input)
{
    if (input.matchSep(";") == false)
    {
        if (autoSemicolon(input) == false)
        {
            throw new ParseError(
                "expected semicolon or end of statement",
                input.getPos()
            );
        }
    }
}

/**
Parse a source file
*/
ASTProgram parseFile(string fileName)
{
    string src = readText!(string)(fileName);
    return parseString(src, fileName);
}

/**
Parse a source string
*/
ASTProgram parseString(string src, string fileName = "")
{
    // Convert the string to UTF-16
    wstring wSrc = toUTF16(src);

    TokenStream input = lexString(wSrc, fileName);

    return parseProgram(input);
}

/**
Parse a top-level program node
*/
ASTProgram parseProgram(TokenStream input)
{
    SrcPos pos = input.getPos();

    auto stmtApp = appender!(ASTStmt[])();

    while (input.eof() == false)
    {
        ASTStmt stmt = parseStmt(input);
        stmtApp.put(stmt);
    }

    // Create the AST program node
    auto ast = new ASTProgram(stmtApp.data, pos);
    
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
        readSep(input, "(");
        ASTExpr testExpr = parseExpr(input);
        readSep(input, ")");

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
        readSep(input, "(");
        auto testExpr = parseExpr(input);
        readSep(input, ")");
        auto bodyStmt = parseStmt(input);

        return new WhileStmt(testExpr, bodyStmt, pos);
    }

    // Do-while loop
    else if (input.matchKw("do"))
    {
        auto bodyStmt = parseStmt(input);
        if (input.matchKw("while") == false)
            throw new ParseError("expected while", input.getPos());
        readSep(input, "(");
        auto testExpr = parseExpr(input);
        readSep(input, ")");

        return new DoWhileStmt(bodyStmt, testExpr, pos);
    }

    // For loop
    else if (input.matchKw("for"))
    {
        // Parse the init statement
        readSep(input, "(");
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
            readSep(input, ";");
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
            readSep(input, ")");
        }

        // Parse the loop body
        auto bodyStmt = parseStmt(input);

        return new ForStmt(initStmt, testExpr, incrExpr, bodyStmt, pos);
    }

    // Switch statement
    else if (input.matchKw("switch"))
    {
        readSep(input, "(");
        auto switchExpr = parseExpr(input);
        readSep(input, ")");
        readSep(input, "{");

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
                readSep(input, ":");

                caseStmts ~= [[]];
                curStmts = &caseStmts[caseStmts.length-1];
            }

            else if (input.matchKw("default"))
            {
                readSep(input, ":");
                if (defaultSeen is true)
                    throw new ParseError("duplicate default label", input.getPos());

                defaultSeen = true;
                curStmts = &defaultStmts;
            }

            else
            {
                if (curStmts is null)
                    throw new ParseError("statement before label", input.getPos());

                curStmts.length += 1;
                (*curStmts)[curStmts.length-1] = parseStmt(input);
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
        readSemiAuto(input);
        return new BreakStmt(pos);
    }

    // Continue statement
    else if (input.matchKw("continue"))
    {
        readSemiAuto(input);
        return new BreakStmt(pos);
    }

    // Return statement
    else if (input.matchKw("return"))
    {
        if (input.matchSep(";"))
            return new ReturnStmt(new NullExpr(), pos);

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

        if (input.matchKw("catch") == false)
            throw new ParseError("expected catch keyword", input.getPos());
        readSep(input, "(");
        auto catchIdent = cast(IdentExpr)parseExpr(input);
        if (catchIdent is null)
            throw new ParseError("invalid catch identifier", catchIdent.pos);
        readSep(input, ")");

        auto catchStmt = parseStmt(input);

        ASTStmt finallyStmt;
        if (input.matchKw("finally"))
            finallyStmt = parseStmt(input);
        else
            finallyStmt = new ExprStmt(new TrueExpr());

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
                initExpr = parseExpr(input);
            }
    
            identExprs ~= [identExpr];
            initExprs ~= [initExpr];
        }

        return new VarStmt(identExprs, initExprs, pos);
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
Parse an expression
*/
ASTExpr parseExpr(TokenStream input, int minPrec = 1)
{
    // Expression parsing using the precedence climbing algorithm
    //    
    // The first call has min precedence 1
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
            readSep(input, "]");
            lhsExpr = new IndexExpr(lhsExpr, indexExpr, lhsExpr.pos);
        }

        // If this is the ternary conditional operator
        else if (cur.stringVal == "?")
        {
            // Consume the current token
            input.read();

            auto trueExpr = parseExpr(input);
            readSep(input, ":");
            auto falseExpr = parseExpr(input, nextMinPrec);

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

ASTExpr parseAtom(TokenStream input)
{
    //writeln("parseAtom");

    Token t = input.peek();
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
        readSep(input, ")");
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
        IdentExpr[] names = [];
        ASTExpr[] values = [];

        for (;;)
        {
            if (input.matchSep("}"))
                break;

            if (values.length > 0 && input.matchSep(",") == false)
                throw new ParseError("expected comma", input.getPos());

            auto nameExpr = parseAtom(input);
            auto identExpr = cast(IdentExpr)nameExpr;
            auto stringExpr = cast(StringExpr)nameExpr;
            if (stringExpr)
                identExpr = new IdentExpr(stringExpr.val, stringExpr.pos);
            if (!identExpr)
                throw new ParseError("invalid property name", nameExpr.pos);
            names ~= [identExpr];

            readSep(input, ":");

            // TODO: priority above comma op?
            auto valueExpr = parseExpr(input);
            values ~= [valueExpr];
        }

        return new ObjectExpr(names, values, pos);
    }

    // New expression
    else if (t.type == Token.OP && t.stringVal == "new")
    {
        // Consume the "new" token
        input.read();

        // Parse the base expression
        auto op = findOperator(t.stringVal, 1, 'r');
        auto baseExpr = parseExpr(input, op.prec);

        // Parse the argument list and create the new expression
        auto argExprs = parseExprList(input, "(", ")");
        return new NewExpr(baseExpr, argExprs, t.pos);
    }

    // Function expression
    // fun (params) body
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

        return new UnOpExpr(op, expr, pos);
    }

    throw new ParseError("unexpected token: " ~ t.toString(), pos);
}

/**
Parse a list of expressions
*/
ASTExpr[] parseExprList(TokenStream input, wstring openSep, wstring closeSep)
{
    readSep(input, openSep);

    ASTExpr[] exprs = [];

    for (;;)
    {
        if (input.matchSep(closeSep))
            break;

        if (exprs.length > 0 && input.matchSep(",") == false)
            throw new ParseError("expected comma", input.getPos());

        exprs ~= [parseExpr(input)];
    }

    return exprs;
}

/**
Parse a function declaration's parameter list
*/
IdentExpr[] parseParamList(TokenStream input)
{
    readSep(input, "(");

    IdentExpr[] exprs = [];

    for (;;)
    {
        if (input.matchSep(")"))
            break;

        if (exprs.length > 0 && input.matchSep(",") == false)
            throw new ParseError("expected comma", input.getPos());

        auto expr = parseExpr(input);

        auto ident = cast(IdentExpr)expr;
        if (ident is null)
            throw new ParseError("invalid list item type", expr.pos);

        exprs ~= [ident];
    }

    return exprs;
}

