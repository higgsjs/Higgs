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
import parser.lexer;
import parser.ast;
import parser.parser;
import ir.ir;
import ir.ops;
import ir.iir;
import ir.inlining;
import ir.peephole;
import ir.livevars;
import ir.typeprop;
import ir.slotalloc;
import runtime.vm;
import options;

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
        IRBlock, "breakTarget",
        IRGenCtx[]*, "breakCtxs",
        IRBlock, "contTarget", 
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

    /// Throw contexts
    IRGenCtx[]* throwCtxs;

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

        assert (
            !hasBranch(),
            "cannot add instr:\n" ~
            instr.toString() ~
            "\ncurrent block already has final branch:\n" ~
            curBlock.toString() ~
            "\nin function \"" ~ curBlock.fun.getName() ~ "\""
        );

        curBlock.addInstr(instr);
        assert (instr.block is curBlock);

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
    Test if a branch instruction was added
    */
    bool hasBranch()
    {
        return (curBlock.lastInstr && curBlock.lastInstr.opcode.isBranch);
    }

    /**
    Register labels in the current context
    */
    void regLabels(
        IdentExpr[] labels, 
        IRBlock breakTarget,
        IRGenCtx[]* breakCtxs,
        IRBlock contTarget, 
        IRGenCtx[]* contCtxs
    )
    {
        foreach (label; labels)
        {
            labelTargets ~= LabelTargets(
                label.name, 
                breakTarget, 
                breakCtxs, 
                contTarget, 
                contCtxs
            );
        }

        // Implicit null label
        labelTargets ~= LabelTargets(
            null, 
            breakTarget,
            breakCtxs,
            contTarget,
            contCtxs
        );
    }

    /**
    Find the context list for a break statement
    */
    IRBlock getBreakTarget(IdentExpr ident, FnlInfo[]* stmts, ref IRGenCtx[]* breakCtxs)
    {
        foreach (target; labelTargets)
        {
            if ((ident is null && target.name is null) || 
                (ident !is null && target.name == ident.name))
                {
                    breakCtxs = target.breakCtxs;
                    return target.breakTarget;
                }
        }

        if (fnlStmt)
            *stmts ~= FnlInfo(fnlStmt, parent);

        if (parent is null)
            return null;

        return parent.getBreakTarget(ident, stmts, breakCtxs);
    }

    /**
    Find the context list for a continue statement
    */
    IRBlock getContTarget(IdentExpr ident, FnlInfo[]* stmts, ref IRGenCtx[]* contCtxs)
    {
        foreach (target; labelTargets)
        {
            if (target.contCtxs is null)
                continue;

            if ((ident is null && target.name is null) || 
                (ident !is null && target.name == ident.name))
            {
                contCtxs = target.contCtxs;
                return target.contTarget;
            }
        }

        if (fnlStmt)
            *stmts ~= FnlInfo(fnlStmt, parent);

        if (parent is null)
            return null;

        return parent.getContTarget(ident, stmts, contCtxs);
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
            return new Tuple!(
                IdentExpr, "ident", 
                IRBlock, "block",
                IRGenCtx[]*, "throwCtxs"
            )
            (catchIdent, catchBlock, throwCtxs);
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
    BranchEdge jump(IRBlock block)
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

    /**
    Create a location-dependent link value
    */
    IRInstr makeLink()
    {
        return addInstr(new IRInstr(
            &MAKE_LINK,
            new IRLinkIdx()
        ));
    }

    /**
    Obtain a constant string value
    */
    IRInstr strVal(wstring str)
    {
        return addInstr(new IRInstr(
            &SET_STR,
            new IRString(str),
            new IRLinkIdx()
        ));
    }
}

/**
Compile an AST program or function into an IR function
*/
IRFunction astToIR(
    VM vm,
    FunExpr ast,
    IRFunction fun = null
)
{
    assert (
        cast(FunExpr)ast || cast(ASTProgram)ast,
        "invalid AST function"
    );

    // If no IR function object was passed, create one
    if (fun is null)
        fun = new IRFunction(vm, ast);

    assert (
        fun.entryBlock is null,
        "function already has an entry block"
    );

    // Create the function entry block
    auto entry = fun.newBlock("entry");
    fun.entryBlock = entry;

    // Create a context for the function body
    IRValue[IdentExpr] initLocalMap;
    auto bodyCtx = new IRGenCtx(
        null,
        fun,
        entry,
        initLocalMap
    );

    // Create values for the hidden arguments
    fun.raVal   = cast(FunParam)entry.addPhi(new FunParam("ra"  , 0));
    fun.closVal = cast(FunParam)entry.addPhi(new FunParam("clos", 1));
    fun.thisVal = cast(FunParam)entry.addPhi(new FunParam("this", 2));
    fun.argcVal = cast(FunParam)entry.addPhi(new FunParam("argc", 3));

    // Create values for the visible function parameters
    for (size_t i = 0; i < ast.params.length; ++i)
    {
        auto argIdx = NUM_HIDDEN_ARGS + i;
        auto ident = ast.params[i];

        auto paramVal = new FunParam(ident.name, cast(uint32_t)argIdx);
        entry.addPhi(paramVal);
        fun.paramMap[ident] = paramVal;
        bodyCtx.localMap[ident] = paramVal;
    }

    // Allocate slots for local variables
    foreach (ident; ast.locals)
    {
        // If this variable does not escape and is not a parameter
        if (ident !in ast.escpVars && ast.params.countUntil(ident) == -1)
        {
            bodyCtx.localMap[ident] = IRConst.undefCst;
        }
    }

    // Initialize global variable declarations to undefined
    if (auto unit = cast(ASTProgram)ast)
    {
        foreach (ident; unit.globals)
        {
            bodyCtx.addInstr(new IRInstr(
                &SET_GLOBAL,
                new IRString(ident.name),
                IRConst.undefCst
            ));
        }
    }

    // If the function uses the arguments object
    if (ast.usesArguments)
    {
        // Create the "arguments" array
        auto protoVal = bodyCtx.addInstr(new IRInstr(&GET_ARR_PROTO));
        auto argObjVal = genRtCall(
            bodyCtx,
            "newArr",
            [protoVal, fun.argcVal],
            fun.ast.pos
        );

        // Map the "arguments" identifier to the array object
        bodyCtx.localMap[ast.argObjIdent] = argObjVal;

        // Set the "callee" property
        auto calleeStr = bodyCtx.strVal("callee");
        auto setInstr = genRtCall(
            bodyCtx,
            "setProp",
            [argObjVal, calleeStr, fun.closVal],
            fun.ast.pos
        );

        // Create the loop test, body and exit blocks
        auto testBlock = fun.newBlock("arg_test");
        auto loopBlock = fun.newBlock("arg_loop");
        auto exitBlock = fun.newBlock("arg_exit");

        // Jump to the test block
        auto entryBranch = bodyCtx.jump(testBlock);

        // Create a phi node for the loop index
        auto idxPhi = testBlock.addPhi(new PhiNode());
        entryBranch.setPhiArg(idxPhi, IRConst.int32Cst(0));

        // Branch based on the index
        auto testCtx = bodyCtx.subCtx(testBlock);
        auto cmpVal = testCtx.addInstr(new IRInstr(
            &LT_I32,
            idxPhi,
            fun.argcVal
        ));
        testCtx.ifTrue(cmpVal, loopBlock, exitBlock);

        // Copy an argument into the array
        auto loopCtx = bodyCtx.subCtx(loopBlock);
        auto argVal = loopCtx.addInstr(new IRInstr(
            &GET_ARG,
            idxPhi
        ));
        genRtCall(
            loopCtx,
            "setArrElemNoCheck",
            [cast(IRValue)argObjVal, idxPhi, argVal],
            fun.ast.pos
        );

        // Increment the loop index and jump to the test block
        auto incVal = loopCtx.addInstr(new IRInstr(
            &ADD_I32,
            idxPhi,
            IRConst.int32Cst(1)
        ));
        auto loopBranch = loopCtx.jump(testBlock);
        loopBranch.setPhiArg(idxPhi, incVal);

        // Continue code generation in the exit block
        bodyCtx.merge(exitBlock);
    }

    // Get the cell pointers for captured closure variables
    foreach (idx, ident; ast.captVars)
    {
        auto getVal = genRtCall(
            bodyCtx,
            "clos_get_cell",
            [fun.closVal, cast(IRValue)IRConst.int32Cst(cast(int32_t)idx)],
            fun.ast.pos
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
                [],
                fun.ast.pos
            );
            fun.cellMap[ident] = allocInstr;

            // If this variable is local
            if (ident in bodyCtx.localMap)
            {
                genRtCall(
                    bodyCtx,
                    "setCellVal",
                    [allocInstr, bodyCtx.localMap[ident]],
                    fun.ast.pos
                );
            }
        }
    }

    // Create closures for nested function declarations
    foreach (funDecl; ast.funDecls)
    {
        // Create an IR function object for the function
        auto subFun = new IRFunction(
            vm,
            funDecl
        );

        // Store the binding for the function
        assgToIR(
            bodyCtx,
            funDecl.name,
            null,
            delegate IRValue(IRGenCtx ctx)
            {
                // Create a closure of this function
                auto newClos = ctx.addInstr(new IRInstr(
                    &NEW_CLOS,
                    new IRFunPtr(subFun)
                ));

                // Set the closure cells for the captured variables
                foreach (idx, ident; subFun.ast.captVars)
                {
                    auto idxCst = IRConst.int32Cst(cast(int32_t)idx);
                    genRtCall(
                        ctx,
                        "clos_set_cell",
                        [newClos, idxCst, fun.cellMap[ident]],
                        fun.ast.pos
                    );
                }

                return newClos;
            }
        );
    }

    // Compile the function body
    stmtToIR(bodyCtx, ast.bodyStmt);

    // If the body has no final branch, compile a "return undefined;"
    if (!bodyCtx.hasBranch)
    {
        bodyCtx.addInstr(new IRInstr(&RET, IRConst.undefCst));
    }

    // Run the inlining pass
    inlinePass(vm, fun);

    // Perform peephole optimizations on the function
    optIR(fun);

    // Compute liveness information for the function
    fun.liveInfo = new LiveInfo(fun);

    // If the type analysis is enabled
    if (opts.jit_typeprop)
    {
        fun.typeInfo = new TypeProp(fun, fun.liveInfo);
    }

    /*
    version (release)
    {
        fun.typeInfo = new TypeProp(fun, fun.liveInfo);
    }
    else
    {
        if (opts.jit_typeprop)
            fun.typeInfo = new TypeProp(fun, fun.liveInfo);
    }
    */

    // Allocate stack slots for the IR instructions
    allocSlots(fun);

    //writeln("compiled fn:");
    //writeln(fun.toString());

    // Return the IR function object
    return fun;
}

