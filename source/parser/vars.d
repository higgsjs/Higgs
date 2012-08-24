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

module parser.vars;

import parser.ast;

/**
Representation of nested scopes and associated variable declarations
*/
class Scope
{
    /// Parent scope
    Scope parent;

    /// Associated AST node
    ASTNode node;

    /// Declarations in this scope, indexed by name
    ASTNode[string] decls;

    this(ASTNode node, Scope parent = null)
    {
        this.node = node;
        this.parent = parent;
    }

    /**
    Add a declaration to this scope
    */
    void addDecl(ASTNode node, string name)
    {
        // If this variable was already declared, do nothing
        if (name in decls)
            return;

        // Add the declaraction to this scope
        decls[name] = node;

        // Find the function scope encompassing this declaration, if any
        Scope funScope = this;
        while (funScope !is null && cast(FunExpr)funScope.node is null)
            funScope = funScope.parent;

        // Add the declaration to the function node
        if (funScope !is null)
        {
            auto funNode = cast(FunExpr)funScope.node;
            funNode.locals ~= [node];
        }
    }

    /**
    Resolve an variable's declaration by name
    */
    ASTNode resolve(string name)
    {
        if (name in decls)
            return decls[name];

        if (parent)
            return parent.resolve(name);

        return null;
    }
}

void resolveVars(ASTProgram node)
{
    // The top-level scope
    auto s = new Scope(node);

    resolveVars(node.bodyStmt, s);
}

void resolveVars(ASTStmt stmt, Scope s)
{
    if (auto blockStmt = cast(BlockStmt)stmt)
    {
        s = new Scope(stmt, s);

        // Parse variable declarations in this scope
        foreach (subStmt; blockStmt.stmts)
            if (auto varStmt = cast(VarStmt)subStmt)
                s.addDecl(varStmt, varStmt.identExpr.name);

        foreach (subStmt; blockStmt.stmts)
            resolveVars(subStmt, s);
    }

    else if (auto varStmt = cast(VarStmt)stmt)
    {
        resolveVars(varStmt.identExpr, s);

        if (varStmt.initExpr)
            resolveVars(varStmt.initExpr, s);
    }

    else if (auto ifStmt = cast(IfStmt)stmt)
    {
        resolveVars(ifStmt.testExpr, s);
        resolveVars(ifStmt.trueStmt, s);
        resolveVars(ifStmt.falseStmt, s);
    }
    
    else if (auto whileStmt = cast(WhileStmt)stmt)
    {
        resolveVars(whileStmt.testExpr, s);
        resolveVars(whileStmt.bodyStmt, s);
    }

    else if (auto doStmt = cast(DoWhileStmt)stmt)
    {
        resolveVars(doStmt.testExpr, s);
        resolveVars(doStmt.bodyStmt, s);
    }

    else if (auto forStmt = cast(ForStmt)stmt)
    {
        s = new Scope(forStmt, s);
        if (auto varStmt = cast(VarStmt)forStmt.initStmt)
            s.addDecl(varStmt, varStmt.identExpr.name);

        resolveVars(forStmt.initStmt, s);
        resolveVars(forStmt.testExpr, s);
        resolveVars(forStmt.incrExpr, s);
        resolveVars(forStmt.bodyStmt, s);
    }

    else if (auto retStmt = cast(ReturnStmt)stmt)
    {
        resolveVars(retStmt.expr, s);
    }

    else if (auto throwStmt = cast(ThrowStmt)stmt)
    {
        resolveVars(throwStmt.expr, s);
    }

    else if (auto tryStmt = cast(TryStmt)stmt)
    {
        resolveVars(tryStmt.tryStmt, s);

        auto ss = new Scope(tryStmt.catchIdent, s);
        ss.addDecl(tryStmt.catchIdent, tryStmt.catchIdent.name);
        resolveVars(tryStmt.catchStmt, ss);

        resolveVars(tryStmt.finallyStmt, s);
    }

    else if (auto exprStmt = cast(ExprStmt)stmt)
    {
        resolveVars(exprStmt.expr, s);
    }

    else
    {
        assert (false, "unhandled statement type:\n" ~ stmt.toString());
    }
}

void resolveVars(ASTExpr expr, Scope s)
{
    if (auto funExpr = cast(FunExpr)expr)
    {
        s = new Scope(funExpr, s);

        foreach (ident; funExpr.params)
            s.addDecl(ident, ident.name);

        resolveVars(funExpr.bodyStmt, s);
    }

    else if (auto binExpr = cast(BinOpExpr)expr)
    {
        resolveVars(binExpr.lExpr, s);
        resolveVars(binExpr.rExpr, s);
    }

    else if (auto unExpr = cast(UnOpExpr)expr)
    {
        resolveVars(unExpr.expr, s);
    }

    else if (auto condExpr = cast(CondExpr)expr)
    {
        resolveVars(condExpr.testExpr, s);
        resolveVars(condExpr.trueExpr, s);
        resolveVars(condExpr.falseExpr, s);
    }

    else if (auto callExpr = cast(CallExpr)expr)
    {
        resolveVars(callExpr.base, s);
        foreach (e; callExpr.args)
            resolveVars(e, s);
    }

    else if (auto newExpr = cast(NewExpr)expr)
    {
        resolveVars(newExpr.base, s);
        foreach (e; newExpr.args)
            resolveVars(e, s);
    }

    else if (auto indexExpr = cast(IndexExpr)expr)
    {
        resolveVars(indexExpr.base, s);
        resolveVars(indexExpr.index, s);
    }

    else if (auto arrayExpr = cast(ArrayExpr)expr)
    {
        foreach (e; arrayExpr.exprs)
            resolveVars(e, s);
    }

    else if (auto identExpr = cast(IdentExpr)expr)
    {
        // Resolve the variable
        ASTNode decl = s.resolve(identExpr.name);

        // Store the resolved node on the identifier
        identExpr.declNode = decl;
    }

    else if (
        cast(IntExpr)expr       ||
        cast(FloatExpr)expr     ||
        cast(StringExpr)expr    ||
        cast(TrueExpr)expr      ||
        cast(FalseExpr)expr     ||
        cast(NullExpr)expr
    )
    {
        // Do nothing
    }

    else
    {
        assert (false, "unhandled expression type:\n" ~ expr.toString());
    }
}

