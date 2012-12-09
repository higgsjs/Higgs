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

import std.stdio;
import parser.ast;

/**
Representation of nested scopes and associated variable declarations
*/
class Scope
{
    /// Parent scope
    Scope parent;

    /// Associated function
    FunExpr fun;

    /// Declarations in this scope, indexed by name
    IdentExpr[wstring] decls;

    /// Variable references in this scope
    IdentExpr[] refs;

    this(FunExpr fun, Scope parent = null)
    {
        this.fun = fun;
        this.parent = parent;
    }

    /**
    Add a declaration to this scope
    */
    void addDecl(IdentExpr ident)
    {
        // If this variable was already declared, do nothing
        if (ident.name in decls)
            return;

        // Add the declaraction to this scope
        decls[ident.name] = ident;

        // Add the local to the function
        fun.locals ~= [ident];
    }

    /**
    Add a nested function declaration
    */
    void addFunDecl(FunExpr node)
    {
        fun.funDecls ~= [node];
    }

    /**
    Resolve the declaration corresponding to an identifier
    */
    IdentExpr resolve(IdentExpr ident)
    {
        auto decl = resolve(ident.name, fun);

        //writefln("unresolved: %s", ident);

        ident.declNode = decl;

        return decl;
    }

    /**
    Resolve a variable's declaration by name
    */
    private IdentExpr resolve(wstring name, FunExpr from)
    {
        // If the declaration was found
        if (name in decls)
        {
            auto decl = decls[name];

            // If the reference is not from this function
            if (fun !is from)
            {
                fun.escpVars[decl] = true;
                from.captVars ~= decl;
            }

            return decl;
        }

        // If there is a parent context
        if (parent !is null)
        {
            auto decl = parent.resolve(name, from);

            // If this is a reference from a nested
            // function to a variable in a parent function
            if (decl !is null && from !is fun && decl !in fun.escpVars)
            {
                fun.escpVars[decl] = true;
                fun.captVars ~= decl;
            }

            return decl;
        }

        return null;
    }
}

/**
Resolve variable declarations and references in a function
*/
void resolveVars(FunExpr fun, Scope parentSc = null)
{
    //writefln("fun: %s", fun.toString());

    auto s = new Scope(fun, parentSc);

    // Add the parameter declarations to the scope
    foreach (ident; fun.params)
        s.addDecl(ident);

    // Find all declarations in the function body
    findDecls(fun.bodyStmt, s);

    // Resolve references in the function body
    resolveRefs(fun.bodyStmt, s);
}

/**
Find all variable/function declarations in a given statement
*/
void findDecls(ASTStmt stmt, Scope s)
{
    if (auto blockStmt = cast(BlockStmt)stmt)
    {
        foreach (subStmt; blockStmt.stmts)
            findDecls(subStmt, s);
    }

    else if (auto varStmt = cast(VarStmt)stmt)
    {
        for (size_t i = 0; i < varStmt.identExprs.length; ++i)
        {
            auto ident = varStmt.identExprs[i];

            // If we are not in a top-level (program) scope,
            // add a declaration for this variable
            if (cast(ASTProgram)s.fun is null)
                s.addDecl(ident);
        }
    }

    else if (auto ifStmt = cast(IfStmt)stmt)
    {
        findDecls(ifStmt.trueStmt, s);
        findDecls(ifStmt.falseStmt, s);
    }
    
    else if (auto whileStmt = cast(WhileStmt)stmt)
    {
        findDecls(whileStmt.bodyStmt, s);
    }

    else if (auto doStmt = cast(DoWhileStmt)stmt)
    {
        findDecls(doStmt.bodyStmt, s);
    }

    else if (auto forStmt = cast(ForStmt)stmt)
    {
        findDecls(forStmt.initStmt, s);
        findDecls(forStmt.bodyStmt, s);
    }

    else if (auto forInStmt = cast(ForInStmt)stmt)
    {
        if (forInStmt.hasDecl)
        {
            auto ident = cast(IdentExpr)forInStmt.varExpr;
            s.addDecl(ident);
        }

        findDecls(forInStmt.bodyStmt, s);
    }

    else if (auto switchStmt = cast(SwitchStmt)stmt)
    {
        foreach (caseStmts; switchStmt.caseStmts)
            foreach (caseStmt; caseStmts)
                findDecls(caseStmt, s);

        foreach (defaultStmt; switchStmt.defaultStmts)
            findDecls(defaultStmt, s);
    }

    else if (auto tryStmt = cast(TryStmt)stmt)
    {
        findDecls(tryStmt.tryStmt, s);
        if (tryStmt.catchStmt)
        {
            s.addDecl(tryStmt.catchIdent);
            findDecls(tryStmt.catchStmt, s);
        }
        if (tryStmt.finallyStmt)
        {
            findDecls(tryStmt.finallyStmt, s);
        }
    }

    else if (auto exprStmt = cast(ExprStmt)stmt)
    {
        // If this is a named function declaration
        if (auto funExpr = cast(FunExpr)exprStmt.expr)
        {
            if (funExpr.name !is null)
            {
                s.addFunDecl(funExpr);

                // If we are not in a top-level (program) scope,
                // declare the function as a variable
                if (cast(ASTProgram)s.fun is null)
                {
                    s.addDecl(funExpr.name);
                    resolveRefs(funExpr.name, s);
                }
            }
        }
    }

    else if (
        cast(ReturnStmt)stmt ||
        cast(ThrowStmt)stmt  ||
        cast(BreakStmt)stmt  ||
        cast(ContStmt)stmt)
    {
        // Do nothing
    }

    else
    {
        assert (false, "unhandled statement type:\n" ~ stmt.toString());
    }
}