void stmtToIR(IRGenCtx ctx, ASTStmt stmt)
{
    //writeln("stmt to IR: ", stmt);

    // Curly-brace enclosed block statement
    if (auto blockStmt = cast(BlockStmt)stmt)
    {
        // For each statement in the block
        foreach (s; blockStmt.stmts)
        {
            // Compile the statement in the current context
            stmtToIR(ctx, s);

            // If a final branch was added, stop
            if (ctx.hasBranch)
                break;
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
                ctx,
                ident,
                null,
                delegate IRValue(IRGenCtx ctx)
                {
                    return exprToIR(ctx, init);
                }
            );
        }
    }

    else if (auto ifStmt = cast(IfStmt)stmt)
    {
        auto trueBlock = ctx.fun.newBlock("if_true");
        auto falseBlock = ctx.fun.newBlock("if_false");
        auto joinBlock = ctx.fun.newBlock("if_join");

        // Evaluate the test expression
        auto testVal = exprToIR(ctx, ifStmt.testExpr);

        // Get the last instruction of the current block
        auto lastInstr = ctx.curBlock.lastInstr;

        // If this is a branch inline IR expression
        if (isBranchIIR(ifStmt.testExpr) && lastInstr && lastInstr.opcode.isBranch)
        {
            assert (
                lastInstr.getTarget(0) is null,
                "iir target already set"
            );

            // Set branch targets for the instruction
            lastInstr.setTarget(0, trueBlock);
            lastInstr.setTarget(1, falseBlock);
        }

        else
        {
            // Convert the expression value to a boolean
            auto boolVal = genBoolEval(
                ctx,
                ifStmt.testExpr,
                testVal
            );

            // Branch based on the boolean value
            ctx.ifTrue(boolVal, trueBlock, falseBlock);
        }

        // Compile the true statement
        auto trueCtx = ctx.subCtx(trueBlock);
        stmtToIR(trueCtx, ifStmt.trueStmt);
        if (!trueCtx.hasBranch)
            trueCtx.jump(joinBlock);

        // Compile the false statement
        auto falseCtx = ctx.subCtx(falseBlock);
        stmtToIR(falseCtx, ifStmt.falseStmt);
        if (!falseCtx.hasBranch)
            falseCtx.jump(joinBlock);

        // Merge the true and false contexts into the join block
        auto joinCtx = mergeContexts(
            ctx,
            [trueCtx, falseCtx],
            joinBlock
        );

        // Continue code generation in the join block
        ctx.merge(joinCtx);
    }

    else if (auto whileStmt = cast(WhileStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto testBlock = ctx.fun.newBlock("while_test");
        auto bodyBlock = ctx.fun.newBlock("while_body");
        auto exitBlock = ctx.fun.newBlock("while_exit");

        // Create a context for the loop entry (the loop test)
        IRGenCtx[] breakCtxLst = [];
        IRGenCtx[] contCtxLst = [];
        auto testCtx = createLoopEntry(
            ctx,
            testBlock,
            stmt,
            exitBlock,
            &breakCtxLst,
            testBlock,
            &contCtxLst
        );

        // Store a copy of the loop entry phi nodes
        auto entryLocals = testCtx.localMap.dup;

        // Compile the loop test in the entry context
        auto testVal = exprToIR(testCtx, whileStmt.testExpr);

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
        stmtToIR(bodyCtx, whileStmt.bodyStmt);

        // Add the test exit to the break context list
        breakCtxLst ~= testCtx.subCtx();

        // Add the body exit to the continue context list
        contCtxLst ~= bodyCtx.subCtx();

        // Merge the break contexts into the loop exit
        auto loopExitCtx = mergeContexts(
            ctx,
            breakCtxLst,
            exitBlock
        );

        // Merge the continue contexts with the loop entry
        mergeLoopEntry(
            ctx,
            contCtxLst,
            entryLocals,
            testBlock
        );

        // Continue code generation after the loop exit
        ctx.merge(loopExitCtx);
    }

    else if (auto doStmt = cast(DoWhileStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto bodyBlock = ctx.fun.newBlock("do_body");
        auto testBlock = ctx.fun.newBlock("do_test");
        auto exitBlock = ctx.fun.newBlock("do_exit");

        // Create a context for the loop entry (the loop test)
        IRGenCtx[] breakCtxLst = [];
        IRGenCtx[] contCtxLst = [];
        auto bodyCtx = createLoopEntry(
            ctx,
            bodyBlock,
            stmt,
            exitBlock,
            &breakCtxLst,
            testBlock,
            &contCtxLst
        );

        // Store a copy of the loop entry phi nodes
        auto entryLocals = bodyCtx.localMap.dup;

        // Compile the loop body statement
        stmtToIR(bodyCtx, doStmt.bodyStmt);
        bodyCtx.jump(testBlock);

        // Add the body exit to the continue context list
        contCtxLst ~= bodyCtx;

        // Merge the continue contexts
        auto testCtx = mergeContexts(
            ctx,
            contCtxLst,
            testBlock
        );

        // Compile the loop test expression
        auto testVal = exprToIR(testCtx, doStmt.testExpr);

        // Convert the expression value to a boolean
        auto boolVal = genBoolEval(
            testCtx, 
            doStmt.testExpr, 
            testVal
        );

        // If the expresson is true, jump to the loop body
        testCtx.ifTrue(boolVal, bodyBlock, exitBlock);

        // Add the test exit to the break context list
        breakCtxLst ~= testCtx.subCtx();

        // Merge the break contexts into the loop exit
        auto loopExitCtx = mergeContexts(
            ctx,
            breakCtxLst,
            exitBlock
        );

        // Merge the continue contexts with the loop entry
        mergeLoopEntry(
            ctx,
            [testCtx.subCtx()],
            entryLocals,
            bodyBlock
        );

        // Continue code generation after the loop exit
        ctx.merge(loopExitCtx);
    }

    else if (auto forStmt = cast(ForStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto testBlock = ctx.fun.newBlock("for_test");
        auto bodyBlock = ctx.fun.newBlock("for_body");
        auto incrBlock = ctx.fun.newBlock("for_incr");
        auto exitBlock = ctx.fun.newBlock("for_exit");

        // Compile the init statement
        stmtToIR(ctx, forStmt.initStmt);

        // Create a context for the loop entry (the loop test)
        IRGenCtx[] breakCtxLst = [];
        IRGenCtx[] contCtxLst = [];
        auto testCtx = createLoopEntry(
            ctx,
            testBlock,
            stmt,
            exitBlock,
            &breakCtxLst,
            incrBlock,
            &contCtxLst
        );

        // Store a copy of the loop entry phi nodes
        auto entryLocals = testCtx.localMap.dup;        

        // Compile the loop test in the entry context
        auto testVal = exprToIR(testCtx, forStmt.testExpr);

        // Convert the expression value to a boolean
        auto boolVal = genBoolEval(
            testCtx, 
            forStmt.testExpr, 
            testVal
        );

        // If the expresson is true, jump to the loop body
        testCtx.ifTrue(boolVal, bodyBlock, exitBlock);

        // Compile the loop body statement
        auto bodyCtx = testCtx.subCtx(bodyBlock);
        stmtToIR(bodyCtx, forStmt.bodyStmt);
        if (!bodyCtx.hasBranch)
            bodyCtx.jump(incrBlock);

        // Add the test exit to the break context list
        breakCtxLst ~= testCtx.subCtx();

        // Add the body exit to the continue context list
        contCtxLst ~= bodyCtx.subCtx();

        // Merge the continue contexts into the increment block
        auto incrCtx = mergeContexts(
            ctx,
            contCtxLst,
            incrBlock
        );

        // Compile the increment expression
        exprToIR(incrCtx, forStmt.incrExpr);

        // Merge the increment context with the entry block
        mergeLoopEntry(
            ctx,
            [incrCtx],
            entryLocals,
            testBlock
        );

        // Merge the break contexts into the loop exit
        auto loopExitCtx = mergeContexts(
            ctx,
            breakCtxLst,
            exitBlock
        );

        // Continue code generation after the loop exit
        ctx.merge(loopExitCtx);
    }

    // For-in loop statement
    else if (auto forInStmt = cast(ForInStmt)stmt)
    {
        // Create the loop test, body and exit blocks
        auto testBlock = ctx.fun.newBlock("forin_test");
        auto bodyBlock = ctx.fun.newBlock("forin_body");
        auto exitBlock = ctx.fun.newBlock("forin_exit");

        // Evaluate the object expression
        auto objVal = exprToIR(ctx, forInStmt.inExpr);

        // Get the property enumerator
        auto enumVal = genRtCall(
            ctx,
            "getPropEnum",
            [objVal],
            stmt.pos
        );

        // Create a context for the loop entry (the loop test)
        IRGenCtx[] breakCtxLst = [];
        IRGenCtx[] contCtxLst = [];
        auto testCtx = createLoopEntry(
            ctx,
            testBlock,
            stmt,
            exitBlock,
            &breakCtxLst,
            testBlock,
            &contCtxLst
        );

        // Store a copy of the loop entry phi nodes
        auto entryLocals = testCtx.localMap.dup;

        // Get the next property
        auto callInstr = testCtx.addInstr(new IRInstr(&CALL, 2));
        callInstr.setArg(0, enumVal);
        callInstr.setArg(1, enumVal);

        // Generate the call targets
        genCallTargets(testCtx, callInstr, stmt.pos);

        // If the property is a constant value, exit the loop
        auto isConst = testCtx.addInstr(new IRInstr(&IS_CONST, callInstr));
        testCtx.ifTrue(isConst, exitBlock, bodyBlock);

        // Create the body context
        auto bodyCtx = testCtx.subCtx(bodyBlock);

        // Assign into the variable expression
        assgToIR(
            bodyCtx,
            forInStmt.varExpr,
            null,
            delegate IRValue(IRGenCtx ctx)
            {
                return callInstr;
            }
        );

        // Compile the loop body statement
        stmtToIR(bodyCtx, forInStmt.bodyStmt);

        // Add the test exit to the break context list
        breakCtxLst ~= testCtx.subCtx();

        // Add the body exit to the continue context list
        contCtxLst ~= bodyCtx.subCtx();

        // Merge the break contexts into the loop exit
        auto loopExitCtx = mergeContexts(
            ctx,
            breakCtxLst,
            exitBlock
        );

        // Merge the continue contexts with the loop entry
        mergeLoopEntry(
            ctx,
            contCtxLst,
            entryLocals,
            testBlock
        );

        // Continue code generation after the loop exit
        ctx.merge(loopExitCtx);
    }

    // Switch statement
    else if (auto switchStmt = cast(SwitchStmt)stmt)
    {
        switchToIR(ctx, switchStmt);
    }

    // Break statement
    else if (auto breakStmt = cast(BreakStmt)stmt)
    {
        IRGenCtx.FnlInfo[] fnlStmts;
        IRGenCtx[]* breakCtxs;
        auto breakTarget = ctx.getBreakTarget(breakStmt.label, &fnlStmts, breakCtxs);

        if (breakCtxs is null)
            throw new ParseError("break statement with no target", stmt.pos);

        // Compile the finally statements in-line
        foreach (fnl; fnlStmts)
        {
            auto fnlCtx = fnl.ctx.subCtx(ctx.curBlock);
            fnlCtx.localMap = ctx.localMap.dup;
            stmtToIR(fnlCtx, fnl.stmt);
            ctx.merge(fnlCtx);
        }

        // Jump to the break target block
        ctx.jump(breakTarget);

        *breakCtxs ~= ctx.subCtx();
    }

    // Continue statement
    else if (auto contStmt = cast(ContStmt)stmt)
    {
        IRGenCtx.FnlInfo[] fnlStmts;
        IRGenCtx[]* contCtxs;
        auto contTarget = ctx.getContTarget(contStmt.label, &fnlStmts, contCtxs);

        if (contCtxs is null)
            throw new ParseError("continue statement with no target", stmt.pos);

        // Compile the finally statements in-line
        foreach (fnl; fnlStmts)
        {
            auto fnlCtx = fnl.ctx.subCtx(ctx.curBlock);
            fnlCtx.localMap = ctx.localMap.dup;
            stmtToIR(fnlCtx, fnl.stmt);
            ctx.merge(fnlCtx);
        }

        // Jump to the continue target block
        ctx.jump(contTarget);

        *contCtxs ~= ctx.subCtx();
    }

    // Return statement
    else if (auto retStmt = cast(ReturnStmt)stmt)
    {
        IRValue retVal;
        if (retStmt.expr is null)
            retVal = IRConst.undefCst;
        else
            retVal = exprToIR(ctx, retStmt.expr);

        // Get the englobing finally statements
        IRGenCtx.FnlInfo[] fnlStmts;
        ctx.getFnlStmts(&fnlStmts);

        // Compile the finally statements in-line
        foreach (fnl; fnlStmts)
        {
            auto fnlCtx = fnl.ctx.subCtx(ctx.curBlock);
            fnlCtx.localMap = ctx.localMap.dup;
            stmtToIR(fnlCtx, fnl.stmt);
            ctx.merge(fnlCtx);
        }

        // Add the return instruction
        ctx.addInstr(new IRInstr(
            &RET,
            retVal
        ));
    }

    else if (auto throwStmt = cast(ThrowStmt)stmt)
    {
        auto throwVal = exprToIR(ctx, throwStmt.expr);

        // Call a primitive which will throw the exception
        auto enumVal = genRtCall(
            ctx,
            "throwExc",
            [throwVal],
            stmt.pos
        );
    }

    else if (auto tryStmt = cast(TryStmt)stmt)
    {
        // Create a block for the catch statement
        auto catchBlock = ctx.fun.newBlock("try_catch");

        // Create a block for the finally statement
        auto fnlBlock = ctx.fun.newBlock("try_finally");

        // Create a context for the try block and set its parameters
        IRGenCtx[] throwCtxLst;
        auto tryCtx = ctx.subCtx();
        tryCtx.catchIdent = tryStmt.catchIdent;
        tryCtx.catchBlock = catchBlock;
        tryCtx.fnlStmt    = tryStmt.finallyStmt;
        tryCtx.throwCtxs  = &throwCtxLst;

        // Compile the try statement
        stmtToIR(tryCtx, tryStmt.tryStmt);

        // After the try statement, go to the finally block
        if (!tryCtx.hasBranch)
            tryCtx.jump(fnlBlock);

        // If there are incoming throw contexts
        IRGenCtx catchCtx = null;
        if (throwCtxLst.length > 0)
        {
            // Merge the incoming throw contexts for the catch block
            catchCtx = mergeContexts(
                ctx,
                throwCtxLst,
                catchBlock
            );
            catchCtx.fnlStmt = tryStmt.finallyStmt;

            // Compile the catch statement, if present
            if (tryStmt.catchStmt !is null)
                stmtToIR(catchCtx, tryStmt.catchStmt);

            // After the catch statement, go to the finally block
            if (!catchCtx.hasBranch)
                catchCtx.jump(fnlBlock);
        }

        // Merge the try and catch contexts for the finally block
        auto fnlCtx = mergeContexts(
            ctx,
            [tryCtx] ~ (catchCtx? [catchCtx]:[]),
            fnlBlock
        );

        // Compile the finally statement, if present
        if (tryStmt.finallyStmt !is null)
            stmtToIR(fnlCtx, tryStmt.finallyStmt);

        // Continue the code generation after the finally statement
        ctx.merge(fnlCtx);
    }

    else if (auto exprStmt = cast(ExprStmt)stmt)
    {
        exprToIR(ctx, exprStmt.expr);
    }

    else
    {
        assert (false, "unhandled statement type:\n" ~ stmt.toString());
    }
}

void switchToIR(IRGenCtx ctx, SwitchStmt stmt)
{
    // Compile the switch expression
    auto switchVal = exprToIR(ctx, stmt.switchExpr);

    // If there are no clauses in the switch statement, we are done
    if (stmt.caseExprs.length == 0)
        return;

    // Create the switch exit and default blocks
    auto exitBlock = ctx.fun.newBlock("switch_exit");
    auto defaultBlock = ctx.fun.newBlock("switch_default");

    // Create a sub-context for the switch clauses
    auto switchCtx = ctx.subCtx();

    // Register the statement labels, if any
    IRGenCtx[] breakCtxLst = [];
    switchCtx.regLabels(stmt.labels, exitBlock, &breakCtxLst, null, null);

    // Context from the previous clause statement block
    IRGenCtx prevStmtCtx = null;

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
        auto testCtx = switchCtx.subCtx(testBlock);
        auto caseVal = exprToIR(testCtx, caseExpr);

        // Test if the case expression matches
        auto cmpInstr = genRtCall(
            testCtx,
            "se",
            [switchVal, caseVal],
            stmt.pos
        );

        // Branch based on the test
        testCtx.ifTrue(cmpInstr, caseBlock, nextTestBlock);

        switchCtx.merge(testCtx);

        // Merge the test and previous case contexts
        auto stmtCtx = mergeContexts(
           switchCtx,
           prevStmtCtx? [switchCtx, prevStmtCtx]:[switchCtx],
           caseBlock
        );

        // Compile the case statements
        foreach (s; caseStmts)
        {
            stmtToIR(stmtCtx, s);
            if (stmtCtx.hasBranch)
                break;
        }

        // Go to the next case block, skipping its test (fallthrough)
        if (!stmtCtx.hasBranch)
            stmtCtx.jump(nextCaseBlock);

        prevStmtCtx = stmtCtx;
    }

    // Merge the test and previous case contexts
    auto defaultCtx = mergeContexts(
       switchCtx,
       prevStmtCtx? [switchCtx, prevStmtCtx]:[switchCtx],
       defaultBlock
    );

    // Compile the default block
    foreach (s; stmt.defaultStmts)
    {
        stmtToIR(defaultCtx, s);
        if (defaultCtx.hasBranch)
            break;
    }

    // Jump to the exit block
    if (!defaultCtx.hasBranch)
        defaultCtx.jump(exitBlock);

    // Add the default block context to the break context list
    breakCtxLst ~= defaultCtx;

    // Merge the break contexts
    auto switchExit = mergeContexts(
       ctx,
       breakCtxLst,
       exitBlock
    );

    // Continue code generation at the exit block
    ctx.merge(switchExit);
}

IRValue exprToIR(IRGenCtx ctx, ASTExpr expr)
{
    //writeln("expr to IR: ", expr);

    // Function expression
    if (auto funExpr = cast(FunExpr)expr)
    {
        // If this is not a function declaration
        if (countUntil(ctx.fun.ast.funDecls, funExpr) == -1)
        {
            // Create an IR function object for the function
            auto fun = new IRFunction(
                ctx.fun.vm,
                funExpr
            );

            // Create a closure of this function
            auto newClos = ctx.addInstr(new IRInstr(
                &NEW_CLOS,
                new IRFunPtr(fun)
            ));

            // Set the closure cells for the captured variables
            foreach (idx, ident; funExpr.captVars)
            {
                auto idxCst = IRConst.int32Cst(cast(int32_t)idx);
                auto cellVal = ctx.fun.cellMap[ident];
                genRtCall(
                    ctx, 
                    "clos_set_cell",
                    [newClos, idxCst, cellVal],
                    expr.pos
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
            auto lVal = exprToIR(ctx, binExpr.lExpr);
            auto rVal = exprToIR(ctx, binExpr.rExpr);

            return genRtCall(
                ctx,
                rtFunName,
                [lVal, rVal],
                expr.pos
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
                        [lArg, rArg],
                        expr.pos
                    );
                };
            }

            auto assgVal = assgToIR(
                ctx,
                binExpr.lExpr,
                opFn,
                delegate IRValue(IRGenCtx ctx)
                {
                    return exprToIR(ctx, binExpr.rExpr);
                }
            );

            return assgVal;
        }

        IRValue genEq()
        {
            if (cast(IntExpr)binExpr.lExpr || cast(IntExpr)binExpr.rExpr)
            {
                auto lVal = exprToIR(ctx, binExpr.lExpr);
                auto rVal = exprToIR(ctx, binExpr.rExpr);
                return genRtCall(
                    ctx,
                    "eqInt",
                    [lVal, rVal],
                    expr.pos
                );
            }

            if (cast(NullExpr)binExpr.rExpr)
            {
                auto lVal = exprToIR(ctx, binExpr.lExpr);
                return genRtCall(
                    ctx,
                    "eqNull",
                    [lVal],
                    expr.pos
                );
            }

            return genBinOp("eq");
        }

        auto op = binExpr.op;

        // Arithmetic operators
        if (op.str == "+")
            return genBinOp("addIntFloat");
        else if (op.str == "-")
            return genBinOp("subIntFloat");
        else if (op.str == "*")
            return genBinOp("mulIntFloat");
        else if (op.str == "/")
            return genBinOp("divIntFloat");
        else if (op.str == "%")
            return genBinOp("modInt");

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
            return genEq();
        else if (op.str == "!=")
            return genBinOp("ne");
        else if (op.str == "<")
            return genBinOp("ltIntFloat");
        else if (op.str == "<=")
            return genBinOp("leIntFloat");
        else if (op.str == ">")
            return genBinOp("gtIntFloat");
        else if (op.str == ">=")
            return genBinOp("geIntFloat");

        // In-place assignment operators
        else if (op.str == "=")
            return genAssign(null);
        else if (op.str == "+=")
            return genAssign("addIntFloat");
        else if (op.str == "-=")
            return genAssign("subIntFloat");
        else if (op.str == "*=")
            return genAssign("mulIntFloat");
        else if (op.str == "/=")
            return genAssign("divIntFloat");
        else if (op.str == "&=")
            return genAssign("modInt");
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
            exprToIR(ctx, binExpr.lExpr);

            // Evaluate the right expression into this context's output
            return exprToIR(ctx, binExpr.rExpr);
        }

        // Logical OR and logical AND
        else if (op.str == "||" || op.str == "&&")
        {
            // Create the right expression and exit blocks
            auto secBlock = ctx.fun.newBlock(((op.str == "||")? "or":"and") ~ "_sec");
            auto exitBlock = ctx.fun.newBlock(((op.str == "||")? "or":"and") ~ "_exit");

            // Evaluate the left expression
            auto fstCtx = ctx.subCtx();
            auto fstVal = exprToIR(fstCtx, binExpr.lExpr);

            // Convert the expression value to a boolean
            auto boolVal = genBoolEval(
                fstCtx, 
                binExpr.lExpr,
                fstVal
            );

            // Evaluate the second expression, if necessary
            auto ifTrue = fstCtx.ifTrue(
                boolVal,
                (op.str == "||")? exitBlock:secBlock,
                (op.str == "||")? secBlock:exitBlock,
            );
            auto fstBranch = ifTrue.getTarget((op.str == "||")? 0:1);

            // Evaluate the right expression
            auto secCtx = fstCtx.subCtx(secBlock);
            auto secVal = exprToIR(secCtx, binExpr.rExpr);
            auto secBranch = secCtx.jump(exitBlock);

            // Merge the contexts from both branches
            auto exitCtx = mergeContexts(
                ctx,
                [fstCtx, secCtx],
                exitBlock
            );

            // Create a phi node to select the output value
            auto phiNode = exitBlock.addPhi(new PhiNode());
            fstBranch.setPhiArg(phiNode, fstVal);
            secBranch.setPhiArg(phiNode, secVal);

            ctx.merge(exitCtx);

            return phiNode;
        }

        else
        {
            assert (false, "unhandled binary operator: " ~ to!string(op.str));
        }
    }

    else if (auto unExpr = cast(UnOpExpr)expr)
    {
        auto op = unExpr.op;

        // Unary plus
        if (op.str == "+")
        {
            auto subVal = exprToIR(ctx, unExpr.expr);

            return genRtCall(
                ctx,
                "plus",
                [subVal],
                expr.pos
            );
        }

        // Unary minus
        else if (op.str == "-")
        {
            auto subVal = exprToIR(ctx, unExpr.expr);

            return genRtCall(
                ctx,
                "minus",
                [subVal],
                expr.pos
            );
        }

        // Bitwise negation
        else if (op.str == "~")
        {
            auto subVal = exprToIR(ctx, unExpr.expr);
            return genRtCall(
                ctx,
                "not",
                [subVal],
                expr.pos
            );
        }

        // Typeof operator
        else if (op.str == "typeof")
        {
            IRValue exprVal;

            // If the subexpression is an identifier
            if (auto identExpr = cast(IdentExpr)unExpr.expr)
            {
                // Evaluate the identifier, but don't throw
                // an exception if it's a non-existent global
                exprVal = refToIR(ctx, identExpr, false);
            }
            else
            {
                // Evaluate the subexpression
                exprVal = exprToIR(ctx, unExpr.expr);
            }

            return genRtCall(
                ctx,
                "typeof",
                [exprVal],
                expr.pos
            );
        }

        // Void operator
        else if (op.str == "void")
        {
            // Evaluate the subexpression
            exprToIR(ctx, unExpr.expr);

            // Produce the undefined value
            return IRConst.undefCst;
        }

        // Delete operator
        else if (op.str == "delete")
        {
            IRValue objVal;
            IRValue propVal;

            // If the base expression is a member expression: a[b]
            if (auto indexExpr = cast(IndexExpr)unExpr.expr)
            {
                objVal = exprToIR(ctx, indexExpr.base);
                propVal = exprToIR(ctx, indexExpr.index);
            }
            else
            {
                objVal = ctx.addInstr(new IRInstr(&GET_GLOBAL_OBJ));

                if (auto identExpr = cast(IdentExpr)unExpr.expr)
                    propVal = ctx.strVal(identExpr.name);
                else
                    propVal = exprToIR(ctx, unExpr.expr);
            }

            return genRtCall(
                ctx,
                "delProp",
                [objVal, propVal],
                expr.pos
            );
        }

        // Boolean (logical) negation
        else if (op.str == "!")
        {
            // Create the right expression and exit blocks
            auto exitBlock = ctx.fun.newBlock("not_exit");

            // Evaluate the test expression
            auto testVal = exprToIR(ctx, unExpr.expr);

            // Convert the expression value to a boolean
            auto boolVal = genBoolEval(
                ctx,
                unExpr.expr,
                testVal
            );

            // If the boolean is true, jump
            auto ift = ctx.ifTrue(
                boolVal,
                exitBlock,
                exitBlock
            );

            // Create a phi node to invert the boolean value
            auto phiNode = exitBlock.addPhi(new PhiNode());
            ift.getTarget(0).setPhiArg(phiNode, IRConst.falseCst);
            ift.getTarget(1).setPhiArg(phiNode, IRConst.trueCst);

            // Continue code generation in the exit block
            ctx.merge(exitBlock);

            return phiNode;
        }

        // Pre-incrementation and pre-decrementation (++x, --x)
        else if ((op.str == "++" || op.str == "--") && op.assoc == 'r')
        {
            // Perform the incrementation/decrementation and assignment
            return assgToIR(
                ctx,
                unExpr.expr,
                delegate IRValue(IRGenCtx ctx, IRValue lArg, IRValue rArg)
                {
                    return genRtCall(
                        ctx,
                        (op.str == "++")? "addInt":"subInt",
                        [lArg, rArg],
                        expr.pos
                    );
                },
                delegate IRValue(IRGenCtx ctx)
                {
                    return IRConst.int32Cst(1);
                }
            );
        }

        // Post-incrementation and post-decrementation (x++, x--)
        else if ((op.str == "++" || op.str == "--") && op.assoc == 'l')
        {
            IRValue outVal = null;

            // Perform the incrementation/decrementation and assignment
            assgToIR(
                ctx,
                unExpr.expr,
                delegate IRValue(IRGenCtx ctx, IRValue lArg, IRValue rArg)
                {
                    // Store the l-value pre-assignment
                    outVal = lArg;

                    return genRtCall(
                        ctx, 
                        (op.str == "++")? "addInt":"subInt",
                        [lArg, rArg],
                        expr.pos
                    );
                },
                delegate IRValue(IRGenCtx ctx)
                {
                    return IRConst.int32Cst(1);
                }
            );

            return outVal;
        }

        else
        {
            assert (
                false, 
                "unhandled unary operator " ~ to!string(op.str) ~ 
                " / " ~ to!string(op.assoc)
            );
        }
    }

    // Ternary operator
    else if (auto condExpr = cast(CondExpr)expr)
    {
        // Create the true, false and join blocks
        auto trueBlock  = ctx.fun.newBlock("cond_true");
        auto falseBlock = ctx.fun.newBlock("cond_false");
        auto joinBlock  = ctx.fun.newBlock("cond_join");

        // Evaluate the test expression
        auto testVal = exprToIR(ctx, condExpr.testExpr);

        // Convert the expression value to a boolean
        auto boolVal = genBoolEval(
            ctx, 
            condExpr.testExpr,
            testVal
        );

        // If the expresson is true, jump
        ctx.ifTrue(
            boolVal,
            trueBlock,
            falseBlock
        );

        // Compile the true expression and assign into the output slot
        auto trueCtx = ctx.subCtx(trueBlock);
        auto trueVal = exprToIR(trueCtx, condExpr.trueExpr);
        auto trueBranch = trueCtx.jump(joinBlock);

        // Compile the false expression and assign into the output slot
        auto falseCtx = ctx.subCtx(falseBlock);
        auto falseVal = exprToIR(falseCtx, condExpr.falseExpr);
        auto falseBranch = falseCtx.jump(joinBlock);

        // Continue code generation in the join block
        ctx.merge(joinBlock);

        auto joinCtx = mergeContexts(
            ctx,
            [trueCtx, falseCtx],
            joinBlock
        );

        // Create a phi node to select the output value
        auto phiNode = joinBlock.addPhi(new PhiNode());
        trueBranch.setPhiArg(phiNode, trueVal);
        falseBranch.setPhiArg(phiNode, falseVal);

        ctx.merge(joinCtx);

        return phiNode;
    }

    // Function call expression
    else if (auto callExpr = cast(CallExpr)expr)
    {
        auto baseExpr = callExpr.base;
        auto argExprs = callExpr.args;

        // If this is an inline IR instruction
        if (isIIR(callExpr))
        {
            return genIIR(ctx, callExpr);
        }

        // Evaluate the call arguments
        auto argVals = new IRValue[argExprs.length];
        foreach (argIdx, argExpr; argExprs)
            argVals[argIdx] = exprToIR(ctx, argExpr);

        // If this is a call to a runtime function
        if (auto identExpr = cast(IdentExpr)baseExpr)
        {
            if (identExpr.name.startsWith(RT_PREFIX))
            {
                // Make a direct static call to the primitive
                auto callInstr = ctx.addInstr(new IRInstr(&CALL_PRIM, 2 + argVals.length));
                callInstr.setArg(0, new IRString(identExpr.name));
                callInstr.setArg(1, new IRFunPtr(null));
                foreach (argIdx, argVal; argVals)
                    callInstr.setArg(2 + argIdx, argVal);

                // Generate the call targets
                genCallTargets(ctx, callInstr, expr.pos);

                return callInstr;
            }
        }

        // Local slots for the closure and "this" arguments
        IRValue closVal;
        IRValue thisVal;

        // If the base expression is a member expression
        if (auto indexExpr = cast(IndexExpr)baseExpr)
        {
            // Evaluate the base (this) expression
            thisVal = exprToIR(ctx, indexExpr.base);

            // Evaluate the index expression
            auto keyVal = exprToIR(ctx, indexExpr.index);

            // Get the method property
            closVal = genRtCall(
                ctx,
                "getPropMethod",
                [thisVal, keyVal],
                expr.pos
            );
        }
        else
        {
            // Evaluate the base expression
            closVal = exprToIR(ctx, baseExpr);

            // The this value is the global object
            thisVal = ctx.addInstr(new IRInstr(&GET_GLOBAL_OBJ));
        }

        // Add the call instruction
        // <dstLocal> = CALL <fnLocal> <thisArg> ...
        auto callInstr = ctx.addInstr(new IRInstr(&CALL, 2 + argVals.length));
        callInstr.setArg(0, closVal);
        callInstr.setArg(1, thisVal);
        foreach (argIdx, argVal; argVals)
            callInstr.setArg(2 + argIdx, argVal);

        // Generate the call targets
        genCallTargets(ctx, callInstr, expr.pos);

        return callInstr;
    }

    // New operator call expression
    else if (auto newExpr = cast(NewExpr)expr)
    {
        auto baseExpr = newExpr.base;
        auto argExprs = newExpr.args;

        // Evaluate the base expression
        auto closVal = exprToIR(ctx, baseExpr);

        // Get the method property
        auto thisVal = genRtCall(
            ctx,
            "ctorNewThis",
            [closVal],
            expr.pos
        );

        // Evaluate the arguments
        auto argVals = new IRValue[argExprs.length];
        foreach (argIdx, argExpr; argExprs)
            argVals[argIdx] = exprToIR(ctx, argExpr);

        // Add the call instruction
        // <dstLocal> = CALL <fnLocal> <thisArg> ...
        auto callInstr = ctx.addInstr(new IRInstr(&CALL, 2 + argVals.length));
        callInstr.setArg(0, closVal);
        callInstr.setArg(1, thisVal);
        foreach (argIdx, argVal; argVals)
            callInstr.setArg(2 + argIdx, argVal);

        // Generate the call targets
        genCallTargets(ctx, callInstr, expr.pos);

        // Select the return value
        auto retVal = genRtCall(
            ctx,
            "ctorSelectRet",
            [callInstr, thisVal],
            expr.pos
        );

        return retVal;
    }

    else if (auto indexExpr = cast(IndexExpr)expr)
    {
        // Evaluate the base expression
        auto baseVal = exprToIR(ctx, indexExpr.base);

        // Evaluate the index expression
        auto idxVal = exprToIR(ctx, indexExpr.index);

        // If the property is a constant string
        if (auto strProp = cast(StringExpr)indexExpr.index)
        {
            // If the property is "length"
            if (strProp.val == "length")
            {
                // Use a primitive specialized for array length
                return genRtCall(
                    ctx,
                    "getPropLength",
                    [baseVal],
                    expr.pos
                );
            }

            // If the property is not "prototype" or "apply"
            if (strProp.val != "prototype" && strProp.val != "apply")
            {
                // Use a primitive specialized for object fields
                return genRtCall(
                    ctx,
                    "getPropField",
                    [baseVal, idxVal],
                    expr.pos
                );
            }

            // Get the property from the base value
            return genRtCall(
                ctx,
                "getProp",
                [baseVal, idxVal],
                expr.pos
            );
        }

        // The property is non-constant, likely an array index
        else
        {
            // Use a primitive specialized for object fields
            return genRtCall(
                ctx,
                "getPropElem",
                [baseVal, idxVal],
                expr.pos
            );
        }
    }

    else if (auto arrayExpr = cast(ArrayExpr)expr)
    {
        // Create the array
        auto protoVal = ctx.addInstr(new IRInstr(&GET_ARR_PROTO));
        auto numVal = cast(IRValue)IRConst.int32Cst(cast(int32_t)arrayExpr.exprs.length);
        auto arrVal = genRtCall(
            ctx,
            "newArr",
            [protoVal, numVal],
            expr.pos
        );

        // Evaluate and set the property values
        for (size_t i = 0; i < arrayExpr.exprs.length; ++i)
        {
            auto valExpr = arrayExpr.exprs[i];

            auto idxVal = IRConst.int32Cst(cast(int32_t)i);
            auto propVal = exprToIR(ctx, valExpr);

            // Set the array element
            genRtCall(
                ctx,
                "setArrElemNoCheck",
                [arrVal, idxVal, propVal],
                expr.pos
            );
        }

        return arrVal;
    }

    else if (auto objExpr = cast(ObjectExpr)expr)
    {
        // Create the object
        auto protoVal = ctx.addInstr(new IRInstr(&GET_OBJ_PROTO));
        auto objVal = genRtCall(
            ctx,
            "newObj",
            [protoVal],
            expr.pos
        );

        // Evaluate the property values
        for (size_t i = 0; i < objExpr.names.length; ++i)
        {
            auto strExpr = objExpr.names[i];
            auto valExpr = objExpr.values[i];

            auto strVal = exprToIR(ctx, strExpr);
            auto propVal = exprToIR(ctx, valExpr);

            // Set the property on the object
            genRtCall(
                ctx,
                "setPropField",
                [objVal, strVal, propVal],
                expr.pos
            );
        }

        return objVal;
    }

    // Identifier/variable reference
    else if (auto identExpr = cast(IdentExpr)expr)
    {
        return refToIR(ctx, identExpr);
    }

    else if (auto intExpr = cast(IntExpr)expr)
    {
        // If the constant fits in the int32 range
        if (intExpr.val >= int32_t.min && intExpr.val <= int32_t.max)
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
        return ctx.strVal(stringExpr.val);
    }

    else if (auto regexpExpr = cast(RegexpExpr)expr)
    {
        auto linkInstr = ctx.makeLink();
        auto strInstr = ctx.strVal(regexpExpr.pattern);
        auto flagsInstr = ctx.strVal(regexpExpr.flags);
        auto reInstr = genRtCall(
            ctx,
            "getRegexp",
            [linkInstr, strInstr, flagsInstr],
            expr.pos
        );

        return reInstr;
    }

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

/**
Generate IR to evaluate an identifier/variable reference
*/
IRValue refToIR(
    IRGenCtx ctx,
    IdentExpr identExpr,
    bool useGetGlobal = true
)
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

    // If this is the undefined constant
    else if (identExpr.name == "$undef")
    {
        return IRConst.undefCst;
    }

    // If this is the missing constant
    else if (identExpr.name == "$missing")
    {
        return IRConst.missingCst;
    }

    // If this is the null pointer constant
    else if (identExpr.name == "$nullptr")
    {
        return new IRRawPtr(null);
    }

    // If the variable is global
    else if (identExpr.declNode is null)
    {
        if (useGetGlobal)
        {
            // Get the global value
            return genRtCall(
                ctx,
                "getGlobalInl",
                [ctx.strVal(identExpr.name)],
                identExpr.pos
            );
        }
        else
        {
            // Use getProp to get the global value
            // This won't throw an exception if the global doesn't exist
            auto globInstr = ctx.addInstr(new IRInstr(&GET_GLOBAL_OBJ));
            auto propStr = ctx.strVal(identExpr.name);
            return  genRtCall(
                ctx,
                "getProp",
                [globInstr, propStr],
                identExpr.pos
            );
        }
    }

    // If the variable is captured or escaping
    else if (identExpr.declNode in ctx.fun.cellMap)
    {
        auto cellVal = ctx.fun.cellMap[identExpr.declNode];
        return genRtCall(
            ctx,
            "getCellVal",
            [cellVal],
            identExpr.pos
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
        auto value = ctx.localMap[identExpr.declNode];
        //writefln("got local var value: %s", value);
        return value;
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
    IRGenCtx ctx,
    ASTExpr lhsExpr,
    InPlaceOpFn inPlaceOpFn,
    ExprEvalFn rhsExprFn
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
                    [base, index],
                    lhsExpr.pos
                );
            }
            else
            {
                // Evaluate the lhs value
                lhsTemp = exprToIR(ctx, lhsExpr);
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

            // If we are in a runtime unit
            if (auto unit = cast(ASTProgram)ctx.fun.ast)
            {
                if (unit.isRuntime)
                {
                    // Set the global value using the special set_global instruction
                    // Note: this is necessary to bootstrap the system as the setGlobal
                    // function is not yet defined while the runtime is being initialized
                    ctx.addInstr(new IRInstr(
                        &SET_GLOBAL,
                        new IRString(identExpr.name),
                        rhsVal
                    ));

                    return rhsVal;
                }
            }

            // Use the setGlobal primitive function.
            genRtCall(
                ctx,
                "setGlobalInl",
                [ctx.strVal(identExpr.name), rhsVal],
                lhsExpr.pos
            );
        }

        // If the variable is captured or escaping
        else if (identExpr.declNode in ctx.fun.cellMap)
        {
            // Set the value in the mutable cell
            auto cellVal = ctx.fun.cellMap[identExpr.declNode];
            genRtCall(
                ctx,
                "setCellVal",
                [cellVal, rhsVal],
                lhsExpr.pos
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
        auto baseVal = exprToIR(ctx, indexExpr.base);

        // Evaluate the index expression
        auto idxVal = exprToIR(ctx, indexExpr.index);

        // Compute the right expression
        auto rhsVal = genRhs(
            ctx,
            baseVal,
            idxVal
        );

        // If the property is a constant string
        if (auto strProp = cast(StringExpr)indexExpr.index)
        {
            // Set the property on the object
            genRtCall(
                ctx,
                "setPropField",
                [baseVal, idxVal, rhsVal],
                lhsExpr.pos
            );
        }

        // The property is non-constant, likely an array index
        else
        {
            // Use a primitive specialized for array elements
            genRtCall(
                ctx,
                "setPropElem",
                [baseVal, idxVal, rhsVal],
                lhsExpr.pos
            );
        }

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
IRValue genIIR(IRGenCtx ctx, ASTExpr expr)
{
    assert (
        isIIR(expr),
        "invalid inline IR expr"
    );

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
    auto instr = new IRInstr(opcode, argExprs.length);

    // For each argument
    for (size_t i = 0; i < argExprs.length; ++i)
    {
        auto argExpr = argExprs[i];
        auto argType = opcode.getArgType(i);

        IRValue argVal = null;

        switch (argType)
        {
            // Local stack slot
            case OpArg.LOCAL:
            argVal = exprToIR(ctx, argExpr);
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
            argVal = IRConst.int32Cst(cast(int32_t)intExpr.val);
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
            argVal = new IRRawPtr(cast(ubyte*)intExpr.val);
            break;

            // String argument
            case OpArg.STRING:
            auto strExpr = cast(StringExpr)argExpr;
            if (strExpr is null)
            {
                throw new ParseError(
                    "expected string argument", 
                    argExpr.pos
                );
            }
            argVal = new IRString(strExpr.val);
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
            argVal = new IRLinkIdx();
            break;

            default:
            assert (false, "unsupported argument type");
        }

        // Set the argument value
        assert (argVal !is null);
        instr.setArg(i, argVal);
    }

    // Add the instruction to the context
    ctx.addInstr(instr);

    // If this is a call instruction
    if (instr.opcode.isCall)
    {
        // Generate the call targets
        genCallTargets(ctx, instr, expr.pos);
    }

    // If this is the shape_get_def instruction (shape dispatch)
    if (instr.opcode is &SHAPE_GET_DEF)
    {
        auto contBlock = ctx.fun.newBlock("shape_cont");

        // Set the branch target for the instruction
        instr.setTarget(0, contBlock);

        // Continue code generation in the new block
        ctx.merge(contBlock);
    }

    // If this instruction has no output, return the undefined value
    if (instr.opcode.output is false)
    {
        return IRConst.undefCst;
    }
    else
    {
        // Return the instruction's value
        return instr;
    }
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

        if (auto unOp = cast(UnOpExpr)expr)
        {
            if (unOp.op.str == "!")
                return true;

            return false;
        }

        if (auto binOp = cast(BinOpExpr)expr)
        {
            auto op = binOp.op.str;

            if (op == "=="  || op == "!="  ||
                op == "===" || op == "!==" ||
                op == "<"   || op == "<="  ||
                op == ">"   || op == ">="  ||
                op == "instanceof" ||
                op == "in")
                return true;

            // The AND and OR of boolean arguments is a boolean
            if ((op == "&&" || op == "||") &&
                isBoolExpr(binOp.lExpr) &&
                isBoolExpr(binOp.rExpr))
                return true;

            return false;
        }

        // Primitive calls are assumed to produce booleans
        if (auto callExpr = cast(CallExpr)expr)
        {
            if (auto identExpr = cast(IdentExpr)callExpr.base)
                if (identExpr.name.startsWith(RT_PREFIX))
                    return true;

            return false;
        }

        return false;
    }

    if (isBoolExpr(testExpr))
    {
        return argVal;
    }

    //writeln(testExpr);
    //writeln("  ", testExpr.pos);

    // Convert the value to a boolean
    return genRtCall(
        ctx,
        "toBool",
        [argVal],
        testExpr.pos
    );
}

/**
Insert a call to a runtime function
*/
IRInstr genRtCall(IRGenCtx ctx, string fName, IRValue[] argVals, SrcPos pos)
{
    auto nameStr = new IRString(RT_PREFIX ~ to!wstring(fName));

    // <dstLocal> = CALL_PRIM <prim_name> <cachedFun> ...
    auto callInstr = ctx.addInstr(new IRInstr(&CALL_PRIM, 2 + argVals.length));
    callInstr.setArg(0, nameStr);
    callInstr.setArg(1, new IRFunPtr(null));
    foreach (argIdx, argVal; argVals)
    {
        assert (argVal !is null);
        callInstr.setArg(2 + argIdx, argVal);
    }

    // Generate the call targets
    genCallTargets(ctx, callInstr, pos);

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
            excCtx,
            catchInfo.ident,
            null,
            delegate IRValue(IRGenCtx ctx)
            {
                return excVal;
            }
        );
    }

    // Compile the finally statements in-line
    foreach (fnl; fnlStmts)
    {
        auto fnlCtx = fnl.ctx.subCtx(excCtx.curBlock);
        fnlCtx.localMap = excCtx.localMap.dup;
        stmtToIR(fnlCtx, fnl.stmt);
        excCtx.merge(fnlCtx);
    }

    // If there is an englobing try block
    if (catchInfo !is null)
    {
        // Jump to the catch block
        // Note: the finally blocks may throw an exception before us
        if (!excCtx.hasBranch)
            excCtx.jump(catchInfo.block);

        // Add the sub-context to the throw context list
        *catchInfo.throwCtxs ~= excCtx;
    }

    // Otherwise, there is no englobing try-catch block
    else
    {
        // Add an interprocedural throw instruction, this will rethrow
        // the exception value after the finally statements
        excCtx.addInstr(new IRInstr(&THROW, excVal));
    }

    return excBlock;
}

