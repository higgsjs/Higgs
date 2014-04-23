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

module ir.typeprop;

import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.conv;
import ir.ir;
import ir.ops;
import runtime.vm;
import jit.ops;

/// Type test result
enum TestResult
{
    TRUE,
    FALSE,
    UNKNOWN
}

/**
Type analysis results for a given function
*/
class TypeProp
{
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

        string toString() const
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

        /// Compute the merge (union) with another type value
        TypeVal merge(TypeVal that)
        {
            // If one of the values is uninferred
            if (this.state is TOP)
                return that;
            if (that.state is TOP)
                return this;

            // If one of the values is non-constant
            if (this.state is BOT || that.state is BOT)
                return TypeVal(BOT);

            // If the types are equal
            if (this == that)
                return this;

            // If this is a known boolean and so is the other value
            if (this.state is KNOWN_BOOL && that.state is KNOWN_BOOL)
            {
                assert (this.val !is that.val);
                return TypeVal(Type.CONST);
            }

            // The type is unknown, non-constant
            assert (!(this.state is that.state && this.type is that.type));
            return TypeVal(BOT);
        }
    }

    /// Uninferred type value
    static const TOP = TypeVal(TypeVal.TOP);

    /// Non-constant (any type) value
    static const BOT = TypeVal(TypeVal.BOT);

    /// Map of IR values to types
    alias TypeVal[IRDstValue] TypeMap;






    // FIXME: query by location?
    // TODO: query function
    // TODO: probably need to be like liveness analysis, have query locations?
    // - have a map of values to type maps?
    public TestResult isTypeAt(IRValue val, Type type, IRInstr testInstr)
    {
        return TestResult.UNKNOWN;
    }




    // TODO: trim dead values





    /**
    Perform type propagation on an intraprocedural CFG using
    the sparse conditional constant propagation technique
    */
    public this(IRFunction fun)
    {
        //writeln(fun);

        // List of CFG edges to be processed
        BranchEdge[] cfgWorkList;

        // Set of reachable blocks
        bool[IRBlock] reachable;

        // Set of visited edges
        bool[BranchEdge] edgeVisited;

        // Map of branch edges to type maps
        TypeMap[BranchEdge] edgeMaps;

        // Add the entry block to the CFG work list
        auto entryEdge = new BranchEdge(null, fun.entryBlock);
        cfgWorkList ~= entryEdge;

        /// Get a type for a given IR value
        auto getType(TypeMap typeMap, IRValue val)
        {
            if (auto dstVal = cast(IRDstValue)val)
                return typeMap.get(dstVal, TOP);

            if (cast(IRString)val ||
                cast(IRFunPtr)val ||
                cast(IRMapPtr)val ||
                cast(IRLinkIdx)val)
                return BOT;

            // Get the constant value pair for this IR value
            auto cstVal = val.cstValue();

            if (cstVal == TRUE)
                return TypeVal(true);
            if (cstVal == FALSE)
                return TypeVal(false);

            return TypeVal(cstVal.type);
        }

        /// Queue a branch into the work list
        void queueSucc(BranchEdge edge, TypeMap typeMap, IRDstValue branch, TypeVal branchType)
        {
            //writeln(branch);
            //writeln("  ", branchType);

            // Flag to indicate the branch type map changed
            bool changed = false;

            // Get the map for this edge
            if (edge !in edgeMaps)
                edgeMaps[edge] = TypeMap.init;
            auto edgeMap = edgeMaps[edge];

            // If a value to be propagated was specified, merge it
            if (branch !is null)
            {
                auto curType = getType(edgeMap, branch);
                auto newType = curType.merge(branchType);
                if (newType != curType)
                {
                    //writeln(branch, " ==> ", newType);

                    edgeMaps[edge][branch] = newType;
                    changed = true;
                }
            }

            // For each type in the incoming map
            foreach (val, inType; typeMap)
            {
                // If this is the value to be propagated,
                // don't propagate the old value
                if (val is branch)
                    continue;

                // Compute the merge of the current and new type
                auto curType = getType(edgeMap, val);
                auto newType = curType.merge(inType);

                // If the type changed, update it
                if (newType != curType)
                {
                    //writeln(val, " ==> ", newType);

                    edgeMaps[edge][val] = newType;
                    changed = true;
                }
            }

            // If the type map changed, queue this edge
            if (changed)
                cfgWorkList ~= edge;
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
                auto edge = phi.block.getIncoming(i);

                // If the edge from the predecessor is not reachable, ignore its value
                if (edge !in edgeVisited)
                    continue;

                auto argVal = edge.getPhiArg(phi);
                auto argType = getType(edgeMaps[edge], argVal);

                // If any arg is still unevaluated, the current value is unevaluated
                if (argType == TOP)
                    return TOP;

                // Merge the argument type with the current type
                curType = curType.merge(argType);
            }

            // All uses have the same constant type
            return curType;
        }

        /// Evaluate an instruction
        auto evalInstr(IRInstr instr, TypeMap typeMap)
        {
            auto op = instr.opcode;

            // Get the type for argument 0
            auto arg0Type = (instr.numArgs > 0)? getType(typeMap, instr.getArg(0)):TOP;

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

            // Get link value
            if (op is &GET_LINK)
            {
                // Unknown type, value could have any type
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

            // Read global variable
            if (op is &GET_GLOBAL)
            {
                // Unknown type, non-constant
                return BOT;
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
                auto intType = TypeVal(Type.INT32);

                // Queue both branch targets
                queueSucc(instr.getTarget(0), typeMap, instr, intType);
                queueSucc(instr.getTarget(1), typeMap, instr, intType);

                return intType;
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

            // float to string
            if (op is &F64_TO_STR)
            {
                return TypeVal(Type.STRING);
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

            // Load funptr
            if (op is &LOAD_FUNPTR)
            {
                return TypeVal(Type.FUNPTR);
            }

            // Load mapptr
            if (op is &LOAD_MAPPTR)
            {
                return TypeVal(Type.MAPPTR);
            }

            // Load rawptr
            if (op is &LOAD_RAWPTR)
            {
                return TypeVal(Type.RAWPTR);
            }

            // Heap alloc untyped
            if (op is &ALLOC_REFPTR)
            {
                return TypeVal(Type.REFPTR);
            }

            // Heap alloc string
            if (op is &ALLOC_STRING)
            {
                return TypeVal(Type.STRING);
            }

            // Heap alloc object
            if (op is &ALLOC_OBJECT)
            {
                return TypeVal(Type.OBJECT);
            }

            // Heap alloc array
            if (op is &ALLOC_ARRAY)
            {
                return TypeVal(Type.ARRAY);
            }

            // Heap alloc closure
            if (op is &ALLOC_CLOSURE)
            {
                return TypeVal(Type.CLOSURE);
            }

            // Make map
            if (op is &MAKE_MAP)
            {
                return TypeVal(Type.MAPPTR);
            }

            // Map property count
            if (op is &MAP_NUM_PROPS)
            {
                return TypeVal(Type.INT32);
            }

            // Map property index
            if (op is &MAP_PROP_IDX)
            {
                return TypeVal(Type.INT32);
            }

            // New closure
            if (op is &NEW_CLOS)
            {
                return TypeVal(Type.CLOSURE);
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
                op is &NE_REFPTR ||
                op is &EQ_RAWPTR ||
                op is &NE_RAWPTR

            )
            {
                // Constant, boolean type
                return TypeVal(Type.CONST);
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

            // is_object
            if (op is &IS_OBJECT)
            {
                if (arg0Type == TOP)
                    return TOP;
                if (arg0Type == BOT)
                    return TypeVal(Type.CONST);
                return TypeVal(arg0Type.type == Type.OBJECT);
            }

            // is_array
            if (op is &IS_ARRAY)
            {
                if (arg0Type == TOP)
                    return TOP;
                if (arg0Type == BOT)
                    return TypeVal(Type.CONST);
                return TypeVal(arg0Type.type == Type.ARRAY);
            }

            // is_closure
            if (op is &IS_CLOSURE)
            {
                if (arg0Type == TOP)
                    return TOP;
                if (arg0Type == BOT)
                    return TypeVal(Type.CONST);
                return TypeVal(arg0Type.type == Type.CLOSURE);
            }

            // is_string
            if (op is &IS_STRING)
            {
                if (arg0Type == TOP)
                    return TOP;
                if (arg0Type == BOT)
                    return TypeVal(Type.CONST);
                return TypeVal(arg0Type.type == Type.STRING);
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

                auto instrArg = cast(IRInstr)instr.getArg(0);

                IRValue propVal;
                TypeVal propType;

                if (instrArg && instrArg.opcode is &IS_I32)
                {
                    propVal = instrArg.getArg(0);
                    propType = TypeVal(Type.INT32);
                }
                else if (instrArg && instrArg.opcode is &IS_F64)
                {
                    propVal = instrArg.getArg(0);
                    propType = TypeVal(Type.FLOAT64);
                }
                else if (instrArg && instrArg.opcode is &IS_CONST)
                {
                    propVal = instrArg.getArg(0);
                    propType = TypeVal(Type.CONST);
                }
                else if (instrArg && instrArg.opcode is &IS_REFPTR)
                {
                    propVal = instrArg.getArg(0);
                    propType = TypeVal(Type.REFPTR);
                }
                else if (instrArg && instrArg.opcode is &IS_RAWPTR)
                {
                    propVal = instrArg.getArg(0);
                    propType = TypeVal(Type.RAWPTR);
                }
                // TODO
                // TODO: missing types
                // TODO

                // If known true or unknown boolean or unknown type
                if ((arg0Type.state == TypeVal.KNOWN_BOOL && arg0Type.val == true) ||
                    (arg0Type.state == TypeVal.KNOWN_TYPE) ||
                    (arg0Type == BOT))
                    queueSucc(instr.getTarget(0), typeMap, cast(IRDstValue)propVal, propType);

                // If known false or unknown boolean or unknown type
                if ((arg0Type.state == TypeVal.KNOWN_BOOL && arg0Type.val == false) ||
                    (arg0Type.state == TypeVal.KNOWN_TYPE) ||
                    (arg0Type == BOT))
                    queueSucc(instr.getTarget(1), typeMap, null, BOT);

                return BOT;
            }

            // Call instructions
            if (op.isCall)
            {
                // Queue branch edges
                if (instr.getTarget(0))
                    queueSucc(instr.getTarget(0), typeMap, instr, BOT);
                if (instr.getTarget(1))
                    queueSucc(instr.getTarget(1), typeMap, instr, BOT);

                // Unknown, non-constant type
                return BOT;
            }

            // Direct branch
            if (op is &JUMP)
            {
                // Queue the jump branch edge
                queueSucc(instr.getTarget(0), typeMap, instr, BOT);
            }

            // Operations producing no output
            if (op.output is false)
            {
                // Return the unknown type
                return BOT;
            }

            // Ensure that we produce a type for all instructions with an output
            assert (
                false,
                format("unhandled instruction: %s", instr)
            );
        }

        // Until the work list is empty
        while (cfgWorkList.length > 0)
        {
            // Remove an edge from the work list
            auto edge = cfgWorkList[$-1];
            cfgWorkList.length--;
            auto block = edge.target;

            //writeln("iterating ", block.getName);

            // Mark the edge and block as visited
            edgeVisited[edge] = true;
            reachable[block] = true;

            // Type map for the current program point
            TypeMap typeMap;

            // For each incoming branch
            for (size_t i = 0; i < block.numIncoming; ++i)
            {
                auto branch = block.getIncoming(i);

                // If the edge from the predecessor is not reachable, ignore its value
                if (branch !in edgeVisited)
                    continue;

                // For each value/type pair in the predecessor map
                auto predMap = edgeMaps[branch];
                foreach (val, predType; predMap)
                {
                    typeMap[val] = predType.merge(typeMap.get(val, TOP));
                }
            }

            // For each phi node
            for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
            {
                // Re-evaluate the type of the phi node
                typeMap[phi] = evalPhi(phi);
            }

            // For each instruction
            for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
            {
                typeMap[instr] = evalInstr(instr, typeMap);

                //writeln(instr, " => ", outTypes[instr]);
            }
        }
    }
}