/**
Resolve variable references in a statement
*/
void resolveRefs(ASTStmt stmt, Scope s)
{
    if (auto blockStmt = cast(BlockStmt)stmt)
    {
        foreach (subStmt; blockStmt.stmts)
            resolveRefs(subStmt, s);
    }

    else if (auto varStmt = cast(VarStmt)stmt)
    {
        for (size_t i = 0; i < varStmt.identExprs.length; ++i)
        {
            auto ident = varStmt.identExprs[i];
            auto init = varStmt.initExprs[i];

            resolveRefs(ident, s);

            if (init)
                resolveRefs(init, s);
        }
    }

    else if (auto ifStmt = cast(IfStmt)stmt)
    {
        resolveRefs(ifStmt.testExpr, s);
        resolveRefs(ifStmt.trueStmt, s);
        resolveRefs(ifStmt.falseStmt, s);
    }
    
    else if (auto whileStmt = cast(WhileStmt)stmt)
    {
        resolveRefs(whileStmt.testExpr, s);
        resolveRefs(whileStmt.bodyStmt, s);
    }

    else if (auto doStmt = cast(DoWhileStmt)stmt)
    {
        resolveRefs(doStmt.testExpr, s);
        resolveRefs(doStmt.bodyStmt, s);
    }

    else if (auto forStmt = cast(ForStmt)stmt)
    {
        resolveRefs(forStmt.initStmt, s);
        resolveRefs(forStmt.testExpr, s);
        resolveRefs(forStmt.incrExpr, s);
        resolveRefs(forStmt.bodyStmt, s);
    }

    else if (auto forInStmt = cast(ForInStmt)stmt)
    {
        resolveRefs(forInStmt.inExpr, s);
        resolveRefs(forInStmt.bodyStmt, s);
    }

    else if (auto switchStmt = cast(SwitchStmt)stmt)
    {
        resolveRefs(switchStmt.switchExpr, s);

        foreach (expr; switchStmt.caseExprs)
            resolveRefs(expr, s);

        foreach (caseStmts; switchStmt.caseStmts)
            foreach (caseStmt; caseStmts)
                resolveRefs(caseStmt, s);

        foreach (defaultStmt; switchStmt.defaultStmts)
            resolveRefs(defaultStmt, s);
    }

    else if (auto retStmt = cast(ReturnStmt)stmt)
    {
        resolveRefs(retStmt.expr, s);
    }

    else if (auto throwStmt = cast(ThrowStmt)stmt)
    {
        resolveRefs(throwStmt.expr, s);
    }

    else if (auto tryStmt = cast(TryStmt)stmt)
    {
        resolveRefs(tryStmt.tryStmt, s);
        if (tryStmt.catchStmt)
        {
            s.addDecl(tryStmt.catchIdent);
            resolveRefs(tryStmt.catchStmt, s);
        }
        if (tryStmt.finallyStmt)
        {
            resolveRefs(tryStmt.finallyStmt, s);
        }
    }

    else if (auto exprStmt = cast(ExprStmt)stmt)
    {
        resolveRefs(exprStmt.expr, s);
    }

    else if (
        cast(BreakStmt)stmt ||
        cast(ContStmt)stmt)
    {
        // Do nothing
    }

    else
    {
        assert (false, "unhandled statement type:\n" ~ stmt.toString());
    }
}

/**
Resolve variable references in an expression
*/
void resolveRefs(ASTExpr expr, Scope s)
{
    // Function (closure) as an expression
    if (auto funExpr = cast(FunExpr)expr)
    {
        // Resolve variable declarations and
        // references in the nested function
        resolveVars(funExpr, s);
    }

    else if (auto binExpr = cast(BinOpExpr)expr)
    {
        resolveRefs(binExpr.lExpr, s);
        resolveRefs(binExpr.rExpr, s);
    }

    else if (auto unExpr = cast(UnOpExpr)expr)
    {
        resolveRefs(unExpr.expr, s);
    }

    else if (auto condExpr = cast(CondExpr)expr)
    {
        resolveRefs(condExpr.testExpr, s);
        resolveRefs(condExpr.trueExpr, s);
        resolveRefs(condExpr.falseExpr, s);
    }

    else if (auto callExpr = cast(CallExpr)expr)
    {
        resolveRefs(callExpr.base, s);
        foreach (e; callExpr.args)
            resolveRefs(e, s);
    }

    else if (auto newExpr = cast(NewExpr)expr)
    {
        resolveRefs(newExpr.base, s);
        foreach (e; newExpr.args)
            resolveRefs(e, s);
    }

    else if (auto indexExpr = cast(IndexExpr)expr)
    {
        resolveRefs(indexExpr.base, s);
        resolveRefs(indexExpr.index, s);
    }

    else if (auto arrayExpr = cast(ArrayExpr)expr)
    {
        foreach (e; arrayExpr.exprs)
            resolveRefs(e, s);
    }

    else if (auto objectExpr = cast(ObjectExpr)expr)
    {
        foreach (e; objectExpr.values)
            resolveRefs(e, s);
    }

    else if (auto identExpr = cast(IdentExpr)expr)
    {
        // Resolve this variable reference
        s.resolve(identExpr);

        //writefln("resolved ref: %s => %s", identExpr, identExpr.declNode);
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

