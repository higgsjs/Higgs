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
import std.algorithm;
import std.typecons;
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
    IRFunction fun;

    /// Block into which to insert
    IRBlock curBlock;

    /// Map of AST nodes to local variables
    LocalIdx[ASTNode]* localMap;

    /// Next temporary index to allocate
    private LocalIdx nextTemp;

    /// Slot to store the output into, if applicable
    private LocalIdx outSlot;

    alias Tuple!(
        wstring, "name", 
        IRBlock, "breakBlock", 
        IRBlock, "contBlock"
    ) LabelTargets;

    /// Target blocks for named statement labels
    LabelTargets[] labelTargets;

    this(
        IRGenCtx parent,
        IRFunction fun, 
        IRBlock block,
        LocalIdx[ASTNode]* localMap,
        LocalIdx nextTemp,
        LocalIdx outSlot
    )
    {
        this.parent = parent;
        this.fun = fun;
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
            fun,
            startBlock,
            localMap,
            nextTemp,
            outSlot
        );
    }

    /**
    Allocate a temporary slot in this context
    */
    LocalIdx allocTemp()
    {
        if (nextTemp == fun.numLocals)
            fun.numLocals++;

        assert (nextTemp < fun.numLocals);

        return nextTemp++;
    }

    /**
    Get a temporary slot to store output into
    */
    LocalIdx getOutSlot()
    {
        if (outSlot != NULL_LOCAL)
            return outSlot;

        // Allocate a slot in the parent context
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

        // If there is already a prescribed output slot
        if (outSlot != NULL_LOCAL)
        {
            // Move the value from the new slot to the current output slot
            auto moveInstr = addInstr(new IRInstr(&IRInstr.MOVE));
            moveInstr.args[0].localIdx = localIdx;
            moveInstr.outSlot = outSlot;
        }

        outSlot = localIdx;
    }

    /**
    Merge and continue insertion in a specific block
    */
    void merge(IRBlock block)
    {
        curBlock = block;
    }

    /**
    Merge and continue insertion after a sub-context's end
    */
    void merge(IRGenCtx subCtx)
    {
        assert (subCtx.parent == this);
        merge(subCtx.curBlock);
    }

    /**
    Method to register labels in the current context
    */
    void regLabels(IdentExpr[] labels, IRBlock breakBlock, IRBlock contBlock)
    {
        foreach (label; labels)
            labelTargets ~= LabelTargets(label.name, breakBlock, contBlock);

        // Implicit null label
        labelTargets ~= LabelTargets(null, breakBlock, contBlock);
    }

    /**
    Find the target block for a break statement
    */
    IRBlock getBreakTarget(IdentExpr ident)
    {
        foreach (target; labelTargets)
            if ((target.name is null && ident is null) || 
                target.name == ident.name)
                return target.breakBlock;

        if (parent is null)
            return null;

        return parent.getBreakTarget(ident);
    }

    /**
    Find the target block for a continue statement
    */
    IRBlock getContTarget(IdentExpr ident)
    {
        foreach (target; labelTargets)
            if ((target.name is null && ident is null) || 
                target.name == ident.name)
                return target.contBlock;

        if (parent is null)
            return null;

        return parent.getContTarget(ident);
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
IRFunction astToIR(FunExpr ast, IRFunction fun = null)
{
    assert (
        cast(FunExpr)ast || cast(ASTProgram)ast,
        "invalid AST function"
    );

    // If no IR function object was passed, create one
    if (fun is null)
        fun = new IRFunction(ast);

    assert (
        fun.entryBlock is null,
        "function already has an entry block"
    );

    // Create the function entry block
    auto entry = fun.newBlock("entry");
    fun.entryBlock = entry;

    // Get the function parameters and variables, if any
    auto params = ast.params;
    auto vars = ast.locals;

    // Map of ast nodes to local slots
    LocalIdx[ASTNode] localMap;

    // Create a context for the function body
    auto bodyCtx = new IRGenCtx(
        null,
        fun, 
        entry,
        &localMap,
        0,
        0
    );

    // Add the frame allocation instruction
    auto pushFrame = bodyCtx.addInstr(new IRInstr(&IRInstr.PUSH_FRAME));
    pushFrame.args[0].intVal = params.length;

    // Allocate the first local slots to parameters
    foreach (ident; params)
    {
        localMap[ident] = bodyCtx.allocTemp();
    }

    // Map temp slots for the hidden arguments
    fun.closSlot = bodyCtx.allocTemp();
    fun.thisSlot = bodyCtx.allocTemp();
    fun.argcSlot = bodyCtx.allocTemp();
    fun.raSlot   = bodyCtx.allocTemp();

    // Allocate slots for local variables and initialize them to undefined
    foreach (node; vars)
    {
        if (node !in localMap)
        {
            auto localSlot = bodyCtx.allocTemp();
            localMap[node] = localSlot;
            bodyCtx.addInstr(new IRInstr(&IRInstr.SET_UNDEF, localSlot));
        }
    }

    // Create closures for nested function declarations
    foreach (funDecl; ast.funDecls)
    {
        // Create an IR function object for the function
        auto subFun = new IRFunction(funDecl);

        // Create a closure of this function
        auto newClos = bodyCtx.addInstr(new IRInstr(&IRInstr.NEW_CLOS));
        newClos.outSlot = bodyCtx.allocTemp();
        newClos.args[0].fun = fun;

        // Store the closure temp in the local map
        localMap[funDecl.name] = newClos.outSlot;
    }

    //writefln("num locals: %s", fun.numLocals);

    // Compile the function body
    stmtToIR(ast.bodyStmt, bodyCtx);

    // If the body has nend return, compile a "return null;"
    auto lastInstr = bodyCtx.getLastInstr();
    if (lastInstr is null || lastInstr.type != &IRInstr.RET)
    {
        auto temp = bodyCtx.allocTemp();
        auto cstInstr = bodyCtx.addInstr(new IRInstr(&IRInstr.SET_UNDEF, temp));
        auto retInstr = bodyCtx.addInstr(new IRInstr(&IRInstr.RET));
        retInstr.args[0].localIdx = temp;
    }

    // Set the local count in the frame allocation instruction
    pushFrame.args[1].intVal = fun.numLocals;

    /// Function to translate (reverse) local indices
    void translLocal(ref LocalIdx localIdx)
    {
        localIdx = fun.numLocals - 1 - localIdx;
    }

    // Translate the hidden argument slots
    translLocal(fun.closSlot);
    translLocal(fun.thisSlot);
    translLocal(fun.argcSlot);
    translLocal(fun.raSlot);

    // For each instruction
    for (auto block = fun.firstBlock; block !is null; block = block.next)
    {
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
        {
            // Translate the output index
            if (instr.type.output)
            {
                translLocal(instr.outSlot);
            }

            // Translate the local argument indices
            auto argTypes = instr.type.argTypes;
            for (size_t i = 0; i < argTypes.length; ++i)
            {
                if (argTypes[i] == IRInstr.Arg.LOCAL)
                    translLocal(instr.args[i].localIdx);
            }

            // Set the local count and return address slot in return instructions
            if (instr.type == &IRInstr.RET)
            {
                instr.args[1].localIdx = fun.raSlot;
                instr.args[2].intVal = fun.numLocals;
            }
        }
    }

    // Return the IR function object
    return fun;
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
        for (size_t i = 0; i < varStmt.identExprs.length; ++i)
        {
            auto ident = varStmt.identExprs[i];
            auto init = varStmt.initExprs[i];

            if (init is null)
                continue;

            assgToIR(
                ident, 
                delegate void(IRGenCtx ctx)
                {
                    exprToIR(init, ctx);
                },
                ctx
            );
        }
    }

    else if (auto ifStmt = cast(IfStmt)stmt)
    {
        // Compile the true statement
        auto trueBlock = ctx.fun.newBlock("if_true");
        auto trueCtx = ctx.subCtx(trueBlock);
        stmtToIR(ifStmt.trueStmt, trueCtx);

        // Compile the false statement
        auto falseBlock = ctx.fun.newBlock("if_false");
        auto falseCtx = ctx.subCtx(falseBlock);
        stmtToIR(ifStmt.falseStmt, falseCtx);

        // Create the join block and patch jumps to it
        auto joinBlock = ctx.fun.newBlock("if_join");
        trueCtx.addInstr(IRInstr.jump(joinBlock));
        falseCtx.addInstr(IRInstr.jump(joinBlock));

        // Evaluate the test expression
        auto exprCtx = ctx.subCtx();
        exprToIR(ifStmt.testExpr, exprCtx);
        ctx.merge(exprCtx);

        // Convert the expression value to a boolean
        auto boolInstr = ctx.addInstr(new IRInstr(
            &IRInstr.BOOL_VAL,
            ctx.allocTemp(),
            exprCtx.getOutSlot(),           
        ));

        // If the expresson is true, jump
        ctx.addInstr(new IRInstr(
            &IRInstr.JUMP_TRUE,
            boolInstr.outSlot,
            trueBlock
        ));

        // Jump to the false statement
        ctx.addInstr(IRInstr.jump(falseBlock));

        // Continue code generation in the join block
        ctx.merge(joinBlock);
    }
  
    else if (auto whileStmt = cast(WhileStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto testBlock = ctx.fun.newBlock("while_test");
        auto bodyBlock = ctx.fun.newBlock("while_body");
        auto exitBlock = ctx.fun.newBlock("while_exit");

        // Register the loop labels, if any
        ctx.regLabels(stmt.labels, exitBlock, testBlock);

        // Jump to the test block
        ctx.addInstr(IRInstr.jump(testBlock));

        // Evaluate the test expression
        auto testCtx = ctx.subCtx(testBlock);
        exprToIR(whileStmt.testExpr, testCtx);

        // Convert the expression value to a boolean
        auto boolInstr = testCtx.addInstr(new IRInstr(
            &IRInstr.BOOL_VAL,
            testCtx.allocTemp(),
            testCtx.getOutSlot(),           
        ));

        // If the expresson is true, jump to the loop body
        testCtx.addInstr(new IRInstr(
            &IRInstr.JUMP_TRUE,
            boolInstr.outSlot,
            bodyBlock
        ));
        testCtx.addInstr(IRInstr.jump(exitBlock));

        // Compile the loop body statement
        auto bodyCtx = ctx.subCtx(bodyBlock);
        stmtToIR(whileStmt.bodyStmt, bodyCtx);

        // Jump to the loop test
        bodyCtx.addInstr(IRInstr.jump(testBlock));

        // Continue code generation in the exit block
        ctx.merge(exitBlock);
    }

    else if (auto doStmt = cast(DoWhileStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto bodyBlock = ctx.fun.newBlock("do_body");
        auto testBlock = ctx.fun.newBlock("do_test");
        auto exitBlock = ctx.fun.newBlock("do_exit");

        // Register the loop labels, if any
        ctx.regLabels(stmt.labels, exitBlock, testBlock);

        // Jump to the body block
        ctx.addInstr(IRInstr.jump(bodyBlock));

        // Compile the loop body statement
        auto bodyCtx = ctx.subCtx(bodyBlock);
        stmtToIR(doStmt.bodyStmt, bodyCtx);

        // Jump to the loop test
        bodyCtx.addInstr(IRInstr.jump(testBlock));

        // Evaluate the test expression
        auto testCtx = ctx.subCtx(testBlock);
        exprToIR(doStmt.testExpr, testCtx);

        // Convert the expression value to a boolean
        auto boolInstr = testCtx.addInstr(new IRInstr(
            &IRInstr.BOOL_VAL,
            testCtx.allocTemp(),
            testCtx.getOutSlot(),           
        ));

        // If the expresson is true, jump to the loop body
        testCtx.addInstr(new IRInstr(
            &IRInstr.JUMP_TRUE,
            boolInstr.outSlot,
            bodyBlock
        ));
        testCtx.addInstr(IRInstr.jump(exitBlock));

        // Continue code generation in the exit block
        ctx.merge(exitBlock);
    }

    else if (auto forStmt = cast(ForStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto testBlock = ctx.fun.newBlock("for_test");
        auto bodyBlock = ctx.fun.newBlock("for_body");
        auto incrBlock = ctx.fun.newBlock("for_incr");
        auto exitBlock = ctx.fun.newBlock("for_exit");

        // Register the loop labels, if any
        ctx.regLabels(stmt.labels, exitBlock, incrBlock);

        // Compile the init statement
        auto initCtx = ctx.subCtx();
        stmtToIR(forStmt.initStmt, initCtx);
        ctx.merge(initCtx);

        // Jump to the test block
        ctx.addInstr(IRInstr.jump(testBlock));

        // Evaluate the test expression
        auto testCtx = ctx.subCtx(testBlock);
        exprToIR(forStmt.testExpr, testCtx);

        // Convert the expression value to a boolean
        auto boolInstr = testCtx.addInstr(new IRInstr(
            &IRInstr.BOOL_VAL,
            testCtx.allocTemp(),
            testCtx.getOutSlot(),           
        ));

        // If the expresson is true, jump to the loop body
        testCtx.addInstr(new IRInstr(
            &IRInstr.JUMP_TRUE,
            boolInstr.outSlot,
            bodyBlock
        ));
        testCtx.addInstr(IRInstr.jump(exitBlock));

        // Compile the loop body statement
        auto bodyCtx = ctx.subCtx(bodyBlock);
        stmtToIR(forStmt.bodyStmt, bodyCtx);

        // Jump to the increment block
        bodyCtx.addInstr(IRInstr.jump(incrBlock));

        // Compile the increment expression
        auto incrCtx = ctx.subCtx(incrBlock);
        exprToIR(forStmt.incrExpr, incrCtx);

        // Jump to the loop test
        incrCtx.addInstr(IRInstr.jump(testBlock));

        // Continue code generation in the exit block
        ctx.merge(exitBlock);
    }

    // Break statement
    else if (auto breakStmt = cast(BreakStmt)stmt)
    {
        auto block = ctx.getBreakTarget(breakStmt.label);

        if (block is null)
            throw new ParseError("break statement with no target", stmt.pos);

        ctx.addInstr(IRInstr.jump(block));
    }

    // Continue statement
    else if (auto contStmt = cast(ContStmt)stmt)
    {
        auto block = ctx.getContTarget(contStmt.label);

        if (block is null)
            throw new ParseError("continue statement with no target", stmt.pos);

        ctx.addInstr(IRInstr.jump(block));
    }

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
    // Function expression
    if (auto funExpr = cast(FunExpr)expr)
    {
        // If this is not a function declaration
        if (countUntil(ctx.fun.ast.funDecls, funExpr) == -1)
        {
            // Create an IR function object for the function
            auto fun = new IRFunction(funExpr);

            // Create a closure of this function
            auto newClos = ctx.addInstr(new IRInstr(&IRInstr.NEW_CLOS));
            newClos.outSlot = ctx.getOutSlot();
            newClos.args[0].fun = fun;
        }
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

        // Comparison operators
        else if (op.str == "===")
            genBinOp(&IRInstr.CMP_SE);
        else if (op.str == "!==")
            genBinOp(&IRInstr.CMP_NS);
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

        if (op.str == "+")
        {
            auto outSlot = ctx.getOutSlot();

            auto cst = ctx.addInstr(IRInstr.intCst(ctx.allocTemp(), 0));

            auto subCtx = ctx.subCtx();       
            exprToIR(unExpr.expr, subCtx);
            ctx.merge(subCtx);

            ctx.addInstr(new IRInstr(
                &IRInstr.ADD,
                outSlot, 
                cst.outSlot,
                subCtx.getOutSlot()
            ));
        }

        else if (op.str == "-")
        {
            auto outSlot = ctx.getOutSlot();

            auto cst = ctx.addInstr(IRInstr.intCst(ctx.allocTemp(), 0));

            auto subCtx = ctx.subCtx();       
            exprToIR(unExpr.expr, subCtx);
            ctx.merge(subCtx);

            ctx.addInstr(new IRInstr(
                &IRInstr.SUB,
                outSlot, 
                cst.outSlot,
                subCtx.getOutSlot()
            ));
        }

        // Bitwise negation
        else if (op.str == "~")
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

        // Pre-incrementation and pre-decrementation (++x, --x)
        else if ((op.str == "++" || op.str == "--") && op.assoc == 'r')
        {
            assgToIR(
                unExpr.expr, 
                delegate void(IRGenCtx ctx)
                {
                    exprToIR(unExpr.expr, ctx);

                    auto cst = ctx.addInstr(IRInstr.intCst(ctx.allocTemp(), 1));

                    ctx.addInstr(new IRInstr(
                        (op.str == "++")? &IRInstr.ADD:&IRInstr.SUB,
                        ctx.getOutSlot(), 
                        ctx.getOutSlot(),
                        cst.outSlot
                    ));
                },
                ctx
            );
        }
        
        // Post-incrementation and post-decrementation (x++, x--)
        else if ((op.str == "++" || op.str == "--") && op.assoc == 'l')
        {
            // Evaluate the subexpression
            auto vCtx = ctx.subCtx();
            exprToIR(unExpr.expr, vCtx);
            ctx.merge(vCtx);

            // Save the current value of the subexpression
            auto valTemp = ctx.allocTemp();
            ctx.addInstr(new IRInstr(
                &IRInstr.MOVE,
                valTemp,
                vCtx.getOutSlot()
            ));

            // Perform the incrementation/decrementation and assignment
            auto aCtx = ctx.subCtx();
            assgToIR(
                unExpr.expr, 
                delegate void(IRGenCtx ctx)
                {
                    auto cst = ctx.addInstr(IRInstr.intCst(ctx.allocTemp(), 1));

                    ctx.addInstr(new IRInstr(
                        (op.str == "++")? &IRInstr.ADD:&IRInstr.SUB,
                        ctx.getOutSlot(), 
                        ctx.getOutSlot(),
                        cst.outSlot
                    ));
                },
                aCtx
            );
            ctx.merge(aCtx);

            // Move the saved value into our output slot
            ctx.addInstr(new IRInstr(
                &IRInstr.MOVE,
                ctx.getOutSlot(),
                valTemp
            ));
        }

        else
        {
            assert (false, "unhandled unary operator");
        }
    }

    else if (auto condExpr = cast(CondExpr)expr)
    {
        // Create the true, false and join blocks
        auto trueBlock  = ctx.fun.newBlock("cond_true");
        auto falseBlock = ctx.fun.newBlock("cond_false");
        auto joinBlock  = ctx.fun.newBlock("cond_join");

        // Get the output slot
        auto outSlot = ctx.getOutSlot();

        // Evaluate the test expression
        auto exprCtx = ctx.subCtx();
        exprToIR(condExpr.testExpr, exprCtx);
        ctx.merge(exprCtx);

        // Convert the expression value to a boolean
        auto boolInstr = ctx.addInstr(new IRInstr(
            &IRInstr.BOOL_VAL,
            ctx.allocTemp(),
            exprCtx.getOutSlot(),           
        ));

        // If the expresson is true, jump
        ctx.addInstr(new IRInstr(
            &IRInstr.JUMP_TRUE,
            boolInstr.outSlot,
            trueBlock
        ));
        ctx.addInstr(IRInstr.jump(falseBlock));

        // Compile the true expression and assign into the output slot
        auto trueCtx = ctx.subCtx(trueBlock, outSlot);
        exprToIR(condExpr.trueExpr, trueCtx);
        trueCtx.addInstr(IRInstr.jump(joinBlock));

        // Compile the false expression and assign into the output slot
        auto falseCtx = ctx.subCtx(falseBlock, outSlot);
        exprToIR(condExpr.falseExpr, falseCtx);
        falseCtx.addInstr(IRInstr.jump(joinBlock));

        // Continue code generation in the join block
        ctx.merge(joinBlock);
    }

    // Function call expression
    else if (auto callExpr = cast(CallExpr)expr)
    {
        auto baseExpr = callExpr.base;
        auto argExprs = callExpr.args;

        LocalIdx thisSlot;

        // If the base expression is a member expression
        if (auto indexExpr = cast(IndexExpr)baseExpr)
        {
            // TODO
            // this value is the index expression base
            assert (false, "member call unimplemented");
        }

        else
        {
            // TODO: global object
            // The this value is the global object
            thisSlot = ctx.allocTemp();
            ctx.addInstr(new IRInstr(&IRInstr.SET_UNDEF, thisSlot));
        }

        // Evaluate the base expression
        auto baseCtx = ctx.subCtx();       
        exprToIR(baseExpr, baseCtx);
        ctx.merge(baseCtx);

        // Evaluate the arguments
        auto argSlots = new LocalIdx[argExprs.length];
        for (size_t i = 0; i < argExprs.length; ++i)
        {
            auto argCtx = ctx.subCtx();       
            exprToIR(argExprs[i], argCtx);
            ctx.merge(argCtx);
            argSlots[i] = argCtx.outSlot;
        }

        // Set the call arguments
        for (size_t i = 0; i < argSlots.length; ++i)
        {
            auto argInstr = ctx.addInstr(new IRInstr(&IRInstr.SET_ARG));
            argInstr.args[0].localIdx = argSlots[i];
            argInstr.args[1].intVal = i;
        }

        // Add the call instruction
        // CALL <fnLocal> <thisArg> <numArgs>
        auto callInstr = ctx.addInstr(new IRInstr(&IRInstr.CALL));
        callInstr.args[0].localIdx = baseCtx.outSlot;
        callInstr.args[1].localIdx = thisSlot;
        callInstr.args[2].intVal = argExprs.length;

        // Get the return value from this call
        ctx.addInstr(new IRInstr(&IRInstr.GET_RET, ctx.getOutSlot()));
    }

    /*
    else if (auto indexExpr = cast(IndexExpr)expr)
    {
    }

    else if (auto arrayExpr = cast(ArrayExpr)expr)
    {
    }
    */

    // Identifier/variable reference
    else if (auto identExpr = cast(IdentExpr)expr)
    {
        // If the variable is global
        if (identExpr.declNode is null)
        {
            // TODO: if id undeclared, must be global variable
            assert (identExpr.declNode !is null);
        }

        // The variable is local
        else
        {
            assert (
                identExpr.declNode in *ctx.localMap,
                "variable declaration not in local map"
            );

            // Set the variable's local slot as our output
            LocalIdx varIdx = (*ctx.localMap)[identExpr.declNode];
            ctx.setOutSlot(varIdx);
        }
    }

    else if (auto intExpr = cast(IntExpr)expr)
    {
        ctx.addInstr(IRInstr.intCst(
            ctx.getOutSlot(),
            intExpr.val
        ));
    }

    else if (auto floatExpr = cast(FloatExpr)expr)
    {
        ctx.addInstr(IRInstr.floatCst(
            ctx.getOutSlot(),
            floatExpr.val
        ));
    }

    // TODO
    // TODO: string expression
    // TODO
    //cast(StringExpr)expr

    else if (cast(TrueExpr)expr)
    {
        ctx.addInstr(new IRInstr(&IRInstr.SET_TRUE, ctx.getOutSlot()));
    }

    else if (cast(FalseExpr)expr)
    {
        ctx.addInstr(new IRInstr(&IRInstr.SET_FALSE, ctx.getOutSlot()));
    }

    else if (cast(NullExpr)expr)
    {
        ctx.addInstr(new IRInstr(&IRInstr.SET_NULL, ctx.getOutSlot()));
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
        // If the variable is global
        if (identExpr.declNode is null)
        {
            // TODO: if id undeclared, must be global variable
            assert (identExpr.declNode !is null, "global vars unimplemented");
        }

        // The variable is local
        else
        {
            LocalIdx varIdx = (*ctx.localMap)[identExpr.declNode];

            // Compute the right expression and assign it into the variable
            auto rCtx = ctx.subCtx(null, varIdx);
            rhsExprFn(rCtx);
            ctx.merge(rCtx);

            // The local variable is our output
            ctx.setOutSlot(varIdx);
        }
    }

    // If the lhs is an array indexing expression (e.g.: a[b])
    else if (auto indexExpr = cast(IndexExpr)lhsExpr)
    {
        // TODO
        assert (false, "not yet supported");

        // TODO: array indexing









    }

    else
    {
        throw new ParseError("invalid lhs in assignment", lhsExpr.pos);
    }
}

