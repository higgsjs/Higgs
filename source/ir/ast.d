/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

import std.stdint;
import std.stdio;
import std.array;
import std.algorithm;
import std.typecons;
import std.conv;
import parser.ast;
import parser.parser;
import ir.ir;
import ir.ops;
import ir.iir;
import interp.layout;

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

    /// Map of identifiers to values (local variables)
    IRValue[IdentExpr] localMap;

    alias Tuple!(
        wstring, "name",
        IRGenCtx[]*, "breakCtxs", 
        IRGenCtx[]*, "contCtxs"
    ) LabelTargets;

    /// Target blocks for named statement labels
    LabelTargets[] labelTargets;

    /// Catch statement block
    IRBlock catchBlock;

    /// Catch statement identifier
    IdentExpr catchIdent;

    /// Finally statement
    ASTStmt fnlStmt;

    /// Finally statement and context pair
    alias Tuple!(
        ASTStmt, "stmt",
        IRGenCtx, "ctx"
    ) FnlInfo;

    /**
    Code generation context constructor
    */
    this(
        IRGenCtx parent,
        IRFunction fun, 
        IRBlock block,
        IRValue[IdentExpr] localMap
    )
    {
        this.parent = parent;
        this.fun = fun;
        this.curBlock = block;
        this.localMap = localMap;
    }

    /**
    Create a sub-context of this context
    */
    IRGenCtx subCtx(IRBlock startBlock =  null)
    {
        auto sub = new IRGenCtx(
            this, 
            this.fun,
            startBlock? startBlock:this.curBlock, 
            this.localMap.dup
        );

        return sub;
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
        this.curBlock = subCtx.curBlock;
        this.localMap = subCtx.localMap;

        subCtx.curBlock = null;
        subCtx.localMap = null;
    }

    /**
    Append a new instruction
    */
    IRInstr addInstr(IRInstr instr)
    {
        assert (
            curBlock !is null,
            "current block is null, context likely absorbed in merge"
        );

        // If the current block already has a branch, do nothing
        if (curBlock.lastInstr && curBlock.lastInstr.opcode.isBranch)
            return instr;

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

    /**
    Register labels in the current context
    */
    void regLabels(IdentExpr[] labels, IRGenCtx[]* breakCtxs, IRGenCtx[]* contCtxs)
    {
        foreach (label; labels)
            labelTargets ~= LabelTargets(label.name, breakCtxs, contCtxs);

        // Implicit null label
        labelTargets ~= LabelTargets(null, breakCtxs, contCtxs);
    }

    /**
    Find the context list for a break statement
    */
    IRGenCtx[]* getBreakTarget(IdentExpr ident, FnlInfo[]* stmts)
    {
        foreach (target; labelTargets)
            if ((ident is null && target.name is null) || 
                (ident !is null && target.name == ident.name))
                return target.breakCtxs;

        if (fnlStmt)
            *stmts ~= FnlInfo(fnlStmt, parent);

        if (parent is null)
            return null;

        return parent.getBreakTarget(ident, stmts);
    }

    /**
    Find the context list for a continue statement
    */
    IRGenCtx[]* getContTarget(IdentExpr ident, FnlInfo[]* stmts)
    {
        foreach (target; labelTargets)
        {
            if (target.contCtxs is null)
                continue;

            if ((ident is null && target.name is null) || 
                (ident !is null && target.name == ident.name))
                return target.contCtxs;
        }

        if (fnlStmt)
            *stmts ~= FnlInfo(fnlStmt, parent);

        if (parent is null)
            return null;

        return parent.getContTarget(ident, stmts);
    }

    /**
    Get all englobing finally statements
    */
    void getFnlStmts(FnlInfo[]* stmts)
    {
        if (fnlStmt)
            *stmts ~= FnlInfo(fnlStmt, parent);

        if (parent)
            parent.getFnlStmts(stmts);   
    }

    /**
    Get the englobing catch block and catch variable, if defined
    */
    auto getCatchInfo(FnlInfo[]* stmts)
    {
        if (catchIdent !is null)
        {
            return new Tuple!(IdentExpr, "ident", IRBlock, "block")(catchIdent, catchBlock);
        }

        if (fnlStmt)
            *stmts ~= FnlInfo(fnlStmt, parent);

        if (parent)
            return parent.getCatchInfo(stmts);

        return null;
    }

    /**
    Insert a jump in the current block
    */
    BranchDesc jump(IRBlock block)
    {
        auto jump = this.addInstr(new IRInstr(&JUMP));
        assert (jump.block is this.curBlock);
        auto desc = jump.setTarget(0, block);
        return desc;
    }

    /**
    Insert a conditional branch in the current block
    */
    IRInstr ifTrue(IRValue arg0, IRBlock trueBlock, IRBlock falseBlock)
    {
        auto ift = this.addInstr(new IRInstr(&IF_TRUE, arg0));
        ift.setTarget(0, trueBlock);
        ift.setTarget(1, falseBlock);
        return ift;
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

    // Create the local variable map
    IRValue[IdentExpr] localMap;

    // Create a context for the function body
    auto bodyCtx = new IRGenCtx(
        null,
        fun, 
        entry,
        localMap
    );

    // Create values for the hidden arguments
    fun.raVal   = new FunParam("ra"  , 0);
    fun.closVal = new FunParam("clos", 1);
    fun.thisVal = new FunParam("this", 2);
    fun.argcVal = new FunParam("argc", 3);

    // Create values for the visible function parameters
    for (size_t i = 0; i < ast.params.length; ++i)
    {
        auto argIdx = 4 + i;
        auto ident = ast.params[i];

        auto paramVal = new FunParam(ident.name, argIdx);
        fun.paramMap[ident] = paramVal;
        localMap[ident] = paramVal;
        entry.addPhi(paramVal);
    }

    // Allocate slots for local variables
    foreach (ident; ast.locals)
    {
        // If this variable does not escape and is not a parameter
        if (ident !in ast.escpVars && ast.params.countUntil(ident) == -1)
        {
            localMap[ident] = IRConst.undefCst;
        }
    }

    // Initialize global variable declarations to undefined
    if (auto unit = cast(ASTProgram)ast)
    {
        foreach (ident; unit.globals)
        {
            auto setInstr = bodyCtx.addInstr(new IRInstr(
                &SET_GLOBAL, 
                new IRString(ident.name),
                IRConst.undefCst,
                new IRCachedIdx()
            ));
        }
    }

    // If the function uses the arguments object
    if (ast.usesArguments)
    {
        //auto argObjSlot = bodyCtx.allocTemp();
        //fun.localMap[ast.argObjIdent] = argObjSlot;

        // FIXME
        /*
        // Create the "arguments" array
        auto linkInstr = subCtx.addInstr(IRInstr.makeLink(subCtx.allocTemp()));
        auto protoInstr = subCtx.addInstr(new IRInstr(&GET_ARR_PROTO, subCtx.allocTemp()));
        auto arrInstr = genRtCall(
            subCtx, 
            "newArr",
            argObjSlot,
            [linkInstr.outSlot, protoInstr.outSlot, fun.argcSlot]
        );
        */
        
        // FIXME
        /*
        // Set the "callee" property
        auto calleeStr = subCtx.addInstr(IRInstr.strCst(subCtx.allocTemp(), "callee"));
        auto setInstr = genRtCall(
            subCtx, 
            "setProp",
            NULL_LOCAL,
            [argObjSlot, calleeStr.outSlot, fun.closSlot]
        );
        */

        // FIXME
        /*
        // Allocate and initialize the loop counter variable
        auto idxSlot = subCtx.allocTemp();
        subCtx.addInstr(IRInstr.intCst(idxSlot, 0));
        */

        auto testBlock = fun.newBlock("arg_test");
        auto loopBlock = fun.newBlock("arg_loop");
        auto exitBlock = fun.newBlock("arg_exit");

        // Jump to the test block
        //subCtx.addInstr(IRInstr.jump(testBlock));

        // FIXME
        /*
        // Branch based on the index
        auto cmpInstr = testCtx.addInstr(new IRInstr(&LT_I32, testCtx.allocTemp(), idxSlot, fun.argcSlot));
        testCtx.addInstr(IRInstr.ifTrue(cmpInstr.outSlot, loopBlock, exitBlock));

        // Copy an argument into the array
        auto getInstr = loopCtx.addInstr(new IRInstr(&GET_ARG, loopCtx.allocTemp(), idxSlot));
        genRtCall(
            loopCtx, 
            "setArrElem",
            NULL_LOCAL,
            [arrInstr.outSlot, idxSlot, getInstr.outSlot]
        );

        // Increment the loop index and jump to the test block
        auto oneCst = loopCtx.addInstr(IRInstr.intCst(loopCtx.allocTemp(), 1));
        loopCtx.addInstr(new IRInstr(&ADD_I32, idxSlot, idxSlot, oneCst.outSlot));
        loopCtx.addInstr(IRInstr.jump(testBlock));
        */

        bodyCtx.merge(exitBlock);
    }

    // Get the cell pointers for captured closure variables
    foreach (idx, ident; ast.captVars)
    {
        auto getVal = genRtCall(
            bodyCtx, 
            "clos_get_cell",
            [fun.closVal, cast(IRValue)IRConst.int32Cst(cast(int32_t)idx)]
        );

        fun.cellMap[ident] = getVal;
    }

    // Create closure cells for the escaping variables
    foreach (ident, bval; ast.escpVars)
    {
        // If this variable is not captured from another function
        if (ident !in fun.cellMap)
        {
            // Allocate a closure cell for the variable
            auto allocInstr = genRtCall(
                bodyCtx, 
                "makeClosCell",
                []
            );
            fun.cellMap[ident] = allocInstr;

            // If this variable is local
            if (ident in localMap)
            {
                genRtCall(
                    bodyCtx, 
                    "setCellVal", 
                    [allocInstr, localMap[ident]]
                );
            }
        }
    }

    // Create closures for nested function declarations
    foreach (funDecl; ast.funDecls)
    {
        // Create an IR function object for the function
        auto subFun = new IRFunction(funDecl);

        // Store the binding for the function
        assgToIR(
            funDecl.name,
            null,
            delegate IRValue(IRGenCtx ctx)
            {
                // Create a closure of this function
                auto newClos = ctx.addInstr(new IRInstr(
                    &NEW_CLOS,
                    new IRFunPtr(subFun),
                    new IRLinkIdx(),
                    new IRLinkIdx()
                ));

                // Set the closure cells for the captured variables
                foreach (idx, ident; subFun.ast.captVars)
                {
                    auto idxCst = IRConst.int32Cst(cast(int32_t)idx);
                    genRtCall(
                        ctx, 
                        "clos_set_cell",
                        [newClos, idxCst, fun.cellMap[ident]]
                    );
                }

                return newClos;
            },
            bodyCtx
        );
    }

    // Compile the function body
    stmtToIR(ast.bodyStmt, bodyCtx);

    // If the body has no final return, compile a "return undefined;"
    auto lastInstr = bodyCtx.getLastInstr();
    if (lastInstr is null || lastInstr.opcode != &RET)
    {
        bodyCtx.addInstr(new IRInstr(&RET, IRConst.undefCst));
    }

    //writeln(fun.toString());

    // Return the IR function object
    return fun;
}

void stmtToIR(ASTStmt stmt, IRGenCtx ctx)
{
    if (auto blockStmt = cast(BlockStmt)stmt)
    {
        foreach (s; blockStmt.stmts)
        {
            stmtToIR(s, ctx);
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
                null,
                delegate IRValue(IRGenCtx ctx)
                {
                    return exprToIR(init, ctx);
                },
                ctx
            );
        }
    }

    /*
    else if (auto ifStmt = cast(IfStmt)stmt)
    {
        // Compile the true statement
        auto trueBlock = ctx.fun.newBlock("if_true");
        auto trueCtx = ctx.subCtx(false, NULL_LOCAL, trueBlock);
        stmtToIR(ifStmt.trueStmt, trueCtx);

        // Compile the false statement
        auto falseBlock = ctx.fun.newBlock("if_false");
        auto falseCtx = ctx.subCtx(false, NULL_LOCAL, falseBlock);
        stmtToIR(ifStmt.falseStmt, falseCtx);

        // Create the join block and patch jumps to it
        auto joinBlock = ctx.fun.newBlock("if_join");
        trueCtx.addInstr(IRInstr.jump(joinBlock));
        falseCtx.addInstr(IRInstr.jump(joinBlock));

        // Evaluate the test expression
        auto exprCtx = ctx.subCtx(true);
        exprToIR(ifStmt.testExpr, exprCtx);
        ctx.merge(exprCtx);

        // Get the last instruction of the current block
        auto lastInstr = ctx.curBlock.lastInstr;

        // If this is a branch inline IR expression
        if (isBranchIIR(ifStmt.testExpr) && lastInstr && lastInstr.opcode.isBranch)
        {
            assert (
                lastInstr.target is null,
                "iir target already set"
            );

            // Set branch targets for the instruction
            lastInstr.target = trueBlock;
            lastInstr.excTarget = falseBlock;
        }

        else
        {
            // Convert the expression value to a boolean
            auto boolSlot = genBoolEval(
                ctx, 
                ifStmt.testExpr, 
                exprCtx.getOutSlot
            );

            // Branch based on the boolean value
            ctx.addInstr(IRInstr.ifTrue(
                boolSlot,
                trueBlock,
                falseBlock
            ));
        }

        // Continue code generation in the join block
        ctx.merge(joinBlock);
    }
    */  

    else if (auto whileStmt = cast(WhileStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto testBlock = ctx.fun.newBlock("while_test");
        auto bodyBlock = ctx.fun.newBlock("while_body");
        auto exitBlock = ctx.fun.newBlock("while_exit");

        // Create a context for the loop entry (the loop test)
        auto testCtx = createLoopEntry(
            ctx,
            testBlock
        );

        // Store a copy of the loop entry phi nodes
        auto entryLocals = testCtx.localMap.dup;        

        // Register the loop labels, if any
        IRGenCtx[] brkCtxList = [];
        IRGenCtx[] cntCtxList = [];
        testCtx.regLabels(stmt.labels, &brkCtxList, &cntCtxList);

        // Compile the loop test in the entry context
        auto testVal = exprToIR(whileStmt.testExpr, testCtx);

        // Convert the expression value to a boolean
        auto boolVal = genBoolEval(
            testCtx, 
            whileStmt.testExpr, 
            testVal
        );

        // If the expresson is true, jump to the loop body
        testCtx.ifTrue(boolVal, bodyBlock, exitBlock);

        // Compile the loop body statement
        auto bodyCtx = testCtx.subCtx(bodyBlock);
        stmtToIR(whileStmt.bodyStmt, bodyCtx);

        // Add the test exit to the entry context list
        brkCtxList ~= testCtx.subCtx();

        // Add the body exit to the continue context list
        cntCtxList ~= bodyCtx.subCtx();

        // Merge the break contexts into the loop exit
        auto loopExitCtx = mergeContexts(
            ctx,
            brkCtxList,
            exitBlock
        );

        // Merge the continue contexts with the loop entry
        mergeLoopEntry(
            cntCtxList,
            entryLocals,
            testBlock
        );

        // Continue code generation after the loop exit
        ctx.merge(loopExitCtx);
    }

    /*
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
        auto bodyCtx = ctx.subCtx(false, NULL_LOCAL, bodyBlock);
        stmtToIR(doStmt.bodyStmt, bodyCtx);

        // Jump to the loop test
        bodyCtx.addInstr(IRInstr.jump(testBlock));

        // Evaluate the test expression
        auto testCtx = ctx.subCtx(true, NULL_LOCAL, testBlock);
        exprToIR(doStmt.testExpr, testCtx);

        // Convert the expression value to a boolean
        auto boolSlot = genBoolEval(
            testCtx, 
            doStmt.testExpr, 
            testCtx.getOutSlot()
        );

        // If the expresson is true, jump to the loop body
        testCtx.addInstr(IRInstr.ifTrue(
            boolSlot,
            bodyBlock,
            exitBlock
        ));

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
        auto initCtx = ctx.subCtx(false);
        stmtToIR(forStmt.initStmt, initCtx);
        ctx.merge(initCtx);

        // Jump to the test block
        ctx.addInstr(IRInstr.jump(testBlock));

        // Evaluate the test expression
        auto testCtx = ctx.subCtx(true, NULL_LOCAL, testBlock);
        exprToIR(forStmt.testExpr, testCtx);

        // Convert the expression value to a boolean
        auto boolSlot = genBoolEval(
            testCtx, 
            forStmt.testExpr, 
            testCtx.getOutSlot()
        );

        // If the expresson is true, jump to the loop body
        testCtx.addInstr(IRInstr.ifTrue(
            boolSlot,
            bodyBlock,
            exitBlock
        ));

        // Compile the loop body statement
        auto bodyCtx = ctx.subCtx(false, NULL_LOCAL, bodyBlock);
        stmtToIR(forStmt.bodyStmt, bodyCtx);

        // Jump to the increment block
        bodyCtx.addInstr(IRInstr.jump(incrBlock));

        // Compile the increment expression
        auto incrCtx = ctx.subCtx(true, NULL_LOCAL, incrBlock);
        exprToIR(forStmt.incrExpr, incrCtx);

        // Jump to the loop test
        incrCtx.addInstr(IRInstr.jump(testBlock));

        // Continue code generation in the exit block
        ctx.merge(exitBlock);
    }

    else if (auto forInStmt = cast(ForInStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto testBlock = ctx.fun.newBlock("forin_test");
        auto bodyBlock = ctx.fun.newBlock("forin_body");
        auto exitBlock = ctx.fun.newBlock("forin_exit");

        // Register the loop labels, if any
        ctx.regLabels(stmt.labels, exitBlock, testBlock);

        // Evaluate the object expression
        auto initCtx = ctx.subCtx(true);
        exprToIR(forInStmt.inExpr, initCtx);
        ctx.merge(initCtx);

        // Get the property enumerator
        auto enumInstr = genRtCall(
            ctx, 
            "getPropEnum", 
            ctx.allocTemp(),
            [initCtx.getOutSlot()]
        );

        // Jump to the test block
        ctx.addInstr(IRInstr.jump(testBlock));

        // Create the loop test context
        auto testCtx = ctx.subCtx(false, NULL_LOCAL, testBlock);

        // Get the next property
        auto callInstr = testCtx.addInstr(new IRInstr(&CALL));
        callInstr.outSlot = testCtx.allocTemp();
        callInstr.args.length = 2;
        callInstr.args[0].localIdx = enumInstr.outSlot;
        callInstr.args[1].localIdx = enumInstr.outSlot;

        // Generate the call targets
        genCallTargets(testCtx, callInstr);

        // If the property is a constant value, exit the loop
        auto boolTemp = testCtx.allocTemp();
        testCtx.addInstr(new IRInstr(
            &IS_CONST,
            boolTemp,
            callInstr.outSlot
        ));
        testCtx.addInstr(IRInstr.ifTrue(
            boolTemp,
            exitBlock,
            bodyBlock
        ));

        // Create the body context
        auto bodyCtx = ctx.subCtx(false, NULL_LOCAL, bodyBlock);

        // Assign into the variable expression
        auto assgCtx = bodyCtx.subCtx(true);
        assgToIR(
            forInStmt.varExpr,
            null,
            delegate void(IRGenCtx ctx)
            {
                ctx.moveToOutput(callInstr.outSlot);
            },
            assgCtx
        );
        bodyCtx.merge(assgCtx);

        // Compile the loop body statement
        stmtToIR(forInStmt.bodyStmt, bodyCtx);

        // Jump to the loop test
        bodyCtx.addInstr(IRInstr.jump(testBlock));

        // Continue code generation in the exit block
        ctx.merge(exitBlock);
    }

    // Switch statement
    else if (auto switchStmt = cast(SwitchStmt)stmt)
    {
        switchToIR(switchStmt, ctx);
    }
    */

    // Break statement
    else if (auto breakStmt = cast(BreakStmt)stmt)
    {
        assert (false);
        /*
        IRGenCtx.FnlInfo[] fnlStmts;
        auto block = ctx.getBreakTarget(breakStmt.label, &fnlStmts);

        if (block is null)
            throw new ParseError("break statement with no target", stmt.pos);

        // Compile the finally statements in-line
        foreach (fnl; fnlStmts)
        {
            auto fnlCtx = ctx.subCtx(false);
            fnlCtx.parent = fnl.ctx;
            stmtToIR(fnl.stmt, fnlCtx);
            ctx.merge(fnlCtx.curBlock);
        }

        ctx.addInstr(IRInstr.jump(block));


        // TODO
        // Add the new context to the list corresponding to this label
        context.breakMap.get(label).push(newContext);
        */
    }

    // Continue statement
    else if (auto contStmt = cast(ContStmt)stmt)
    {
        assert (false);
        /*
        IRGenCtx.FnlInfo[] fnlStmts;
        auto block = ctx.getContTarget(contStmt.label, &fnlStmts);

        if (block is null)
            throw new ParseError("continue statement with no target", stmt.pos);

        // Compile the finally statements in-line
        foreach (fnl; fnlStmts)
        {
            auto fnlCtx = ctx.subCtx(false);
            fnlCtx.parent = fnl.ctx;
            stmtToIR(fnl.stmt, fnlCtx);
            ctx.merge(fnlCtx.curBlock);
        }

        ctx.addInstr(IRInstr.jump(block));
        */
    }

    // Return statement
    else if (auto retStmt = cast(ReturnStmt)stmt)
    {
        IRValue retVal;
        if (retStmt.expr is null)
            retVal = IRConst.undefCst;
        else
            retVal = exprToIR(retStmt.expr, ctx);

        // Get the englobing finally statements
        IRGenCtx.FnlInfo[] fnlStmts;
        ctx.getFnlStmts(&fnlStmts);

        // Compile the finally statements in-line
        foreach (fnl; fnlStmts)
        {
            auto fnlCtx = fnl.ctx.subCtx();
            stmtToIR(fnl.stmt, fnlCtx);
            ctx.merge(fnlCtx);
        }

        // Add the return instruction
        ctx.addInstr(new IRInstr(
            &RET,
            retVal
        ));
    }

    /*
    else if (auto throwStmt = cast(ThrowStmt)stmt)
    {
        auto subCtx = ctx.subCtx(true);
        exprToIR(throwStmt.expr, subCtx);
        ctx.merge(subCtx);

        // Generate the exception path
        if (auto excBlock = genExcPath(ctx, subCtx.getOutSlot()))
        {
            // Jump to the exception path
            ctx.addInstr(IRInstr.jump(excBlock));
        }
        else
        {
            // Add an interprocedural throw instruction
            ctx.addInstr(new IRInstr(
                &THROW,
                NULL_LOCAL,
                subCtx.getOutSlot()
            ));
        }
    }

    else if (auto tryStmt = cast(TryStmt)stmt)
    {
        // Create a block for the catch statement
        auto catchBlock = ctx.fun.newBlock("try_catch");

        // Create a block for the finally statement
        auto fnlBlock = ctx.fun.newBlock("try_finally");

        // Create a context for the try block and set its parameters
        auto tryCtx = ctx.subCtx(false);
        tryCtx.catchIdent = tryStmt.catchIdent;
        tryCtx.catchBlock = catchBlock;
        tryCtx.fnlStmt = tryStmt.finallyStmt;

        // Compile the try statement
        stmtToIR(tryStmt.tryStmt, tryCtx);

        // After the try statement, go to the finally block
        tryCtx.addInstr(IRInstr.jump(fnlBlock));

        // Create a context for the catch block and set its parameters
        auto catchCtx = ctx.subCtx(false, NULL_LOCAL, catchBlock);
        catchCtx.fnlStmt = tryStmt.finallyStmt;

        // Compile the catch statement, if present
        if (tryStmt.catchStmt !is null)
            stmtToIR(tryStmt.catchStmt, catchCtx);

        // After the catch statement, go to the finally block
        catchCtx.addInstr(IRInstr.jump(fnlBlock));

        // Compile the finally statement, if present
        auto fnlCtx = ctx.subCtx(false,  NULL_LOCAL, fnlBlock);
        if (tryStmt.finallyStmt !is null)
            stmtToIR(tryStmt.finallyStmt, fnlCtx);

        // Continue the code generation after the finally statement
        ctx.merge(fnlCtx);
    }
    */

    else if (auto exprStmt = cast(ExprStmt)stmt)
    {
        exprToIR(exprStmt.expr, ctx);
    }

    else
    {
        assert (false, "unhandled statement type:\n" ~ stmt.toString());
    }
}

/*
void switchToIR(SwitchStmt stmt, IRGenCtx ctx)
{
    // Compile the switch expression
    auto switchCtx = ctx.subCtx(true);
    exprToIR(stmt.switchExpr, switchCtx);
    ctx.merge(switchCtx);

    // Get the stack slot for the switch expression output
    auto cmpSlot = switchCtx.getOutSlot();

    // If there are no clauses in the switch statement, we are done
    if (stmt.caseExprs.length == 0)
        return;

    // Create the switch exit and default blocks
    auto exitBlock = ctx.fun.newBlock("switch_exit");
    auto defaultBlock = ctx.fun.newBlock("switch_default");

    // Register the statement labels, if any
    ctx.regLabels(stmt.labels, exitBlock, null);

    // Blocks in which the nest test and case statements will reside
    auto nextTestBlock = ctx.curBlock;
    auto nextCaseBlock = ctx.fun.newBlock("switch_case");

    // For each case expression
    for (size_t i = 0; i < stmt.caseExprs.length; ++i)
    {
        auto caseExpr = stmt.caseExprs[i];
        auto caseStmts = stmt.caseStmts[i];

        auto testBlock = nextTestBlock;
        if (i < stmt.caseExprs.length - 1)
            nextTestBlock = ctx.fun.newBlock("switch_test");
        else
            nextTestBlock = defaultBlock;

        auto caseBlock = nextCaseBlock;
        if (i < stmt.caseExprs.length - 1)
            nextCaseBlock = ctx.fun.newBlock("switch_case");
        else
            nextCaseBlock = defaultBlock;

        // Compile the case expression
        auto exprCtx = ctx.subCtx(true, NULL_LOCAL, testBlock);
        exprToIR(caseExpr, exprCtx);
        ctx.merge(exprCtx);

        // Test if the case expression matches
        auto cmpInstr = genRtCall(
            ctx, 
            "se", 
            ctx.allocTemp(),
            [cmpSlot, exprCtx.getOutSlot()]
        );

        // Branch based on the test
        ctx.addInstr(IRInstr.ifTrue(
            cmpInstr.outSlot,
            caseBlock,
            nextTestBlock
        ));

        // Compile the case statements
        auto subCtx = ctx.subCtx(false, NULL_LOCAL, caseBlock);
        foreach (s; caseStmts)
        {
            auto stmtCtx = subCtx.subCtx(false);
            stmtToIR(s, stmtCtx);
            subCtx.merge(stmtCtx);
        }

        // Go to the next case block, skipping its test condition
        subCtx.addInstr(IRInstr.jump(nextCaseBlock));
    }

    // Compile the default block
    auto subCtx = ctx.subCtx(false, NULL_LOCAL, defaultBlock);
    foreach (s; stmt.defaultStmts)
    {
        auto stmtCtx = subCtx.subCtx(false);
        stmtToIR(s, stmtCtx);
        subCtx.merge(stmtCtx);
    }

    // Jump to the exit block
    subCtx.addInstr(IRInstr.jump(exitBlock));

    // Continue code generation at the exit block
    ctx.merge(exitBlock);
}
*/

IRValue exprToIR(ASTExpr expr, IRGenCtx ctx)
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
            auto newClos = ctx.addInstr(new IRInstr(
                &NEW_CLOS,
                new IRFunPtr(fun),
                new IRLinkIdx(),
                new IRLinkIdx()
            ));

            // Set the closure cells for the captured variables
            foreach (idx, ident; funExpr.captVars)
            {
                auto idxCst = IRConst.int32Cst(cast(int32_t)idx);
                auto cellVal = ctx.fun.cellMap[ident];
                genRtCall(
                    ctx, 
                    "clos_set_cell",
                    [newClos, idxCst, cellVal]
                );
            }

            return newClos;
        }

        return null;
    }

    else if (auto binExpr = cast(BinOpExpr)expr)
    {
        IRValue genBinOp(string rtFunName)
        {
            auto lVal = exprToIR(binExpr.lExpr, ctx);
            auto rVal = exprToIR(binExpr.rExpr, ctx);

            return genRtCall(
                ctx, 
                rtFunName,
                [lVal, rVal]
            );
        }

        IRValue genAssign(string rtFunName)
        {
            InPlaceOpFn opFn = null;
            if (rtFunName !is null)
            {
                opFn = delegate IRValue(IRGenCtx ctx, IRValue lArg, IRValue rArg)
                {
                    return genRtCall(
                        ctx, 
                        rtFunName, 
                        [lArg, rArg]
                    );
                };
            }

            auto assgVal = assgToIR(
                binExpr.lExpr,
                opFn,
                delegate IRValue(IRGenCtx ctx)
                {
                    return exprToIR(binExpr.rExpr, ctx);
                },
                ctx
            );

            return assgVal;
        }

        auto op = binExpr.op;

        // Arithmetic operators
        if (op.str == "+")
            return genBinOp("add");
        else if (op.str == "-")
            return genBinOp("sub");
        else if (op.str == "*")
            return genBinOp("mul");
        else if (op.str == "/")
            return genBinOp("div");
        else if (op.str == "%")
            return genBinOp("mod");

        // Bitwise operators
        else if (op.str == "&")
            return genBinOp("and");
        else if (op.str == "|")
            return genBinOp("or");
        else if (op.str == "^")
            return genBinOp("xor");
        else if (op.str == "<<")
            return genBinOp("lsft");
        else if (op.str == ">>")
            return genBinOp("rsft");
        else if (op.str == ">>>")
            return genBinOp("ursft");

        // Instanceof operator
        else if (op.str == "instanceof")
            return genBinOp("instanceof");

        // In operator
        else if (op.str == "in")
            return genBinOp("in");

        // Comparison operators
        else if (op.str == "===")
            return genBinOp("se");
        else if (op.str == "!==")
            return genBinOp("ns");
        else if (op.str == "==")
            return genBinOp("eq");
        else if (op.str == "!=")
            return genBinOp("ne");
        else if (op.str == "<")
            return genBinOp("lt");
        else if (op.str == "<=")
            return genBinOp("le");
        else if (op.str == ">")
            return genBinOp("gt");
        else if (op.str == ">=")
            return genBinOp("ge");

        // In-place assignment operators
        else if (op.str == "=")
            return genAssign(null);
        else if (op.str == "+=")
            return genAssign("add");
        else if (op.str == "-=")
            return genAssign("sub");
        else if (op.str == "*=")
            return genAssign("mul");
        else if (op.str == "/=")
            return genAssign("div");
        else if (op.str == "&=")
            return genAssign("mod");
        else if (op.str == "&=")
            return genAssign("and");
        else if (op.str == "|=")
            return genAssign("or");
        else if (op.str == "^=")
            return genAssign("xor");
        else if (op.str == "<<=")
            return genAssign("lsft");
        else if (op.str == ">>=")
            return genAssign("rsft");
        else if (op.str == ">>>=")
            return genAssign("ursft");

        // Sequencing (comma) operator
        else if (op.str == ",")
        {
            // Evaluate the left expression
            exprToIR(binExpr.lExpr, ctx);

            // Evaluate the right expression into this context's output
            return exprToIR(binExpr.rExpr, ctx);
        }

        // FIXME
        /*
        // Logical OR and logical AND
        else if (op.str == "||" || op.str == "&&")
        {
            // Create the right expression and exit blocks
            auto secnBlock = ctx.fun.newBlock(((op.str == "||")? "or":"and") ~ "_sec");
            auto exitBlock = ctx.fun.newBlock(((op.str == "||")? "or":"and") ~ "_exit");

            // Evaluate the left expression
            auto lCtx = ctx.subCtx(true, ctx.getOutSlot());
            exprToIR(binExpr.lExpr, lCtx);
            ctx.merge(lCtx); 

            // Convert the expression value to a boolean
            auto boolSlot = genBoolEval(
                ctx, 
                binExpr.lExpr, 
                lCtx.getOutSlot()
            );

            // Evaluate the second expression, if necessary
            ctx.addInstr(IRInstr.ifTrue(
                boolSlot,
                (op.str == "||")? exitBlock:secnBlock,
                (op.str == "||")? secnBlock:exitBlock,
            ));

            // Evaluate the right expression
            auto rCtx = ctx.subCtx(true, ctx.getOutSlot(), secnBlock);
            exprToIR(binExpr.rExpr, rCtx); 

            // Jump to the exit block
            rCtx.addInstr(IRInstr.jump(exitBlock));

            // Continue code generation in the exit block
            ctx.merge(exitBlock);
        }
        */

        else
        {
            assert (false, "unhandled binary operator: " ~ to!string(op.str));
        }
    }

    else if (auto unExpr = cast(UnOpExpr)expr)
    {
        auto op = unExpr.op;

        if (op.str == "+")
        {   
            auto subVal = exprToIR(unExpr.expr, ctx);

            return genRtCall(
                ctx, 
                "add",
                [IRConst.int32Cst(0), subVal]
            );
        }

        else if (op.str == "-")
        {
            auto subVal = exprToIR(unExpr.expr, ctx);

            return genRtCall(
                ctx, 
                "sub",
                [IRConst.int32Cst(0), subVal]
            );
        }

        // Bitwise negation
        else if (op.str == "~")
        {
            auto subVal = exprToIR(unExpr.expr, ctx);

            return genRtCall(
                ctx, 
                "not", 
                [subVal]
            );
        }

        /*
        // Typeof operator
        else if (op.str == "typeof")
        {
            // If the subexpression is a global variable
            if (auto identExpr = cast(IdentExpr)unExpr.expr)
            {
                if (identExpr.declNode is null && identExpr.name != "this"w)
                {
                    auto globInstr = ctx.addInstr(new IRInstr(&GET_GLOBAL_OBJ, ctx.allocTemp()));
                    auto strInstr = ctx.addInstr(IRInstr.strCst(ctx.allocTemp(), identExpr.name));

                    auto getInstr = genRtCall(
                        ctx, 
                        "getProp",
                        ctx.allocTemp(),
                        [globInstr.outSlot, strInstr.outSlot]
                    );

                    genRtCall(
                        ctx, 
                        "typeof", 
                        ctx.getOutSlot(),
                        [getInstr.outSlot]
                    );

                    return;
                }
            }

            // Evaluate the subexpression directly
            auto lCtx = ctx.subCtx(true);
            exprToIR(unExpr.expr, lCtx);
            ctx.merge(lCtx);

            genRtCall(
                ctx, 
                "typeof", 
                ctx.getOutSlot(),
                [lCtx.getOutSlot()]
            );
        }

        // Delete operator
        else if (op.str == "delete")
        {
            IRGenCtx objCtx;
            IRGenCtx propCtx;

            // If the base expression is a member expression: a[b]
            if (auto indexExpr = cast(IndexExpr)unExpr.expr)
            {
                objCtx = ctx.subCtx(true);
                exprToIR(indexExpr.base, objCtx);
                ctx.merge(objCtx);

                propCtx = ctx.subCtx(true);
                exprToIR(indexExpr.index, propCtx);
                ctx.merge(propCtx);
            }
            else
            {
                objCtx = ctx.subCtx(true);
                ctx.addInstr(new IRInstr(&GET_GLOBAL_OBJ, objCtx.getOutSlot()));
                ctx.merge(objCtx);

                propCtx = ctx.subCtx(true);
                if (auto identExpr = cast(IdentExpr)unExpr.expr)
                {
                    propCtx.addInstr(IRInstr.strCst(
                        propCtx.getOutSlot(),
                        identExpr.name
                    ));
                }
                else
                {
                    exprToIR(unExpr.expr, objCtx);
                }
                ctx.merge(propCtx);
            }

            genRtCall(
                ctx, 
                "delProp",
                ctx.getOutSlot(),
                [objCtx.getOutSlot(), propCtx.getOutSlot()]
            );
        }

        // Boolean (logical) negation
        else if (op.str == "!")
        {
            // Create the right expression and exit blocks
            auto trueBlock = ctx.fun.newBlock("not_true");
            auto falseBlock = ctx.fun.newBlock("not_false");
            auto exitBlock = ctx.fun.newBlock("not_exit");

            auto lCtx = ctx.subCtx(true);
            exprToIR(unExpr.expr, lCtx);
            ctx.merge(lCtx);

            // Convert the expression value to a boolean
            auto boolSlot = genBoolEval(
                ctx, 
                unExpr.expr,
                lCtx.getOutSlot()
            );

            // If the boolean is true, jump
            ctx.addInstr(IRInstr.ifTrue(
                boolSlot,
                trueBlock,
                falseBlock
            ));

            // true => false
            trueBlock.addInstr(new IRInstr(&SET_FALSE, ctx.getOutSlot()));
            trueBlock.addInstr(IRInstr.jump(exitBlock));

            // false => true
            falseBlock.addInstr(new IRInstr(&SET_TRUE, ctx.getOutSlot()));
            falseBlock.addInstr(IRInstr.jump(exitBlock));

            // Continue code generation in the exit block
            ctx.merge(exitBlock);
        }

        // Pre-incrementation and pre-decrementation (++x, --x)
        else if ((op.str == "++" || op.str == "--") && op.assoc == 'r')
        {
            // Perform the incrementation/decrementation and assignment
            assgToIR(
                unExpr.expr,
                delegate void(IRGenCtx ctx, LocalIdx lArg, LocalIdx rArg)
                {
                    genRtCall(
                        ctx, 
                        (op.str == "++")? "add":"sub",
                        ctx.getOutSlot(),
                        [lArg, rArg]
                    );
                },
                delegate void(IRGenCtx ctx)
                {
                    ctx.addInstr(IRInstr.intCst(ctx.getOutSlot(), 1));
                },
                ctx
            );
        }
        
        // Post-incrementation and post-decrementation (x++, x--)
        else if ((op.str == "++" || op.str == "--") && op.assoc == 'l')
        {
            // Get the slot for the output value
            auto valOutSlot = ctx.getOutSlot();

            // Perform the incrementation/decrementation and assignment
            auto aCtx = ctx.subCtx(true);
            assgToIR(
                unExpr.expr,
                delegate void(IRGenCtx ctx, LocalIdx lArg, LocalIdx rArg)
                {
                    ctx.addInstr(new IRInstr(&MOVE, valOutSlot, lArg));

                    genRtCall(
                        ctx, 
                        (op.str == "++")? "add":"sub", 
                        ctx.getOutSlot(),
                        [lArg, rArg]
                    );
                },
                delegate void(IRGenCtx ctx)
                {
                    ctx.addInstr(IRInstr.intCst(ctx.getOutSlot(), 1));
                },
                aCtx
            );
            ctx.merge(aCtx);
        }
        */

        else
        {
            assert (
                false, 
                "unhandled unary operator " ~ to!string(op.str) ~ 
                " / " ~ to!string(op.assoc)
            );
        }
    }

    /*
    else if (auto condExpr = cast(CondExpr)expr)
    {
        // Create the true, false and join blocks
        auto trueBlock  = ctx.fun.newBlock("cond_true");
        auto falseBlock = ctx.fun.newBlock("cond_false");
        auto joinBlock  = ctx.fun.newBlock("cond_join");

        // Get the output slot
        auto outSlot = ctx.getOutSlot();

        // Evaluate the test expression
        auto exprCtx = ctx.subCtx(true);
        exprToIR(condExpr.testExpr, exprCtx);
        ctx.merge(exprCtx);

        // Convert the expression value to a boolean
        auto boolSlot = genBoolEval(
            ctx, 
            condExpr.testExpr,
            exprCtx.getOutSlot()
        );

        // If the expresson is true, jump
        ctx.addInstr(IRInstr.ifTrue(
            boolSlot,
            trueBlock,
            falseBlock
        ));

        // Compile the true expression and assign into the output slot
        auto trueCtx = ctx.subCtx(true, ctx.getOutSlot(), trueBlock);
        exprToIR(condExpr.trueExpr, trueCtx);
        trueCtx.addInstr(IRInstr.jump(joinBlock));

        // Compile the false expression and assign into the output slot
        auto falseCtx = ctx.subCtx(true, ctx.getOutSlot(), falseBlock);
        exprToIR(condExpr.falseExpr, falseCtx);
        falseCtx.addInstr(IRInstr.jump(joinBlock));

        // Continue code generation in the join block
        ctx.merge(joinBlock);
    }
    */

    // Function call expression
    else if (auto callExpr = cast(CallExpr)expr)
    {
        auto baseExpr = callExpr.base;
        auto argExprs = callExpr.args;

        // If this is an inline IR instruction
        if (isIIR(callExpr))
        {
            return genIIR(callExpr, ctx);
        }

        // Local slots for the closure and "this" arguments
        IRValue closVal;
        IRValue thisVal;

        // If the base expression is a member expression
        if (auto indexExpr = cast(IndexExpr)baseExpr)
        {
            // Evaluate the base (this) expression
            thisVal = exprToIR(indexExpr.base, ctx);

            // Evaluate the index expression
            auto keyVal = exprToIR(indexExpr.index, ctx);

            // Get the method property
            closVal = genRtCall(
                ctx,
                "getProp",
                [thisVal, keyVal]
            );
        }

        else
        {
            // Evaluate the base expression
            closVal = exprToIR(baseExpr, ctx);

            // The this value is the global object
            thisVal = ctx.addInstr(new IRInstr(&GET_GLOBAL_OBJ));
        }

        // Evaluate the arguments
        auto argVals = new IRValue[argExprs.length];
        foreach (argIdx, argExpr; argExprs)
        {
            argVals[argIdx] = exprToIR(argExpr, ctx);
        }

        // Add the call instruction
        // <dstLocal> = CALL <fnLocal> <thisArg> ...
        auto callInstr = ctx.addInstr(new IRInstr(&CALL, 2 + argVals.length));
        callInstr.setArg(0, closVal);
        callInstr.setArg(1, thisVal);
        foreach (argIdx, argVal; argVals)
            callInstr.setArg(2+argIdx, argVal);

        // Generate the call targets
        genCallTargets(ctx, callInstr);

        return callInstr;
    }

    /*
    // New operator call expression
    else if (auto newExpr = cast(NewExpr)expr)
    {
        auto baseExpr = newExpr.base;
        auto argExprs = newExpr.args;

        // Evaluate the base expression
        auto baseCtx = ctx.subCtx(true);       
        exprToIR(baseExpr, baseCtx);
        ctx.merge(baseCtx);

        // Evaluate the arguments
        auto argSlots = new LocalIdx[argExprs.length];
        for (size_t i = 0; i < argExprs.length; ++i)
        {
            auto argCtx = ctx.subCtx(true);       
            exprToIR(argExprs[i], argCtx);
            ctx.merge(argCtx);
            argSlots[i] = argCtx.outSlot;
        }

        // Add the call instruction
        // <dstLocal> = NEW <fnLocal> ...
        auto callInstr = ctx.addInstr(new IRInstr(&CALL_NEW));
        callInstr.outSlot = ctx.getOutSlot();
        callInstr.args.length = 1 + argSlots.length;
        callInstr.args[0].localIdx = baseCtx.outSlot;
        for (size_t i = 0; i < argSlots.length; ++i)
            callInstr.args[1+i].localIdx = argSlots[i];

        // Generate the call targets
        genCallTargets(ctx, callInstr);
    }
    */

    else if (auto indexExpr = cast(IndexExpr)expr)
    {
        // Evaluate the base expression
        auto baseVal = exprToIR(indexExpr.base, ctx);

        // Evaluate the index expression
        auto idxVal = exprToIR(indexExpr.index, ctx);

        // Get the property from the object
        return genRtCall(
            ctx, 
            "getProp",
            [baseVal, idxVal]
        );
    }

    /*
    else if (auto arrayExpr = cast(ArrayExpr)expr)
    {
        // Create the array
        auto linkInstr = ctx.addInstr(IRInstr.makeLink(ctx.allocTemp()));
        auto protoInstr = ctx.addInstr(new IRInstr(&GET_ARR_PROTO, ctx.allocTemp()));
        auto numInstr = ctx.addInstr(IRInstr.intCst(ctx.allocTemp(), cast(int32)arrayExpr.exprs.length));
        auto arrInstr = genRtCall(
            ctx, 
            "newArr",
            ctx.getOutSlot(),
            [linkInstr.outSlot, protoInstr.outSlot, numInstr.outSlot]
        );

        auto idxTmp = ctx.allocTemp();
        auto valTmp = ctx.allocTemp();

        // Evaluate the property values
        for (size_t i = 0; i < arrayExpr.exprs.length; ++i)
        {
            auto valExpr = arrayExpr.exprs[i];

            ctx.addInstr(IRInstr.intCst(
                idxTmp,
                cast(int32)i
            ));

            auto valCtx = ctx.subCtx(true, valTmp);
            exprToIR(valExpr, valCtx);
            ctx.merge(valCtx);

            // Set the property on the object
            genRtCall(
                ctx, 
                "setProp",
                ctx.allocTemp(),
                [arrInstr.outSlot, idxTmp, valCtx.getOutSlot()]
            );
        }
    }

    else if (auto objExpr = cast(ObjectExpr)expr)
    {
        // Create the object
        auto linkInstr = ctx.addInstr(IRInstr.makeLink(ctx.allocTemp()));
        auto protoInstr = ctx.addInstr(new IRInstr(&GET_OBJ_PROTO, ctx.allocTemp()));
        auto objInstr = genRtCall(
            ctx, 
            "newObj",
            ctx.getOutSlot(),
            [linkInstr.outSlot, protoInstr.outSlot]
        );

        auto strTmp = ctx.allocTemp();
        auto valTmp = ctx.allocTemp();

        // Evaluate the property values
        for (size_t i = 0; i < objExpr.names.length; ++i)
        {
            auto strExpr = objExpr.names[i];
            auto valExpr = objExpr.values[i];

            auto strCtx = ctx.subCtx(true, strTmp);
            exprToIR(strExpr, strCtx);
            ctx.merge(strCtx);

            auto valCtx = ctx.subCtx(true, valTmp);
            exprToIR(valExpr, valCtx);
            ctx.merge(valCtx);

            // Set the property on the object
            genRtCall(
                ctx, 
                "setProp",
                ctx.allocTemp(),
                [objInstr.outSlot, strCtx.getOutSlot(), valCtx.getOutSlot()]
            );
        }
    }
    */

    // Identifier/variable reference
    else if (auto identExpr = cast(IdentExpr)expr)
    {
        // If this is the "this" argument
        if (identExpr.name == "this")
        {
            return ctx.fun.thisVal;
        }

        // If this is the argument count argument
        else if (identExpr.name == "$argc")
        {
            return ctx.fun.argcVal;
        }

        // If the variable is global
        else if (identExpr.declNode is null)
        {
            // Get the global value
            return ctx.addInstr(new IRInstr(
                &GET_GLOBAL,
                new IRString(identExpr.name),
                new IRCachedIdx()
            ));
        }

        // If the variable is captured or escaping
        else if (identExpr.declNode in ctx.fun.cellMap)
        {
            auto cellVal = ctx.fun.cellMap[identExpr.declNode];
            return genRtCall(
                ctx, 
                "getCellVal",
                [cellVal]
            );
        }

        // The variable is local
        else
        {
            assert (
                identExpr.declNode in ctx.localMap,
                "variable declaration not in local map: \"" ~ 
                to!string(identExpr.name) ~ "\""
            );

            // Get the variable's value
            return ctx.localMap[identExpr.declNode];
        }
    }

    else if (auto intExpr = cast(IntExpr)expr)
    {
        // If the constant fits in the int32 range
        if (intExpr.val >= int32.min && intExpr.val <= int32.max)
        {
            return IRConst.int32Cst(cast(int32_t)intExpr.val);
        }
        else
        {
            return IRConst.float64Cst(cast(double)intExpr.val);
        }
    }

    else if (auto floatExpr = cast(FloatExpr)expr)
    {
        return IRConst.float64Cst(floatExpr.val);
    }

    else if (auto stringExpr = cast(StringExpr)expr)
    {
        return ctx.addInstr(new IRInstr(
            &SET_STR,
            new IRString(stringExpr.val),
            new IRLinkIdx()
        ));
    }

    /*
    else if (auto regexpExpr = cast(RegexpExpr)expr)
    {
        auto linkInstr = ctx.addInstr(IRInstr.makeLink(ctx.allocTemp()));
        auto reInstr = ctx.addInstr(IRInstr.strCst(
            ctx.allocTemp(),
            regexpExpr.pattern
        ));
        auto flagsInstr = ctx.addInstr(IRInstr.strCst(
            ctx.allocTemp(), 
            regexpExpr.flags
        ));

        auto arrInstr = genRtCall(
            ctx, 
            "getRegexp",
            ctx.outSlot,
            [linkInstr.outSlot, reInstr.outSlot, flagsInstr.outSlot]
        );
    }
    */

    else if (cast(TrueExpr)expr)
    {
        return IRConst.trueCst;
    }

    else if (cast(FalseExpr)expr)
    {
        return IRConst.falseCst;
    }

    else if (cast(NullExpr)expr)
    {
        return IRConst.nullCst;
    }

    else
    {
        assert (false, "unhandled expression type:\n" ~ expr.toString());
    }
}

