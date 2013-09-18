/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module ir.typeprop;

import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.conv;
import ir.ir;
import ir.ops;
import interp.interp;
import jit.ops;

/// Type representation, propagated by the analysis
struct TypeVal
{
    enum : uint
    {
        BOT,        // Known to be non-constant
        KNOWN_BOOL,
        KNOWN_TYPE,
        TOP         // Value not yet known
    };

    uint state;
    Type type;
    bool val;

    this(uint s) { state = s; }
    this(Type t) { state = KNOWN_TYPE; type = t; }
    this(bool v) { state = KNOWN_BOOL; type = Type.CONST; val = v; }

    string toString()
    {
        switch (state)
        {
            case BOT:
            return "bot/unknown";
            
            case TOP:
            return "top/uninf";

            case KNOWN_TYPE:
            return to!string(type);

            case KNOWN_BOOL:
            return to!string(val);

            default:
            assert (false);
        }
    }
}

const BOT = TypeVal(TypeVal.BOT);
const TOP = TypeVal(TypeVal.TOP);

/// Analysis output, map of IR values to types
alias TypeVal[IRDstValue] TypeMap; 

/**
Perform type propagation on an intraprocedural CFG using
the sparse conditional constant propagation technique
*/
TypeMap typeProp(IRFunction fun)
{
    // List of CFG edges to be processed
    BranchDesc[] cfgWorkList;

    // List of SSA values to be processed
    IRDstValue[] ssaWorkList;

    // Set of reachable blocks
    bool[IRBlock] reachable;

    // Set of visited edges, indexed by predecessor id, successor id
    bool[BranchDesc] edgeVisited;

    // Map of type values inferred
    TypeVal[IRDstValue] typeMap;

    // Add the entry block to the CFG work list
    cfgWorkList ~= new BranchDesc(null, fun.entryBlock);

    /// Get a type for a given IR value
    auto getType(IRValue val)
    {
        if (auto dstVal = cast(IRDstValue)val)
            return typeMap.get(dstVal, TOP);

        if (cast(IRString)val ||
            cast(IRFunPtr)val ||
            cast(IRLinkIdx)val ||
            cast(IRCachedIdx)val)
            return BOT;

        // Get the constant value pair for this IR value
        auto cstVal = val.cstValue();

        if (cstVal.word == TRUE)
            return TypeVal(true);
        if (cstVal.word == FALSE)
            return TypeVal(false);

        return TypeVal(cstVal.type);
    }

    // Separate function to evaluate phis
    auto evalPhi(PhiNode phi)
    {
        // If this is a function parameter, unknown type
        if (cast(FunParam)phi)
            return BOT;

        TypeVal curType = TOP;

        // For each incoming branch
        for (size_t i = 0; i < phi.block.numIncoming; ++i)
        {
            auto branch = phi.block.getIncoming(i);
            auto argVal = branch.getPhiArg(phi);
            auto argType = getType(argVal);

            // If the edge from the predecessor is not reachable, ignore its value
            if (branch !in edgeVisited)
                continue;

            // If any arg is still unevaluated, the current value is unevaluated
            if (argType == TOP)
                return TOP;

            // If not all uses have the same value, return the non-constant value
            if (argType != curType && curType != TOP)
                return BOT;

            curType = argType;
        }

        // All uses have the same constant type
        return curType;
    }

    // Evaluate an SSA instruction
    auto evalInstr(IRInstr instr)
    {
        auto op = instr.opcode;

        auto arg0Type = (instr.numArgs > 0)? getType(instr.getArg(0)):TOP;

        // Get type
        if (op is &GET_TYPE)
        {
            return arg0Type;
        }

        // Get word
        if (op is &GET_WORD)
        {
            return TypeVal(Type.INT64);
        }

        // Make value
        if (op is &MAKE_VALUE)
        {
            // Unknown type, non-constant
            return BOT;
        }

        // Get argume nt (var arg)
        if (op is &GET_ARG)
        {
            // Unknown type, non-constant
            return BOT;
        }

        // Set string
        if (op is &SET_STR)
        {
            return TypeVal(Type.REFPTR);
        }

        // Get string
        if (op is &GET_STR)
        {
            return TypeVal(Type.REFPTR);
        }

        // Make link
        if (op is &MAKE_LINK)
        {
            return TypeVal(Type.INT32);
        }

        // Get link
        if (op is &GET_LINK)
        {
            // Unknown type, non-constant
            return BOT;
        }

        // Get interpreter objects
        if (op is &GET_GLOBAL_OBJ ||
            op is &GET_OBJ_PROTO ||
            op is &GET_ARR_PROTO ||
            op is &GET_FUN_PROTO)
        {
            return TypeVal(Type.REFPTR);
        }

        // int32 arithmetic/logical
        if (
            op is &ADD_I32 ||
            op is &SUB_I32 ||
            op is &MUL_I32 ||
            op is &DIV_I32 ||
            op is &MOD_I32 ||
            op is &AND_I32 ||
            op is &OR_I32 ||
            op is &XOR_I32 ||
            op is &NOT_I32 ||
            op is &LSFT_I32 ||
            op is &RSFT_I32 ||
            op is &URSFT_I32)
        {
            return TypeVal(Type.INT32);
        }

        // int32 arithmetic with overflow
        if (
            op is &ADD_I32_OVF ||
            op is &SUB_I32_OVF ||
            op is &MUL_I32_OVF)
        {
            // Queue both branch targets
            cfgWorkList ~= instr.getTarget(0);
            cfgWorkList ~= instr.getTarget(1);

            return TypeVal(Type.INT32);
        }

        // float64 arithmetic
        if (
            op is &ADD_F64 ||
            op is &SUB_F64 ||
            op is &MUL_F64 ||
            op is &DIV_F64)
        {
            return TypeVal(Type.FLOAT64);
        }

        // int to float
        if (op is &I32_TO_F64)
        {
            return TypeVal(Type.FLOAT64);
        }

        // float to int
        if (op is &F64_TO_I32)
        {
            return TypeVal(Type.INT32);
        }

        // Load integer
        if (
            op is &LOAD_U8 ||
            op is &LOAD_U16 ||
            op is &LOAD_U32)
        {
            return TypeVal(Type.INT32);
        }

        // Load 64-bit integer
        if (op is &LOAD_U64)
        {
            return TypeVal(Type.INT64);
        }

        // Load f64
        if (op is &LOAD_F64)
        {
            return TypeVal(Type.FLOAT64);
        }

        // Load refptr
        if (op is &LOAD_REFPTR)
        {
            return TypeVal(Type.REFPTR);
        }

        // Load rawptr
        if (op is &LOAD_RAWPTR)
        {
            return TypeVal(Type.RAWPTR);
        }

        // Comparison operations
        if (
            op is &EQ_I8 ||
            op is &LT_I32 ||
            op is &LE_I32 ||
            op is &GT_I32 ||
            op is &GE_I32 ||
            op is &EQ_I32 ||
            op is &NE_I32 ||
            op is &LT_F64 ||
            op is &LE_F64 ||
            op is &GT_F64 ||
            op is &GE_F64 ||
            op is &EQ_F64 ||
            op is &NE_F64 ||
            op is &EQ_CONST ||
            op is &NE_CONST ||
            op is &EQ_REFPTR ||
            op is &NE_REFPTR
        )
        {
            // Constant, boolean type
            return TypeVal(Type.CONST);
        }

        // Read global variable
        if (op is &GET_GLOBAL)
        {
            // Unknown type, non-constant
            return BOT;
        }

        // is_i32
        if (op is &IS_I32)
        {
            if (arg0Type == TOP)
                return TOP;
            if (arg0Type == BOT)
                return TypeVal(Type.CONST);
            return TypeVal(arg0Type.type == Type.INT32);
        }

        // is_f64
        if (op is &IS_F64)
        {
            if (arg0Type == TOP)
                return TOP;
            if (arg0Type == BOT)
                return TypeVal(Type.CONST);
            return TypeVal(arg0Type.type == Type.FLOAT64);
        }

        // is_const
        if (op is &IS_CONST)
        {
            if (arg0Type == TOP)
                return TOP;
            if (arg0Type == BOT)
                return TypeVal(Type.CONST);
            return TypeVal(arg0Type.type == Type.CONST);
        }

        // is_refptr
        if (op is &IS_REFPTR)
        {
            if (arg0Type == TOP)
                return TOP;
            if (arg0Type == BOT)
                return TypeVal(Type.CONST);
            return TypeVal(arg0Type.type == Type.REFPTR);
        }

        // is_rawptr
        if (op is &IS_RAWPTR)
        {
            if (arg0Type == TOP)
                return TOP;
            if (arg0Type == BOT)
                return TypeVal(Type.CONST);
            return TypeVal(arg0Type.type == Type.RAWPTR);
        }

        // Conditional branch
        if (op is &IF_TRUE)
        {
            // If the argument is unevaluated, do nothing
            if (arg0Type is TOP)
                return TOP;

            // If known true or unknown boolean or unknown type
            if ((arg0Type.state == TypeVal.KNOWN_BOOL && arg0Type.val == true) ||
                (arg0Type.state == TypeVal.KNOWN_TYPE) || 
                (arg0Type == BOT))
                cfgWorkList ~= instr.getTarget(0);

            // If known false or unknown boolean or unknown type
            if ((arg0Type.state == TypeVal.KNOWN_BOOL && arg0Type.val == false) ||
                (arg0Type.state == TypeVal.KNOWN_TYPE) || 
                (arg0Type == BOT))
                cfgWorkList ~= instr.getTarget(1);

            return BOT;
        }

        // Call instructions
        if (op.isCall)
        {
            // Queue branch edges
            if (instr.getTarget(0))
                cfgWorkList ~= instr.getTarget(0);
            if (instr.getTarget(1))
                cfgWorkList ~= instr.getTarget(1);

            // Unknown, non-constant type
            return BOT;
        }

        // Direct branch
        if (op is &JUMP)
        {
            // Queue the jump branch edge
            cfgWorkList ~= instr.getTarget(0);
            return BOT;
        }

        // Operations producing no output
        if (op.output is false)
        {
            return BOT;
        }

        // Unsupported operation
        assert (
            op !in codeGenFns,
            "Missing support for op: " ~ op.mnem
        );

        // Return the unknown type
        return BOT;
    }

    // Until a fixed point is reached
    while (cfgWorkList.length > 0 || ssaWorkList.length > 0)
    {
        // Until the CFG work list is processed
        while (cfgWorkList.length > 0)
        {
            // Remove an edge from the work list
            auto edge = cfgWorkList[$-1];
            cfgWorkList.length--;
            auto pred = edge.pred;
            auto succ = edge.succ;

            // If this is not the first visit of this edge, do nothing
            if (edge in edgeVisited)
                continue;

            // Test if this is the first visit to this block
            auto firstVisit = !(succ in reachable);

            // Mark the edge as visited
            edgeVisited[edge] = true;

            // Mark the successor block as reachable
            reachable[succ] = true;

            // For each phi node of the successor block
            for (auto phi = succ.firstPhi; phi !is null; phi = phi.next)
            {
                // Evaluate the phi node
                typeMap[phi] = evalPhi(phi);
            }

            // If this is the first visit
            if (firstVisit is true)
            {
                // For each instruction of the successor block
                for (auto instr = succ.firstInstr; instr !is null; instr = instr.next)
                {
                    // Evaluate the instruction
                    typeMap[instr] = evalInstr(instr);

                    // For each use of the instruction
                    for (auto use = instr.getFirstUse; use !is null; use = use.next)
                    {
                        // If the block of the use is reachable
                        if (use.owner.block in reachable)
                        {
                            // Add the use to the SSA work list
                            ssaWorkList ~= use.owner;
                        }
                    }
                }
            }
        }

        // Until the SSA work list is processed
        while (ssaWorkList.length > 0)
        {
            // Remove an edge from the SSA work list
            auto v = ssaWorkList[$-1];
            ssaWorkList.length--;

            // Evaluate the value of the edge dest
            TypeVal t;
            if (auto phi = cast(PhiNode)v)
                t = evalPhi(phi);
            else if (auto instr = cast(IRInstr)v)
                t = evalInstr(instr);
            else
                assert (false);

            // If the type of the value has changed
            if (t != typeMap[v])
            {
                // Update the value for this instruction
                typeMap[v] = t;

                // For each use of v
                for (auto use = v.getFirstUse; use !is null; use = use.next)
                {
                    // If the block of the use is reachable
                    if (use.owner.block in reachable)
                    {
                        // Add the use to the SSA work list
                        ssaWorkList ~= use.owner;;
                    }
                }
            }
        }
    }

    // Return the type values inferred
    return typeMap;
}

