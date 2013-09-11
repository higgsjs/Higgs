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
import ir.ir;
import interp.interp;

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





        // TODO: handle constants
        return BOT;
    }

    // Separate function to evaluate phis
    auto evalPhi(PhiNode phi)
    {
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

            // If any arg is still top, the current value is unknown
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
        // TODO: map lookup?

        /*
        // If there is a const prop function for this instruction, use it
        if (instr.constEval !== undefined)
        {
            var val = instr.constEval(getValue, edgeReachable, queueEdge, params);

            return val;
        }

        // Otherwise, if this instruction is a generic branch
        else if (instr.isBranch())
        {
            // Put all branches on the CFG work list
            for (var i = 0; i < instr.targets.length; ++i)
            {
                if (instr.targets[i])
                    queueEdge(instr, instr.targets[i]);
            }
        }
        */

        // By default, return the non-constant value
        return BOT;
    }

    // Until a fixed point is reached
    while (cfgWorkList.length > 0 || ssaWorkList.length > 0)
    {
        // Until the CFG work list is processed
        while (cfgWorkList.length > 0)
        {
            /*
            // Remove an edge from the work list
            var edge = cfgWorkList.pop();
            var pred = edge.pred;
            var succ = edge.succ;

            // Test if this edge has already been visited
            var firstEdgeVisit = (edgeVisited[pred.blockId][succ.blockId] !== true);

            // If this is not the first visit of this edge, do nothing
            if (!firstEdgeVisit)
                continue;

            // Test if this is the first visit to this block
            var firstVisit = (reachable[succ.blockId] !== true);

            //print('iterating cfg: ' + succ.getBlockName() + (firstVisit? ' (first visit)':''));

            // Mark the edge as visited
            edgeVisited[pred.blockId][succ.blockId] = true;

            // Mark the successor block as reachable
            reachable[succ.blockId] = true;

            // For each instruction in the successor block
            for (var i = 0; i < succ.instrs.length; ++i)
            {
                var instr = succ.instrs[i];

                // If this is not a phi node and this is not the first visit,
                // do not revisit non-phi instructions
                if (!(instr instanceof PhiInstr) && !firstVisit)
                    break;

                //print('visiting: ' + instr);

                // Evaluate the instruction
                instrVals[instr.instrId] = evalInstr(instr);

                // For each dest of the instruction
                for (var j = 0; j < instr.dests.length; ++j)
                {
                    var dest = instr.dests[j];

                    // If the block of the destination is reachable
                    if (reachable[dest.parentBlock.blockId] === true)
                    {
                        // Add the dest to the SSA work list
                        ssaWorkList.push(dest);
                    }
                }
            }
            */
        }

        // Until the SSA work list is processed
        while (ssaWorkList.length > 0)
        {
            /*
            // Remove an edge from the SSA work list
            var v = ssaWorkList.pop();

            // Evaluate the value of the edge dest
            var t = evalInstr(v);

            //print('iterating ssa: ' + v + ' ==> ' + t);

            // If the instruction value has changed
            //if (t !== instrVals[v.instrId])
            if (t !== getValue(v))
            {
                //print('value changed: ' + v + ' ==> ' + t);

                // Update the value for this instruction
                instrVals[v.instrId] = t;
                
                // For each dest of v
                for (var i = 0; i < v.dests.length; ++i)
                {
                    var dest = v.dests[i];

                    // If the block of the destination is reachable
                    if (reachable[dest.parentBlock.blockId] === true)
                    {
                        // Add the dest to the SSA work list
                        ssaWorkList.push(dest);
                    }
                }
            }
            */
        }
    }

    // Return the type values inferred
    return typeMap;
}

//=============================================================================
//
// Constant propagation functions for IR instructions
//
//=============================================================================