/// In-place operation delegate function
alias IRValue delegate(IRGenCtx ctx, IRValue lArg, IRValue rArg) InPlaceOpFn;

/// Expression evaluation delegate function
alias IRValue delegate(IRGenCtx ctx) ExprEvalFn;

/**
Generate IR for an assignment expression
*/
IRValue assgToIR(
    ASTExpr lhsExpr, 
    InPlaceOpFn inPlaceOpFn,
    ExprEvalFn rhsExprFn, 
    IRGenCtx ctx
)
{
    IRValue genRhs(
        IRGenCtx ctx,
        IRValue base = null,
        IRValue index = null
    )
    {
        // If there is no in-place operation
        if (inPlaceOpFn is null)
        {
            // Compute the right expression
            return rhsExprFn(ctx);
        }
        else
        {
            // Compute the right expression
            auto rhsVal = rhsExprFn(ctx);

            // If this is an indexed property access
            IRValue lhsTemp;
            if (base !is null)
            {
                // Get the property from the object
                lhsTemp = genRtCall(
                    ctx, 
                    "getProp",
                    [base, index]
                );
            }
            else
            {
                // Evaluate the lhs value
                lhsTemp = exprToIR(lhsExpr, ctx);
            }

            // Generate the in-place operation
            return inPlaceOpFn(ctx, lhsTemp, rhsVal);
        }
    }

    // If the lhs is an identifier
    if (auto identExpr = cast(IdentExpr)lhsExpr)
    {
        // Compute the right expression
        auto rhsVal = genRhs(ctx);

        // If the variable is global (unresolved)
        if (identExpr.declNode is null)
        {
            //writefln("assigning to global: %s", identExpr);

            // Set the global value
            ctx.addInstr(new IRInstr(
                &SET_GLOBAL,
                new IRString(identExpr.name),
                rhsVal,
                new IRCachedIdx()
            ));
        }

        // If the variable is captured or escaping
        else if (identExpr.declNode in ctx.fun.cellMap)
        {
            // Set the value in the mutable cell
            auto cellVal = ctx.fun.cellMap[identExpr.declNode];
            genRtCall(
                ctx, 
                "setCellVal",
                [cellVal, rhsVal]
            );
        }

        // The variable is local
        else
        {
            // Assign the value in the local map
            ctx.localMap[identExpr.declNode] = rhsVal;
        }

        return rhsVal;
    }

    // If the lhs is an array indexing expression (e.g.: a[b])
    else if (auto indexExpr = cast(IndexExpr)lhsExpr)
    {
        // Evaluate the base expression
        auto baseVal = exprToIR(indexExpr.base, ctx);

        // Evaluate the index expression
        auto idxVal = exprToIR(indexExpr.index, ctx);

        // Compute the right expression
        auto rhsVal = genRhs(
            ctx,
            baseVal,
            idxVal
        );

        // Set the property on the object
        genRtCall(
            ctx, 
            "setProp",
            [baseVal, idxVal, rhsVal]
        );

        return rhsVal;
    }

    else
    {
        throw new ParseError("invalid lhs in assignment", lhsExpr.pos);
    }
}

