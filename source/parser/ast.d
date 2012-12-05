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

module parser.ast;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.algorithm;
import std.math;
import util.id;
import util.string;
import parser.lexer;

/**
Base class for all AST nodes
*/
class ASTNode : IdObject
{
    SrcPos pos;

    // Force subclasses to set the position
    this(SrcPos pos)
    { 
        this.pos = pos; 
    }
}

/**
Top-level program (source file) node
*/
class ASTProgram : FunExpr
{
    this(ASTStmt[] stmts, SrcPos pos = null)
    {
        super(null, [], new BlockStmt(stmts), pos);
    }

    string toString()
    {
        auto blockStmt = cast(BlockStmt)bodyStmt;
        auto stmts = blockStmt.stmts;

        string str;

        for (size_t i = 0; i < stmts.length; ++i)
        {
            auto stmt = stmts[i];
            str ~= stmt.toString();
            if (i < stmts.length - 1)
                str ~= "\n";
        }

        return str;
    }
}

/**
Base class for AST statement nodes
*/
class ASTStmt : ASTNode
{
    /// Labels preceding this statement
    IdentExpr[] labels = [];

    this(SrcPos pos)
    {
        super(pos);
    }

    string blockStr()
    {
        if (cast(BlockStmt)this)
        {
            return this.toString();
        }
        else
        {
            return "{\n" ~ indent(this.toString()) ~ "\n}";
        }
    }
}

/**
Block/sequence statement
*/
class BlockStmt : ASTStmt
{
    ASTStmt[] stmts;

    this(ASTStmt[] stmts, SrcPos pos = null)
    {
        super(pos);
        this.stmts = stmts;
    }

    string toString()
    {
        string str;
        foreach (stmt; stmts)
            str ~= stmt.toString() ~ "\n";

        return format("{\n%s}", indent(str));
    }
}

/**
Variable declaration/initialization statement
*/
class VarStmt : ASTStmt
{
    /// Identifier expressions
    IdentExpr[] identExprs;

    /// Initializer expressions
    ASTExpr[] initExprs;

    this(IdentExpr[] identExprs, ASTExpr[] initExprs, SrcPos pos = null)
    {
        assert (identExprs.length == initExprs.length);

        super(pos);
        this.identExprs = identExprs;
        this.initExprs = initExprs;
    }

    string toString()
    {
        auto output = appender!(string)();

        output.put("var ");

        for (size_t i = 0; i < identExprs.length; ++i)
        {
            output.put(identExprs[i].toString());

            if (initExprs[i])
            {
                output.put(" = ");
                output.put(initExprs[i].toString());
            }

            if (i < identExprs.length - 1)
                output.put(", ");
        }

        output.put(";");

        return output.data;
    }
}

/**
If statement
*/
class IfStmt : ASTStmt
{
    ASTExpr testExpr;
    ASTStmt trueStmt;
    ASTStmt falseStmt;

    this(
        ASTExpr testExpr, 
        ASTStmt trueStmt,
        ASTStmt falseStmt,
        SrcPos pos = null
    )
    {
        super(pos);
        this.testExpr = testExpr;
        this.trueStmt = trueStmt;
        this.falseStmt = falseStmt;
    }

    string toString()
    {
        if (falseStmt)
        {
            return format(
                "if (%s)\n%s\nelse\n%s", 
                testExpr,
                trueStmt.blockStr(),
                falseStmt.blockStr()
            );
        }
        else
        {
            return format(
                "if (%s)\n%s", 
                testExpr,
                trueStmt.blockStr()
            );
        }
    }
}

/**
While loop statement
*/
class WhileStmt : ASTStmt
{
    ASTExpr testExpr;
    ASTStmt bodyStmt;

    this(
        ASTExpr testExpr, 
        ASTStmt bodyStmt,
        SrcPos pos = null
    )
    {
        super(pos);
        this.testExpr = testExpr;
        this.bodyStmt = bodyStmt;
    }

    string toString()
    {
        return format(
            "while (%s)\n%s", 
            testExpr,
            bodyStmt.blockStr()
        );
    }
}

/**
For loop statement
*/
class ForStmt : ASTStmt
{
    ASTStmt initStmt;
    ASTExpr testExpr;
    ASTExpr incrExpr;
    ASTStmt bodyStmt;

    this(
        ASTStmt initStmt, 
        ASTExpr testExpr, 
        ASTExpr incrExpr, 
        ASTStmt bodyStmt,
        SrcPos pos = null
    )
    {
        assert (
            cast(VarStmt)initStmt !is null ||
            cast(ExprStmt)initStmt !is null
        );

        super(pos);
        this.initStmt = initStmt;
        this.testExpr = testExpr;
        this.incrExpr = incrExpr;
        this.bodyStmt = bodyStmt;
    }

