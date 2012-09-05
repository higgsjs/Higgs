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

module ir.ast;

import std.stdio;
import std.array;
import parser.ast;
import parser.parser;
import ir.ir;

/**
IR generation context
*/
class IRGenCtx
{
    /// Parent context
    IRGenCtx parent;

    /// IR function object
    IRFunction func;

    /// Block into which to insert
    IRBlock curBlock;

    /// Map of AST nodes to local variables
    LocalIdx[ASTNode] localMap;

    /// Next temporary index to allocate
    private LocalIdx nextTemp;

    /// Slot to store the output into, if applicable
    private LocalIdx outSlot;

    this(
        IRGenCtx parent,
        IRFunction func, 
        IRBlock block,
        LocalIdx[ASTNode] localMap,
        LocalIdx nextTemp,
        LocalIdx outSlot
    )
    {
        this.parent = parent;
        this.func = func;
        this.curBlock = block;
        this.localMap = localMap;
        this.nextTemp = nextTemp;
        this.outSlot = outSlot;
    }

    /**
    Create a context to compile a sub-expression into.
    This context will have its own temporary variables.
    */    
    IRGenCtx subCtx(IRBlock startBlock = null, LocalIdx outSlot = NULL_LOCAL)
    {
        if (startBlock is null)
            startBlock = curBlock;

        return new IRGenCtx(
            this,
            func,
            startBlock,
            localMap,
            nextTemp,
            outSlot
        );
    }

    /**
    Allocate a temporary slot
    */
    LocalIdx allocTemp()
    {
        if (nextTemp == func.numLocals)
            func.numLocals++;

        assert (nextTemp < func.numLocals);

        return nextTemp++;
    }

    /**
    Test if an output temp was set
    */
    bool outSet()
    {
        return outSlot != NULL_LOCAL;
    }

    /**
    Get a temporary slot to store output into
    */
    LocalIdx getOutSlot()
    {
        if (outSlot != NULL_LOCAL)
            return outSlot;

        outSlot = parent.allocTemp();

        return outSlot;
    }

    /**
    Set the output local slot
    */
    void setOutSlot(LocalIdx localIdx)
    {
        if (outSlot == localIdx)
            return;

        // If there is already an output slot
        if (outSlot != NULL_LOCAL)
        {
            // Move the value from the new slot to the current output slot
            auto moveInstr = addInstr(new IRInstr(&IRInstr.MOVE));
            moveInstr.args[0].localIdx = localIdx;
            moveInstr.outIdx = outSlot;
        }

        outSlot = localIdx;
    }

    /**
    Merge and continue insertion after a sub-context's end
    */
    void merge(IRGenCtx subCtx)
    {
        assert (subCtx.parent == this);

        curBlock = subCtx.curBlock;
    }

    /**
    Append a new instruction
    */
    IRInstr addInstr(IRInstr instr)
    {
        curBlock.addInstr(instr);
        return instr;
    }

    /**
    Get the last instruction added
    */
    IRInstr getLastInstr()
    {
        return curBlock.lastInstr;
    }
}

/**
Compile an AST program or function into an IR function
*/
IRFunction astToIR(FunExpr ast)
{
    assert (cast(FunExpr)ast || cast(ASTProgram)ast);

    // Get the function parameters and variables, if any
    auto params = ast.params;
    auto vars = ast.locals;

    // Create a function object
    auto func = new IRFunction(ast, params);

    LocalIdx[ASTNode] localMap;

    // Allocate the first local slots to parameters
    foreach (ident; params)
    {
        auto localIdx = cast(LocalIdx)localMap.length;
        localMap[ident] = localIdx;
    }

    // Allocate local slots to remaining local variables
    foreach (node; vars)
    {
        if (node !in localMap)
        {
            auto localIdx = cast(LocalIdx)localMap.length;
            localMap[node] = localIdx;
        }
    }

    writefln("local map len: %s", localMap.length);

    // Set the initial number of locals
    func.numLocals = cast(uint)localMap.length;

    // Create the function entry block
    auto entry = func.newBlock("entry");
    func.entryBlock = entry;

    // Create a context for the function body
    auto bodyCtx = new IRGenCtx(
        null,
        func, 
        entry,
        localMap,
        func.numLocals,
        0
    );

    // Compile the function body
    stmtToIR(ast.bodyStmt, bodyCtx);

    // If the body has nend return, compile a "return null;"
    auto lastInstr = bodyCtx.getLastInstr();
    if (lastInstr is null || lastInstr.type != &IRInstr.RET)
    {
        auto temp = bodyCtx.allocTemp();

        auto cstInstr = bodyCtx.addInstr(new IRInstr(&IRInstr.SET_NULL));
        cstInstr.outIdx = temp;

        auto retInstr = bodyCtx.addInstr(new IRInstr(&IRInstr.RET));
        retInstr.args[0].localIdx = temp;
    }

    return func;
}