/**
Test if an expression is inline IR
*/
bool isIIR(ASTExpr expr)
{

    auto callExpr = cast(CallExpr)expr;
    if (!callExpr)
        return false;

    auto identExpr = cast(IdentExpr)callExpr.base;
    return (identExpr && identExpr.name.startsWith(IIR_PREFIX));
}

/**
Test if this is a branch-position inline IR expression
*/
bool isBranchIIR(ASTExpr expr)
{
    // If this is an assignment, check the right subexpression
    auto binExpr = cast(BinOpExpr)expr;
    if (binExpr && binExpr.op.str == "=")
        expr = binExpr.rExpr;

    return isIIR(expr);
}

/**
Generate an inline IR instruction
*/
IRInstr genIIR(ASTExpr expr, IRGenCtx ctx)
{
    assert (
        isIIR(expr), 
        "invalid inline IR expr"
    );

    assert (false);

    /*
    auto callExpr = cast(CallExpr)expr;
    auto baseExpr = callExpr.base;
    auto argExprs = callExpr.args;
    IdentExpr identExpr = cast(IdentExpr)baseExpr;

    // Get the instruction name
    auto instrName = to!string(identExpr.name[IIR_PREFIX.length..$]);

    if (instrName !in iir)
    {
        throw new ParseError(
            "wrong iir instruction name: \"" ~ instrName ~ "\"", 
            callExpr.pos
        );
    }

    auto opcode = iir[instrName];

    if ((argExprs.length < opcode.argTypes.length) ||
        (argExprs.length > opcode.argTypes.length && !opcode.isVarArg))
    {
        throw new ParseError(
            "wrong iir argument count for \"" ~ instrName ~ "\"",
            callExpr.pos
        );
    }

    // Create the IR instruction
    auto instr = new IRInstr(opcode);
    instr.args.length = argExprs.length;
    instr.outSlot = ctx.getOutSlot();

    // For each argument
    for (size_t i = 0; i < argExprs.length; ++i)
    {
        auto argExpr = argExprs[i];
        auto argType = opcode.getArgType(i);

        switch (argType)
        {
            // Local stack slot
            case OpArg.LOCAL:
            auto argCtx = ctx.subCtx(true);       
            exprToIR(argExpr, argCtx);
            ctx.merge(argCtx);
            instr.args[i].localIdx = argCtx.outSlot;
            break;

            // Integer argument
            case OpArg.INT32:
            auto intExpr = cast(IntExpr)argExpr;
            if (intExpr is null)
            {
                throw new ParseError(
                    "expected integer argument", 
                    argExpr.pos
                );
            }
            instr.args[i].int32Val = cast(int32)intExpr.val;
            break;

            // Raw pointer constant
            case OpArg.RAWPTR:
            auto intExpr = cast(IntExpr)argExpr;
            if (intExpr is null)
            {
                throw new ParseError(
                    "expected integer argument", 
                    argExpr.pos
                );
            }
            instr.args[i].ptrVal = cast(rawptr)intExpr.val;
            break;

            // String argument
            case OpArg.STRING:
            auto strExpr = cast(StringExpr)argExpr;
            if (strExpr is null)
            {
                throw new ParseError(
                    "expected int argument", 
                    argExpr.pos
                );
            }
            instr.args[i].stringVal = strExpr.val;
            break;

            // Link table index
            case OpArg.LINK:
            auto intExpr = cast(IntExpr)argExpr;
            if (intExpr is null || intExpr.val != 0)
            {
                throw new ParseError(
                    "expected 0 argument", 
                    argExpr.pos
                );
            }
            instr.args[i].linkIdx = NULL_LINK;
            break;

            // CODEBLOCK
            case OpArg.CODEBLOCK:
            if (cast(NullExpr)argExpr)
            {
                instr.args[i].codeBlock = null;
            }
            else
            {
                throw new ParseError(
                        "expected null argument", 
                        argExpr.pos
                );
            }
            break;

            default:
            assert (false, "unsupported argument type");
        }
    }

    // Add the instruction to the context
    ctx.addInstr(instr);

    // If this is a call_instruction, generate the call targets
    if (instr.opcode.isCall)
        genCallTargets(ctx, instr);

    return instr;
    */
}