    string toString()
    {
        return format(
            "for (%s %s; %s)\n%s", 
            initStmt,
            testExpr,
            incrExpr,
            bodyStmt.blockStr()
        );
    }
}

/**
For-in loop statement

Grammar:
for (LeftHandSideExpression in Expression)
for (var VariableDeclarationNoIn in Expression)

Examples:
for (a in [0, 1, 2]) print(a);
for (a.b in [0, 1, 2]) print(a.b);
for (var a in b) print(a);
for (var a in 0,[0,1,2]) print(a);
*/
class ForInStmt : ASTStmt
{
    /// Flag indicating there is a variable declaration
    bool hasDecl;

    /// If this has a variable declaration, this must be an IdentExpr
    ASTExpr varExpr;

    ASTExpr inExpr;

    ASTStmt bodyStmt;

    this(
        bool hasDecl,
        ASTExpr varExpr,
        ASTExpr inExpr,
        ASTStmt bodyStmt,
        SrcPos pos = null
    )
    {
        super(pos);
        this.hasDecl = hasDecl;
        this.varExpr = varExpr;
        this.inExpr = inExpr;
        this.bodyStmt = bodyStmt;
    }

    string toString()
    {
        return format(
            "for (%s%s in %s)\n%s", 
            hasDecl? "var ":"",
            varExpr,
            inExpr,
            bodyStmt.blockStr()
        );
    }
}

/**
Do-while loop statement
*/
class DoWhileStmt : ASTStmt
{
    ASTStmt bodyStmt;
    ASTExpr testExpr;

    this(
        ASTStmt bodyStmt,
        ASTExpr testExpr,
        SrcPos pos = null
    )
    {
        super(pos);
        this.bodyStmt = bodyStmt;
        this.testExpr = testExpr;
    }

    string toString()
    {
        return format(
            "do\n%s\nwhile (%s)", 
            bodyStmt.blockStr(),
            testExpr
        );
    }
}

/**
Switch statement
*/
class SwitchStmt : ASTStmt
{
    ASTExpr switchExpr;

    ASTExpr[] caseExprs;

    ASTStmt[][] caseStmts;

    ASTStmt[] defaultStmts;

    this(
        ASTExpr switchExpr,
        ASTExpr[] caseExprs,
        ASTStmt[][] caseStmts,
        ASTStmt[] defaultStmts,
        SrcPos pos = null
    )
    {
        assert (caseExprs.length == caseStmts.length);

        super(pos);
        this.switchExpr = switchExpr;
        this.caseExprs = caseExprs;
        this.caseStmts = caseStmts;
        this.defaultStmts = defaultStmts;
    }

    string toString()
    {
        auto output = appender!(string)();

        output.put("switch (");
        output.put(switchExpr.toString());
        output.put(")\n{\n");

        auto bodyApp = appender!(string)();

        for (size_t i = 0; i < caseExprs.length; ++i)
        {
            bodyApp.put("case ");
            bodyApp.put(caseExprs[i].toString());
            bodyApp.put(":\n");
            auto stmts = caseStmts[i];
            foreach (stmt; stmts)
            {
                bodyApp.put(stmt.toString());
                bodyApp.put("\n");
            }
        }

        bodyApp.put("default:\n");
        if (defaultStmts !is null)
        {
            foreach (stmt; defaultStmts)
            {
                bodyApp.put(stmt.toString());
                bodyApp.put("\n");
            }
        }

        output.put(indent(bodyApp.data));

        output.put("}");

        return output.data;
    }
}

/**
Break statement
*/
class BreakStmt : ASTStmt
{
    IdentExpr label;

    this(IdentExpr label, SrcPos pos = null)
    {
        super(pos);
        this.label = label;
    }

    string toString()
    {
        if (label)
            return format("break %s;", label);
        else
            return format("break;");
    }
}

/**
Continue statement
*/
class ContStmt : ASTStmt
{
    IdentExpr label;

    this(SrcPos pos = null)
    {
        super(pos);
    }

    this(IdentExpr label, SrcPos pos = null)
    {
        super(pos);
        this.label = label;
    }

    string toString()
    {
        if (label)
            return format("continue %s;", label);
        else
            return format("continue;");
    }
}

/**
Return statement
*/
class ReturnStmt : ASTStmt
{
    ASTExpr expr;

    this(ASTExpr expr, SrcPos pos = null)
    {
        super(pos);
        this.expr = expr;
    }

    string toString()
    {
        return format("return %s;", expr);
    }
}

/**
Throw statement
*/
class ThrowStmt : ASTStmt
{
    ASTExpr expr;

    this(ASTExpr expr, SrcPos pos = null)
    {
        super(pos);
        this.expr = expr;
    }