/**
Generate and set the normal and exception targets for a call instruction
*/
void genCallTargets(IRGenCtx ctx, IRInstr callInstr, SrcPos pos)
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

    // Set the source position for the call
    callInstr.srcPos = pos;
}

/*
Creates phi nodes and modifies the local variable map for a loop entry
*/
IRGenCtx createLoopEntry(
    IRGenCtx curCtx,
    IRBlock entryBlock,
    ASTStmt loopStmt,
    IRBlock breakBlock,
    IRGenCtx[]* breakCtxLst,
    IRBlock contBlock,
    IRGenCtx[]* contCtxLst
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
    auto loopCtx = new IRGenCtx(
        curCtx,
        curCtx.fun,
        entryBlock,
        localMap
    );

    // Register the loop labels, if any
    loopCtx.regLabels(
        loopStmt.labels,
        breakBlock, 
        breakCtxLst, 
        contBlock, 
        contCtxLst
    );

    return loopCtx;
}

/**
Merge incoming contexts for a loop entry block
*/
void mergeLoopEntry(
    IRGenCtx parentCtx,
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

        if (!ctx.hasBranch)
            ctx.jump(entryBlock);
    }

    // For each local variable going through the loop
    foreach (ident, value; entryMap)
    {
        auto phiNode = cast(PhiNode)value;
        assert (phiNode !is null);
        assert (phiNode.block is entryBlock);

        // Set the incoming phi values for all incoming contexts
        foreach (ctx; contexts)
        {
            auto incVal = ctx.localMap[ident];

            assert (ctx.hasBranch);
            auto branch = ctx.curBlock.lastInstr;

            for (size_t tIdx = 0; tIdx < IRInstr.MAX_TARGETS; ++tIdx)
                if (auto desc = branch.getTarget(tIdx))
                    if (desc.target == entryBlock)
                        desc.setPhiArg(phiNode, incVal);
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

                assert (
                    branch !is null,
                    "mergeContexts: no branch from block: \"" ~ 
                    ctx.curBlock.getName() ~ "\""
                );

                // For each target of the branch instruction
                for (size_t tIdx = 0; tIdx < IRInstr.MAX_TARGETS; ++tIdx)
                    if (auto desc = branch.getTarget(tIdx))
                        if (desc.target == mergeBlock)
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