/**
Evaluate a value as a boolean
*/
IRValue genBoolEval(IRGenCtx ctx, ASTExpr testExpr, IRValue argVal)
{
    bool isBoolExpr(ASTExpr expr)
    {
        if (isBranchIIR(expr))
            return true;

        if (cast(TrueExpr)expr || cast(FalseExpr)expr)
            return true;

        auto unOp = cast(UnOpExpr)expr;
        if (unOp !is null &&
            unOp.op.str == "!" &&
            isBoolExpr(unOp.expr))
            return true;

        auto binOp = cast(BinOpExpr)expr;
        if (binOp !is null)
        {
            auto op = binOp.op.str;
 
            if (op == "=="  || op == "!=" ||
                op == "===" || op == "!==" ||
                op == "<"   || op == "<=" ||
                op == ">"   || op == ">=")
                return true;

            if ((op == "&&" || op == "||") && 
                isBoolExpr(binOp.lExpr) && 
                isBoolExpr(binOp.rExpr))
                return true;
        }

        return false;
    }

    if (isBoolExpr(testExpr))
    {
        return argVal;
    }
    else
    {
        // Convert the value to a boolean
        auto boolInstr = genRtCall(
            ctx, 
            "toBool",
            [argVal]
        );

        return boolInstr;
    }
}