    string toString()
    {
        return format("throw %s;", expr);
    }
}

/**
Try-catch-finally statement
*/
class TryStmt : ASTStmt
{
    ASTStmt tryStmt;
    IdentExpr catchIdent;
    ASTStmt catchStmt;
    ASTStmt finallyStmt;

    this(
        ASTStmt tryStmt,
        IdentExpr catchIdent,
        ASTStmt catchStmt,
        ASTStmt finallyStmt,
        SrcPos pos = null
    )
    {
        super(pos);
        this.tryStmt = tryStmt;
        this.catchIdent = catchIdent;
        this.catchStmt = catchStmt;
        this.finallyStmt = finallyStmt;
    }

    string toString()
    {
        auto output = appender!string();

        output.put("try\n");
        output.put(tryStmt.blockStr());

        if (this.catchStmt)
        {
            output.put("\ncatch (");
            output.put(catchIdent.toString());
            output.put(")\n");
            output.put(catchStmt.blockStr());
        }

        if (this.finallyStmt)
        {
            output.put("\nfinally\n");
            output.put(finallyStmt.blockStr());
        }

        return output.data;
    }
}

/**
Expression statement
*/
class ExprStmt : ASTStmt
{
    ASTExpr expr;

    this(ASTExpr expr, SrcPos pos = null)
    {
        super(pos);
        this.expr = expr;
    }

    string toString()
    {
        return format("%s;", expr);
    }
}

/**
Base class for AST expressions
*/
class ASTExpr : ASTNode
{
    this(SrcPos pos) 
    {
        super(pos); 
    }

    /// Get the operator precedence for this expression
    int getPrec()
    {
        // By default, maximum precedence (atomic)
        return MAX_PREC;
    }

    /// Parenthesize this expression as appropriate
    string parenString(ASTExpr parent)
    {
        if (parent.getPrec() > this.getPrec())
            return "(" ~ this.toString() ~ ")";
        else
            return this.toString();
    }
}

/**
Function declaration expression
*/
class FunExpr : ASTExpr
{
    /// Function name identifier
    IdentExpr name;

    /// Function parameters
    IdentExpr[] params;

    /// Function body
    ASTStmt bodyStmt;

    /// List of local variables declarations
    ASTNode[] locals;

    /// List of nested function declarations
    FunExpr[] funDecls;

    this(IdentExpr name, IdentExpr[] params, ASTStmt bodyStmt, SrcPos pos = null)
    {
        super(pos);
        this.name = name;
        this.params = params;
        this.bodyStmt = bodyStmt;
    }

    string getName()
    {
        return name? name.toString():"";
    }

    string toString()
    {
        auto output = appender!string();

        output.put(xformat("function %s(%(%s, %))", getName(), params));

        if (cast(ReturnStmt)bodyStmt || cast(ExprStmt)bodyStmt)
        {
            output.put(" ");
            output.put(bodyStmt.toString());
        }
        else
        {
            output.put("\n");
            output.put(bodyStmt.blockStr());
        }

        return output.data;
    }
}

/**
Binary operator expression
*/
class BinOpExpr : ASTExpr
{
    /// Binary operator
    Operator op;

    /// Subexpressions
    ASTExpr lExpr;
    ASTExpr rExpr;

    this(Operator op, ASTExpr lExpr, ASTExpr rExpr, SrcPos pos = null)
    {
        assert (op !is null, "operator is null");
        assert (op.arity == 2, "invalid arity");

        super(pos);
        this.op = op;
        this.lExpr = lExpr;
        this.rExpr = rExpr;
    }

    this(wstring opStr, ASTExpr lExpr, ASTExpr rExpr, SrcPos pos = null)
    {
        auto op = findOperator(opStr, 2);
        this(op, lExpr, rExpr, pos);
    }

    int getPrec()
    {
        return op.prec;
    }

    string toString()
    {
        string opStr;

        if (op.str == ".")
            opStr = ".";
        else if (op.str == ",")
            opStr = ", ";
        else
            opStr = " " ~ to!string(op.str) ~ " ";

        return format(
            "%s%s%s",
            lExpr.parenString(this),
            opStr,
            rExpr.parenString(this)
        );
    }
}

/**
Unary operator expression
*/
class UnOpExpr : ASTExpr
{
    /// Unary operator
    Operator op;

    /// Subexpression
    ASTExpr expr;

    this(Operator op, ASTExpr expr, SrcPos pos = null)
    {
        assert (op.arity == 1);

        super(pos);
        this.op = op;
        this.expr = expr;
    }

    this(wstring opStr, char assoc, ASTExpr expr, SrcPos pos = null)
    {
        auto op = findOperator(opStr, 1, assoc);
        this(op, expr, pos);
    }