void stmtToIR(ASTStmt stmt, IRGenCtx ctx)
{
    if (auto blockStmt = cast(BlockStmt)stmt)
    {
        foreach (s; blockStmt.stmts)
        {
            auto subCtx = ctx.subCtx();
            stmtToIR(s, subCtx);
            ctx.merge(subCtx);
        }
    }

    else if (auto varStmt = cast(VarStmt)stmt)
    {
        // TODO
        /*
        if (varStmt.initExpr)
        {
            assgToIR(
                varStmt.identExpr, 
                delegate void(IRGenCtx ctx)
                {
                    exprToIR(varStmt.initExpr, ctx);
                },
                ctx
            );
        }
        */
    }

    else if (auto ifStmt = cast(IfStmt)stmt)
    {
        // TODO

        assert (false);
    }

    /*  
    else if (auto whileStmt = cast(WhileStmt)stmt)
    {
    }

    else if (auto doStmt = cast(DoWhileStmt)stmt)
    {
    }

    else if (auto forStmt = cast(ForStmt)stmt)
    {
    }
    */

    // Return statement
    else if (auto retStmt = cast(ReturnStmt)stmt)
    {
        auto subCtx = ctx.subCtx();
        exprToIR(retStmt.expr, subCtx);
        ctx.merge(subCtx);

        auto retInstr = ctx.addInstr(new IRInstr(&IRInstr.RET));
        retInstr.args[0].localIdx = subCtx.getOutSlot();
    }

    /*
    else if (auto throwStmt = cast(ThrowStmt)stmt)
    {
    }

    else if (auto tryStmt = cast(TryStmt)stmt)
    {
    }
    */

    else if (auto exprStmt = cast(ExprStmt)stmt)
    {
        auto subCtx = ctx.subCtx();
        exprToIR(exprStmt.expr, subCtx);
        ctx.merge(subCtx);
    }

    else
    {
        assert (false, "unhandled statement type");
    }
}