/**
Insert a call to a runtime function
*/
IRInstr genRtCall(IRGenCtx ctx, string fName, IRValue[] argVals)
{
    // Get the global function
    auto funVal = ctx.addInstr(new IRInstr(
        &GET_GLOBAL, 
        new IRString(to!wstring("$rt_" ~ fName)),
        new IRCachedIdx()
    ));

    // <dstLocal> = CALL <fnLocal> <thisArg> ...
    auto callInstr = ctx.addInstr(new IRInstr(&CALL, 2 + argVals.length));
    callInstr.setArg(0, funVal);
    callInstr.setArg(1, funVal);
    foreach (argIdx, argVal; argVals)
        callInstr.setArg(2 + argIdx, argVal);

    // Generate the call targets
    genCallTargets(ctx, callInstr);

    return callInstr;
}

/**
Generate the exception code path for a call or throw instruction
*/
IRBlock genExcPath(IRGenCtx ctx, IRValue excVal)
{
    IRGenCtx.FnlInfo[] fnlStmts;
    auto catchInfo = ctx.getCatchInfo(&fnlStmts);

    // If there is no englobing catch block and there are
    // no englobing finally statements
    if (catchInfo is null && fnlStmts.length == 0)
        return null;

    // Create a block for the exception path
    auto excBlock = ctx.fun.newBlock("call_exc");
    auto excCtx = ctx.subCtx(excBlock);           

    // If there is an englobing try block
    if (catchInfo !is null)
    {
        // Assign the exception value to the catch variable
        assgToIR(
            catchInfo.ident,
            null,
            delegate IRValue(IRGenCtx ctx)
            {
                return excVal;
            },
            excCtx
        );
    }

    //writefln("num fnl stmts: %s", fnlStmts.length);

    // Compile the finally statements in-line
    foreach (fnl; fnlStmts)
    {
        auto fnlCtx = fnl.ctx.subCtx();
        stmtToIR(fnl.stmt, fnlCtx);
        excCtx.merge(fnlCtx);
    }

    // If there is an englobing try block
    if (catchInfo !is null)
    {
        // Jump to the catch block
        excCtx.jump(catchInfo.block);
    }

    // Otherwise, there is no englobing try-catch block
    else
    {
        // Add an interprocedural throw instruction
        excCtx.addInstr(new IRInstr(&THROW));
    }

    return excBlock;
}