    int getPrec()
    {
        return op.prec;
    }

    string toString()
    {
        if (op.assoc == 'r')
            return format("%s%s", op.str, expr.parenString(this));
        else
            return format("%s%s", expr.parenString(this), op.str);
    }
}

/**
Ternary conditional "?" operator expression
*/
class CondExpr : ASTExpr
{
    ASTExpr testExpr;
    ASTExpr trueExpr;
    ASTExpr falseExpr;

    this(ASTExpr testExpr, ASTExpr trueExpr, ASTExpr falseExpr, SrcPos pos = null)
    {
        super(pos);
        this.testExpr = testExpr;
        this.trueExpr = trueExpr;
        this.falseExpr = falseExpr;
    }

    string toString()
    {
        return format("%s? %s:%s", testExpr, trueExpr, falseExpr);
    }
}

/**
Function call expression
*/
class CallExpr : ASTExpr
{
    ASTExpr base;

    ASTExpr[] args;

    this(ASTExpr base, ASTExpr[] args, SrcPos pos = null)
    {
        super(pos);
        this.base = base;
        this.args = args;
    }

    string toString()
    {
        return xformat("%s(%(%s, %))", base, args);
    }
}

/**
New/constructor expression
*/
class NewExpr : ASTExpr
{
    ASTExpr base;

    ASTExpr[] args;

    this(ASTExpr base, ASTExpr[] args, SrcPos pos = null)
    {
        super(pos);
        this.base = base;
        this.args = args;
    }

    string toString()
    {
        return xformat("new %s(%(%s, %))", base, args);
    }
}

/**
Array/object indexing (subscript) expression
*/
class IndexExpr : ASTExpr
{
    ASTExpr base;

    ASTExpr index;

    this(ASTExpr base, ASTExpr index, SrcPos pos = null)
    {
        super(pos);
        this.base = base;
        this.index = index;
    }

    string toString()
    {
        return xformat("%s[%s]", base, index);
    }
}

/**
Array literal expression
*/
class ArrayExpr : ASTExpr
{
    ASTExpr[] exprs;

    this(ASTExpr[] exprs, SrcPos pos = null)
    {
        super(pos);
        this.exprs = exprs;
    }

    string toString()
    {
        return xformat("[%(%s, %)]", exprs);
    }
}

/**
Object literal expression
*/
class ObjectExpr : ASTExpr
{
    StringExpr[] names;

    ASTExpr[] values;

    this(StringExpr[] names, ASTExpr[] values, SrcPos pos = null)
    {
        assert (names.length == values.length);

        super(pos);
        this.names = names;
        this.values = values;
    }

    string toString()
    {
        auto output = appender!(string)();

        output.put("{");

        for (size_t i = 0; i < names.length; ++i)
        {
            output.put(names[i].toString());
            output.put(":");
            output.put(values[i].toString());
            if (i != names.length - 1)
                output.put(", ");
        }

        output.put("}");

        return output.data;
    }
}

/**
Identifier/symbol expression
*/
class IdentExpr : ASTExpr
{
    /// Identifier name string
    wstring name;

    /// AST node where this variable was declared, if applicable
    ASTNode declNode = null;

    this(wstring name, SrcPos pos = null)
    {
        super(pos);
        this.name = name;
    }

    string toString()
    {
        return to!string(name);
    }
}

/**
Integer constant expression
*/
class IntExpr : ASTExpr
{
    long val;

    this(long val, SrcPos pos = null)
    {
        super(pos);
        this.val = val;
    }

    string toString()
    {
        return to!(string)(val);
    }
}

/**
Floating-point constant expression
*/
class FloatExpr : ASTExpr
{
    double val;

    this(double val, SrcPos pos = null)
    {
        super(pos);
        this.val = val;
    }

    string toString()
    {
        if (floor(val) == val)
            return format("%.1f", val);
        else
            return format("%f", val);
    }
}

/**
String-constant expression
*/
class StringExpr : ASTExpr
{
    wstring val;

    this(wstring val, SrcPos pos = null)
    {
        super(pos);
        this.val = val;
    }

    string toString()
    {
        return "\"" ~ to!string(escapeJSString(val)) ~ "\"";
    }
}

/**
True boolean constant expression
*/
class TrueExpr : ASTExpr
{
    this(SrcPos pos = null)
    {
        super(pos);
    }

    string toString()
    {
        return "true";
    }
}

/**
False boolean constant expression
*/
class FalseExpr : ASTExpr
{
    this(SrcPos pos = null)
    {
        super(pos);
    }

    string toString()
    {
        return "false";
    }
}

/**
Null constant expression
*/
class NullExpr : ASTExpr
{
    this(SrcPos pos = null)
    {
        super(pos);
    }

    string toString()
    {
        return "null";
    }
}