/*
ArithInstr.genConstEval = function (opFunc, genFunc)
{
    function constEval(getValue, edgeReachable, queueEdge, params)
    {
        var v0 = getValue(this.uses[0]);
        var v1 = getValue(this.uses[1]);

        if (v0 === TOP || v1 === TOP)
            return TOP;

        if (v0 instanceof IRConst && v0.isNumber() &&
            v1 instanceof IRConst && v1.isNumber())
        {
            if (v0.isInt() && v1.isInt())
            {
                v0 = v0.getImmValue(params);
                v1 = v1.getImmValue(params);
            }
            else
            {
                v0 = v0.value;
                v1 = v1.value;
            }

            var result = opFunc(v0, v1, this.type);

            if (this.type === IRType.box)
                result = num_shift(result, -params.staticEnv.getBinding('TAG_NUM_BITS_INT').value);

            // If there was no overflow, return the result
            if (this.type.valInRange(result, params))
            {
                return IRConst.getConst(
                    result,
                    this.type
                );
            }
        }

        if (genFunc !== undefined)
        {           
            var u0 = (v0 instanceof IRConst)? v0:this.uses[0];
            var u1 = (v1 instanceof IRConst)? v1:this.uses[1];

            return genFunc(u0, u1, this.type);
        }

        // By default, return the unknown value
        return BOT;
    }

    return constEval;
};

AddInstr.prototype.constEval = ArithInstr.genConstEval(
    function (v0, v1)
    {
        return num_add(v0, v1);
    },
    function (u0, u1)
    {
        if (u0 instanceof IRConst && num_eq(u0.value, 0))
            return u1;

        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

SubInstr.prototype.constEval = ArithInstr.genConstEval(
    function (v0, v1)
    {
        return num_sub(v0, v1);
    },
    function (u0, u1)
    {
        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

MulInstr.prototype.constEval = ArithInstr.genConstEval(
    function (v0, v1)
    {
        return num_mul(v0, v1);
    },
    function (u0, u1, outType)
    {
        if (u0 instanceof IRConst && num_eq(u0.value, 1))
            return u1;

        if (u1 instanceof IRConst && num_eq(u1.value, 1))
            return u0;

        if (((u0 instanceof IRConst && num_eq(u0.value, 0)) || 
             (u1 instanceof IRConst && num_eq(u1.value, 0))) &&
            u0.type === u1.type)
        {
            return IRConst.getConst(
                0,
                outType
            );
        }

        return BOT;
    }
);

DivInstr.prototype.constEval = ArithInstr.genConstEval(
    function (v0, v1, type)
    {
        var res = num_div(v0, v1);

        if (type.isInt() || type === IRType.box)
        {
            if (num_gt(res, 0))
                return Math.floor(res);
            else
                return Math.ceil(res);
        }

        return res;
    },
    function (u0, u1)
    {
        if (u1 instanceof IRConst && num_eq(u1.value, 1))
            return u0;

        return BOT;
    }
);

ModInstr.prototype.constEval = ArithInstr.genConstEval(
    function (v0, v1, type)
    {
        if (type.isInt() && (num_lt(v0, 0) || num_lt(v1, 0)))
            return NaN;

        return num_mod(v0, v1);
    }
);

BitOpInstr.genConstEval = function (opFunc, genFunc)
{
    function constEval(getValue, edgeReachable, queueEdge, params)
    {
        var v0 = getValue(this.uses[0]);
        var v1 = getValue(this.uses[1]);

        if (v0 === TOP || v1 === TOP)
            return TOP;

        // If both values are constant integers
        if (v0 instanceof IRConst && 
            v1 instanceof IRConst &&
            v0.isInt() && v1.isInt() &&
            !(v0.type === IRType.box && !v0.isBoxInt(params)) &&
            !(v1.type === IRType.box && !v1.isBoxInt(params))
        )
        {
            v0 = v0.getImmValue(params);
            v1 = v1.getImmValue(params);

            // If both values fit in the int32 range
            if (IRType.i32.valInRange(v0, params) &&
                IRType.i32.valInRange(v1, params))
            {
                var result = opFunc(v0, v1, this.type, params);

                if (this.type === IRType.box)
                    result = num_shift(result, -params.staticEnv.getBinding('TAG_NUM_BITS_INT').value);

                // If the result is within the range of the output type, return it
                if (this.type.valInRange(result, params))
                {
                    return IRConst.getConst(
                        result,
                        this.type
                    );
                }
            }
        }

        if (genFunc !== undefined)
        {
            var u0 = (v0 instanceof IRConst)? v0:this.uses[0];
            var u1 = (v1 instanceof IRConst)? v1:this.uses[1];

            return genFunc(u0, u1, this.type, params);
        }

        // By default, return the unknown value
        return BOT;
    }

    return constEval;
};

AndInstr.prototype.constEval = BitOpInstr.genConstEval(
    function (v0, v1)
    {
        return num_and(v0, v1);
    },
    function (u0, u1, outType, params)
    {
        var TAG_INT_MASK = params.staticEnv.getBinding('TAG_INT_MASK').value;
        var TAG_REF_MASK = params.staticEnv.getBinding('TAG_REF_MASK').value;

        if ((u0 instanceof IRConst && num_eq(u0.value, 0)) ||
            (u1 instanceof IRConst && num_eq(u1.value, 0)))
        {
            return IRConst.getConst(
                0,
                outType
            );
        }

        if (u0 instanceof IRConst &&
            u1 instanceof IRConst &&
            u0.type === IRType.box &&
            !u0.isBoxInt(params) &&
            u1.type === IRType.pint && 
            num_eq(u1.value, TAG_REF_MASK))
        {
            return IRConst.getConst(
                u0.getTagBits(params),
                IRType.pint
            );
        }

        if (u0 instanceof IRConst &&
            u1 instanceof IRConst &&
            u1.type === IRType.box &&
            !u1.isBoxInt(params) &&
            u0.type === IRType.pint && 
            num_eq(u0.value, TAG_REF_MASK))
        {
            return IRConst.getConst(
                u1.getTagBits(params),
                IRType.pint
            );
        }

        if (u0 instanceof IRConst &&
            u1 instanceof IRConst &&
            u0.type === IRType.box &&
            u1.type === IRType.pint && 
            num_eq(u1.value, TAG_INT_MASK))
        {
            return IRConst.getConst(
                num_and(u0.getTagBits(params), TAG_INT_MASK),
                IRType.pint
            );
        }

        if (u0 instanceof IRConst &&
            u1 instanceof IRConst &&
            u1.type === IRType.box &&
            u0.type === IRType.pint && 
            num_eq(u0.value, TAG_INT_MASK))
        {
            return IRConst.getConst(
                num_and(u1.getTagBits(params), TAG_INT_MASK),
                IRType.pint
            );
        }

        return BOT;
    }
);

OrInstr.prototype.constEval = BitOpInstr.genConstEval(
    function (v0, v1)
    {
        return num_or(v0, v1);
    },
    function (u0, u1, type)
    {
        if (u0 instanceof IRConst && num_eq(u0.value, 0))
            return u1;

        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

XorInstr.prototype.constEval = BitOpInstr.genConstEval(
    function (v0, v1)
    {
        return num_xor(v0, v1);
    }
);

LsftInstr.prototype.constEval = BitOpInstr.genConstEval(
    function (v0, v1)
    {
        return num_shift(v0, v1);
    },
    function (u0, u1, type)
    {
        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

RsftInstr.prototype.constEval = BitOpInstr.genConstEval(
    function (v0, v1)
    {
        return num_shift(v0, -v1);
    },
    function (u0, u1, type)
    {
        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

UrsftInstr.prototype.constEval = BitOpInstr.genConstEval(
    function (v0, v1, type, params)
    {
        return num_urshift(v0, v1, type.getSizeBits(params));
    },
    function (u0, u1, type)
    {
        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

ICastInstr.prototype.constEval = function (getValue, edgeReachable, queueEdge, params)
{
    if (this.uses[0].type === this.type)
        return this.uses[0];

    var v0 = getValue(this.uses[0]);

    if (v0 === TOP)
        return TOP;

    if (v0 instanceof IRConst)
    {
        var result;

        if (v0.type.isInt() && this.type.isInt())
        {
            if (this.type.valInRange(v0.value, params))
                result = v0.value;
        }

        else if (v0.type === IRType.box && v0.isInt() && this.type.isInt())
        {
            var castVal = v0.getImmValue(params);
            
            if (this.type.valInRange(castVal, params))
                result = castVal;
        }

        else if (v0.type.isInt() && this.type === IRType.box)
        {
            var TAG_NUM_BITS_INT = params.staticEnv.getBinding('TAG_NUM_BITS_INT').value;
            var TAG_INT_MASK = params.staticEnv.getBinding('TAG_INT_MASK').value;
            var TAG_INT = params.staticEnv.getBinding('TAG_INT').value;

            // If the tag bits correspond to a boxed integer
            if (num_and(v0.value, TAG_INT_MASK) === TAG_INT)
            {
                var castVal = num_shift(v0.value, -TAG_NUM_BITS_INT);

                if (this.type.valInRange(castVal, params))
                    result = castVal;
            }
        }

        if (result !== undefined)
        {
            return IRConst.getConst(
                result,
                this.type
            );
        }
    }

    return BOT;
};

ArithOvfInstr.genConstEval = function (opFunc, genFunc)
{
    function constEval(getValue, edgeReachable, queueEdge, params)
    {
        var v0 = getValue(this.uses[0]);
        var v1 = getValue(this.uses[1]);

        if (v0 === TOP || v1 === TOP)
        {
            return TOP;
        }

        if (v0 instanceof IRConst && v0.isNumber() &&
            v1 instanceof IRConst && v1.isNumber())
        {
            if (v0.isInt() && v1.isInt())
            {
                v0 = v0.getImmValue(params);
                v1 = v1.getImmValue(params);
            }
            else
            {
                v0 = v0.value;
                v1 = v1.value;
            }

            var result = opFunc(v0, v1);

            if (this.type === IRType.box)
                result = num_shift(result, -params.staticEnv.getBinding('TAG_NUM_BITS_INT').value);

            // If there was no overflow
            if (this.type.valInRange(result, params))
            {
                // Add the normal (non-overflow) branch to the work list
                queueEdge(this, this.targets[0]);

                // Return the result
                return IRConst.getConst(
                    result,
                    this.type
                );
            }
        }

        if (genFunc !== undefined)
        {
            var u0 = (v0 instanceof IRConst)? v0:this.uses[0];
            var u1 = (v1 instanceof IRConst)? v1:this.uses[1];

            var result = genFunc(u0, u1, this.type);

            if (result !== BOT)
            {
                // Add the normal (non-overflow) branch to the work list
                queueEdge(this, this.targets[0]);

                return result;
            }
        }

        // By default, both branches are reachable (an overflow could occur)
        queueEdge(this, this.targets[0]);
        queueEdge(this, this.targets[1]);

        // By default, return the unknown value
        return BOT;
    }

    return constEval;
};

AddOvfInstr.prototype.constEval = ArithOvfInstr.genConstEval(
    function (v0, v1)
    {
        return num_add(v0, v1);
    },
    function (u0, u1)
    {
        if (u0 instanceof IRConst && num_eq(u0.value, 0))
            return u1;

        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

SubOvfInstr.prototype.constEval = ArithOvfInstr.genConstEval(
    function (v0, v1)
    {
        return num_sub(v0, v1);
    },
    function (u0, u1)
    {
        if (u1 instanceof IRConst && num_eq(u1.value, 0))
            return u0;

        return BOT;
    }
);

MulOvfInstr.prototype.constEval = ArithOvfInstr.genConstEval(
    function (v0, v1)
    {
        return num_mul(v0, v1);
    },
    function (u0, u1, outType)
    {
        if (u0 instanceof IRConst && num_eq(u0.value, 1))
            return u1;

        if (u1 instanceof IRConst && num_eq(u1.value, 1))
            return u0;

        if (((u0 instanceof IRConst && num_eq(u0.value, 0)) ||
             (u1 instanceof IRConst && num_eq(u1.value, 0))) &&
            u0.type === u1.type)
        {
            return IRConst.getConst(
                0,
                outType
            );
        }

        return BOT;
    }
);

LsftOvfInstr.prototype.constEval = ArithOvfInstr.genConstEval(
    function (v0, v1)
    {
        return num_shift(v0, v1);
    }
);

function constEvalBool(val)
{
    // If the test is a constant
    if (val instanceof IRConst)
    {
        // If the test evaluates to true
        if (
            val.value === true ||
            (val.isNumber() && num_ne(val.value, 0)) ||
            (val.isString() && val.value !== '')
        )
        {
            return IRConst.getConst(true);
        }

        // If the test evaluates to false
        else if (
            val.value === false ||
            val.value === null ||
            val.value === undefined ||
            val.value === '' ||
            num_eq(val.value, 0)
        )
        {
            return IRConst.getConst(false);
        }
    }

    // Return the non-constant value
    return BOT;
}

CallFuncInstr.prototype.constEval = function (getValue, edgeReachable, queueEdge, params)
{
    // If this is a call to boxToBool
    if (this.getCallee() instanceof IRFunction && 
        this.getCallee() === params.staticEnv.getBinding('boxToBool'))
    {
        // Evaluate the boolean value
        var boolVal = constEvalBool(getValue(this.uses[this.uses.length-1]));

        // If we could evaluate the boolean value, return it
        if (boolVal instanceof IRConst)
            return boolVal;
    }

    // Add all branch targets to the CFG work list
    for (var i = 0; i < this.targets.length; ++i)
        if (this.targets[i])
            queueEdge(this, this.targets[i]);

    return BOT;
};

IfInstr.prototype.constEval = function (getValue, edgeReachable, queueEdge, params)
{
    var v0 = getValue(this.uses[0]);
    var v1 = getValue(this.uses[1]);

    // Comparison test value, by default, it is unknown (bottom)
    var testVal = BOT;

    if (v0 === TOP || v1 === TOP)
        testVal = TOP;

    if (v0 instanceof IRConst && v1 instanceof IRConst)
    {
        v0 = v0.value;
        v1 = v1.value;

        // If this is a number comparison
        if (num_instance(v0) && num_instance(v1))
        {
            switch (this.testOp)
            {
                case 'LT': testVal = num_lt(v0, v1); break;
                case 'LE': testVal = num_le(v0, v1); break;
                case 'GT': testVal = num_gt(v0, v1); break;
                case 'GE': testVal = num_ge(v0, v1); break;
                case 'EQ': testVal = num_eq(v0, v1); break;
                case 'NE': testVal = num_ne(v0, v1); break;
            }
        }

        // If this is a boolean or string comparison
        if ((typeof v0 === 'boolean' && typeof v1 === 'boolean') ||
            (typeof v0 === 'string' && typeof v1 === 'string'))
        {
            switch (this.testOp)
            {
                case 'EQ': testVal = (v0 === v1); break;
                case 'NE': testVal = (v0 !== v1); break;
            }
        }
    }

    //print(testVal);

    // If the test evaluates to true
    if (testVal === true)
    {
        // Add the true branch to the work list
        queueEdge(this, this.targets[0]);
    }

    // If the test evaluates to false
    else if (testVal === false)
    {
        // Add the false branch to the work list
        queueEdge(this, this.targets[1]);
    }

    // If test is non-constant, both branches are reachable
    else if (testVal === BOT)
    {
        queueEdge(this, this.targets[0]);
        queueEdge(this, this.targets[1]);
    }

    // Return the test value
    return testVal;
}
*/