/**
Generate and set the normal and exception targets for a call instruction
*/
void genCallTargets(IRGenCtx ctx, IRInstr callInstr)
{
    // Create a block for the call continuation
    auto contBlock = ctx.fun.newBlock("call_cont");

    // Set the continuation target
    callInstr.setTarget(0, contBlock);

    // Generate the exception path for the call instruction
    if (auto excBlock = genExcPath(ctx, callInstr))
        callInstr.setTarget(1, excBlock);

    // Continue code generation in the continuation block
    ctx.merge(contBlock);
}

/*
Creates phi nodes and modifies the local variable map for a loop entry
*/
IRGenCtx createLoopEntry(
    IRGenCtx curCtx, 
    IRBlock entryBlock
)
{
    // Branch into the loop entry
    auto entryDesc = curCtx.jump(entryBlock);  

    // Create a local map for the loop entry
    IRValue[IdentExpr] localMap;

    // For each local variable
    foreach (ident, value; curCtx.localMap)
    {
        // Create a phi node in the loop entry block
        auto phiNode = entryBlock.addPhi(new PhiNode());

        // Set the entry argument to the phi node
        entryDesc.setPhiArg(phiNode, value);

        // Add the phi node to the local map
        localMap[ident] = phiNode;
    }

    // Create the loop entry context
    return new IRGenCtx(
        curCtx,
        curCtx.fun,
        entryBlock,
        localMap
    );
}