void exprToIR(ASTExpr expr, IRGenCtx ctx)
{
    if (auto funExpr = cast(FunExpr)expr)
    {
        // TODO
    }

    else if (auto binExpr = cast(BinOpExpr)expr)
    {
        void genBinOp(IRInstr.Type* instrType)
        {
            auto lCtx = ctx.subCtx();
            exprToIR(binExpr.lExpr, lCtx);
            ctx.merge(lCtx);

            auto rCtx = ctx.subCtx();       
            exprToIR(binExpr.rExpr, rCtx);
            ctx.merge(rCtx);

            ctx.addInstr(new IRInstr(
                instrType,
                ctx.getOutSlot(), 
                lCtx.getOutSlot(),
                rCtx.getOutSlot()
            ));
        }

        auto op = binExpr.op;

        // Arithmetic operators
        if (op.str == "+")
            genBinOp(&IRInstr.ADD);
        else if (op.str == "-")
            genBinOp(&IRInstr.SUB);
        else if (op.str == "*")
            genBinOp(&IRInstr.MUL);
        else if (op.str == "/")
            genBinOp(&IRInstr.DIV);
        else if (op.str == "%")
            genBinOp(&IRInstr.MOD);

        // Bitwise operators
        else if (op.str == "&")
            genBinOp(&IRInstr.AND);
        else if (op.str == "|")
            genBinOp(&IRInstr.OR);
        else if (op.str == "^")
            genBinOp(&IRInstr.XOR);
        else if (op.str == "<<")
            genBinOp(&IRInstr.LSHIFT);
        else if (op.str == ">>")
            genBinOp(&IRInstr.RSHIFT);
        else if (op.str == ">>>")
            genBinOp(&IRInstr.URSHIFT);

        // String concatenation
        else if (op.str == "~")
            genBinOp(&IRInstr.CAT);

        // TODO: SE, NS

        // Comparison operators
        else if (op.str == "==")
            genBinOp(&IRInstr.CMP_EQ);
        else if (op.str == "!=")
            genBinOp(&IRInstr.CMP_NE);
        else if (op.str == "<")
            genBinOp(&IRInstr.CMP_LT);
        else if (op.str == "<=")
            genBinOp(&IRInstr.CMP_LE);
        else if (op.str == ">")
            genBinOp(&IRInstr.CMP_GT);
        else if (op.str == ">=")
            genBinOp(&IRInstr.CMP_GE);

        // Assignment expression
        else if (binExpr.op.str == "=")
        {
            assgToIR(
                binExpr.lExpr, 
                delegate void(IRGenCtx ctx)
                {
                    exprToIR(binExpr.rExpr, ctx);
                },
                ctx
            );
        }

        else
        {
            assert (false, "unhandled binary operator");
        }
    }

    else if (auto unExpr = cast(UnOpExpr)expr)
    {
        auto op = unExpr.op;

        /*
        if (op.str == '+')
        {
            // TODO: 0 + x;
        }

        else if (op.str == '-')
        {
            // TODO: 0 - x
        }

        // Bitwise negation
        else*/ if (op.str == "~")
        {
            auto lCtx = ctx.subCtx();
            exprToIR(unExpr.expr, lCtx);
            ctx.merge(lCtx);

            ctx.addInstr(new IRInstr(
                &IRInstr.NOT,
                ctx.getOutSlot(), 
                lCtx.getOutSlot()
            ));
        }

        // Boolean (logical) negation
        else if (op.str == "!")
        {
            auto lCtx = ctx.subCtx();
            exprToIR(unExpr.expr, lCtx);
            ctx.merge(lCtx);

            ctx.addInstr(new IRInstr(
                &IRInstr.BOOL_NOT,
                ctx.getOutSlot(), 
                lCtx.getOutSlot()
            ));
        }

        // Pre-incrementation (++x)
        else if (op.str == "++" && op.assoc == 'r')
        {
            assgToIR(
                unExpr.expr, 
                delegate void(IRGenCtx ctx)
                {
                    exprToIR(unExpr.expr, ctx);

                    auto cst = ctx.addInstr(IRInstr.intCst(ctx.allocTemp(), 1));

                    ctx.addInstr(new IRInstr(
                        &IRInstr.ADD,
                        ctx.getOutSlot(), 
                        ctx.getOutSlot(),
                        cst.outIdx
                    ));
                },
                ctx
            );
        }
        
        // Post-incrementation (x++)
        else if (op.str == "++" && op.assoc == 'l')
        {
            auto outSlot = ctx.allocTemp();

            auto vCtx = ctx.subCtx();
            exprToIR(unExpr.expr, vCtx);
            ctx.merge(vCtx);

            ctx.addInstr(new IRInstr(
                &IRInstr.MOVE,
                outSlot,
                vCtx.getOutSlot()
            ));

            ctx.setOutSlot(outSlot);

            auto aCtx = ctx.subCtx();
            assgToIR(
                unExpr.expr, 
                delegate void(IRGenCtx ctx)
                {
                    auto cst = ctx.addInstr(IRInstr.intCst(ctx.allocTemp(), 1));

                    ctx.addInstr(new IRInstr(
                        &IRInstr.ADD,
                        ctx.getOutSlot(), 
                        ctx.getOutSlot(),
                        cst.outIdx
                    ));
                },
                aCtx
            );
            ctx.merge(aCtx);

        }

        // TODO: Pre --

        // TODO: Post --

        else
        {
            assert (false, "unhandled unary operator");
        }
    }

    /*
    else if (auto condExpr = cast(CondExpr)expr)
    {
    }
    */

    else if (auto callExpr = cast(CallExpr)expr)
    {
        // TODO
        assert (false, "call unimplemented");
    }

    /*
    else if (auto indexExpr = cast(IndexExpr)expr)
    {
    }

    else if (auto arrayExpr = cast(ArrayExpr)expr)
    {
    }
    */

    else if (auto identExpr = cast(IdentExpr)expr)
    {
        // TODO: if id undeclared, must be global variable
        assert (identExpr.declNode !is null);

        LocalIdx varIdx = ctx.localMap[identExpr.declNode];

         // Set the variable as our output
        ctx.setOutSlot(varIdx);
    }

    else if (auto intExpr = cast(IntExpr)expr)
    {
        auto instr = ctx.addInstr(new IRInstr(&IRInstr.SET_INT));
        instr.args[0].intVal = intExpr.val;
        instr.outIdx = ctx.getOutSlot();
    }

    /*
        cast(FloatExpr)expr     ||
        cast(StringExpr)expr    ||
    */

    else if (cast(TrueExpr)expr)
    {
        auto instr = ctx.addInstr(new IRInstr(&IRInstr.SET_TRUE));
        instr.outIdx = ctx.getOutSlot();
    }

    else if (cast(FalseExpr)expr)
    {
        auto instr = ctx.addInstr(new IRInstr(&IRInstr.SET_FALSE));
        instr.outIdx = ctx.getOutSlot();
    }

    else if (cast(NullExpr)expr)
    {
        auto instr = ctx.addInstr(new IRInstr(&IRInstr.SET_NULL));
        instr.outIdx = ctx.getOutSlot();
    }

    else
    {
        assert (false, "unhandled expression type:\n" ~ expr.toString());
    }
}

/// Expression evaluation delegate function
alias void delegate(IRGenCtx ctx) ExprEvalFn;

/**
Generate IR for an assignment expression
*/
void assgToIR(ASTExpr lhsExpr, ExprEvalFn rhsExprFn, IRGenCtx ctx)
{
    // If the lhs is an identifier
    if (auto identExpr = cast(IdentExpr)lhsExpr)
    {
        // TODO: if id undeclared, must be global variable
        assert (identExpr.declNode !is null);

        LocalIdx varIdx = ctx.localMap[identExpr.declNode];

        writefln("var idx: %s", varIdx);

        auto rCtx = ctx.subCtx(null, varIdx);
        rhsExprFn(rCtx);
        ctx.merge(rCtx);

        // The local variable is our output
        ctx.setOutSlot(varIdx);
    }

    // If the lhs is a binary expression
    else if (auto binOpExpr = cast(BinOpExpr)lhsExpr)
    {
        // TODO
        assert (false, "not yet supported");
    }

    else
    {
        throw new ParseError("invalid lhs in assignment", lhsExpr.pos);
    }
}