/**
Merge incoming contexts for a loop entry block
*/
void mergeLoopEntry(
    IRGenCtx[] contexts,
    IRValue[IdentExpr] entryMap,
    IRBlock entryBlock
)
{
    // Add a jump from each incoming context to the loop entry
    foreach (ctx; contexts)
    {
        //writefln("merging context into entry");
        //writefln("lastInstr: %s", ctx.curBlock.lastInstr);

        auto lastInstr = ctx.curBlock.lastInstr;
        if (!lastInstr || !lastInstr.opcode.isBranch)
            ctx.jump(entryBlock);
    }

    // For each local variable going through the loop
    foreach (ident, value; entryMap)
    {
        auto phiNode = cast(PhiNode)value;
        assert (phiNode !is null);

        // Count the number of incoming self reference values
        size_t numSelf = 0;
        IRValue nonSelfVal = null;
        foreach (ctx; contexts)
        {
            auto incVal = ctx.localMap[ident];

            if (incVal is phiNode)
                numSelf++;
            else
                nonSelfVal = incVal;
        }

        assert (nonSelfVal !is null);

        // If the phi node only has one incoming value and self references
        if (numSelf == contexts.length - 1)
        {
            // Replace uses of the phi node by uses of its incoming value
            phiNode.replUses(nonSelfVal);

            // Remove the phi node
            entryBlock.remPhi(phiNode);
        }
        else
        {
            // Set the incoming phi values for all incoming contexts
            foreach (ctx; contexts)
            {
                auto incVal = ctx.localMap[ident];
                auto branchDesc = ctx.curBlock.lastInstr.getTarget(0);
                branchDesc.setPhiArg(phiNode, incVal);
            }
        }
    }
}

/**
Merge local variables locations from multiple contexts using phi nodes
*/
IRGenCtx mergeContexts(
    IRGenCtx parentCtx,
    IRGenCtx[] contexts,
    IRBlock mergeBlock
)
{
    assert (
        contexts.length > 0, 
        "no contexts to merge"
    );

    // Local map for the merged values
    IRValue[IdentExpr] mergeMap;

    // For each local variable going through the loop
    foreach (ident, value; parentCtx.localMap)
    {
        // Check if all incoming values are the same
        IRValue firstVal = contexts[0].localMap[ident];
        bool allEqual = true;
        foreach (ctx; contexts[1..$])
        {
            auto incVal = ctx.localMap[ident];
            if (incVal != firstVal)
                allEqual = false;
        }

        // If not all incoming values are the same
        if (allEqual is false)
        {
            // Create a phi node for this value
            auto phiNode = mergeBlock.addPhi(new PhiNode());

            // Add the phi node to the merged map
            mergeMap[ident] = phiNode;

            // Set the incoming phi values for all incoming contexts
            foreach (ctx; contexts)
            {
                auto incVal = ctx.localMap[ident];
                auto branch = ctx.curBlock.lastInstr;
                assert (branch !is null);

                // For each target of the branch instruction
                for (size_t tIdx = 0; tIdx < IRInstr.MAX_TARGETS; ++tIdx)
                    if (auto desc = branch.getTarget(tIdx))
                        desc.setPhiArg(phiNode, incVal);
            }
        }

        // Otherwise, all values are the same
        else
        {
            // Add the value directly to the merged map
            mergeMap[ident] = firstVal;
        }
    }

    // Create the loop entry context
    return new IRGenCtx(
        parentCtx,
        parentCtx.fun,
        mergeBlock,
        mergeMap
    );
}

