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

module ir.ir;

import std.stdio;
import std.array;
import std.string;
import std.stdint;
import std.typecons;
import std.conv;
import std.regex;
import util.id;
import util.string;
import parser.ast;
import ir.ops;
import interp.interp;
import interp.layout;
import jit.codeblock;

/// Local variable index type
alias uint32 LocalIdx;

/// Link table index type
alias uint32 LinkIdx;

/// Null local constant
immutable LocalIdx NULL_LOCAL = LocalIdx.max;

/// Null link constant
immutable LocalIdx NULL_LINK = LinkIdx.max;

/// Number of hidden function arguments
immutable uint32_t NUM_HIDDEN_ARGS = 4;

/***
IR function
*/
class IRFunction : IdObject
{
    /// Corresponding AST node
    FunExpr ast;

    /// Function name
    string name = "";

    /// Entry block
    IRBlock entryBlock = null;

    /// First and last basic blocks
    IRBlock firstBlock = null;
    IRBlock lastBlock = null;

    // Number of visible parameters
    uint32_t numParams = 0;

    /// Total number of locals, including parameters and temporaries
    uint32_t numLocals = 0;

    /// Hidden argument SSA values
    FunParam raVal;
    FunParam closVal;
    FunParam thisVal;
    FunParam argcVal;

    /// Map of parameters to SSA values
    FunParam[IdentExpr] paramMap;

    /// Map of identifiers to SSA cell values (closure/shared variables)
    IRValue[IdentExpr] cellMap;

    /// Callee profiling information (filled by interpreter)
    uint64_t[IRFunction][IRInstr] callCounts;  

    /// Map of call instructions to list of inlined functions
    IRFunction[][IRInstr] inlineMap;

    /// Compiled code block
    CodeBlock codeBlock = null;

    /// Constructor
    this(FunExpr ast)
    {
        this.name = ast.getName();
        this.ast = ast;
        this.numParams = cast(uint32_t)ast.params.length;

        // If the function is anonymous
        if (this.name == "")
        {
            if (cast(ASTProgram)ast)
            {
                this.name = ast.pos.file? ast.pos.file:"";
                enum notAlnum = ctRegex!(`[^0-9|a-z|A-Z]`, "g");
                this.name = this.name.replace(notAlnum, "_");
            }
            else
            {
                this.name = "anon";
            }
        }
    }

    string getName()
    {
        return this.name ~ "(" ~ idString() ~ ")";
    }

    override string toString()
    {
        auto output = appender!string();

        output.put("function ");
        output.put(getName());

        // Parameters
        output.put("(");
        output.put("ra:" ~ raVal.getName() ~ ", ");
        output.put("clos:" ~ closVal.getName() ~ ", ");
        output.put("this:" ~ thisVal.getName() ~ ", ");
        output.put("argc:" ~ argcVal.getName());

        foreach (argIdx, var; ast.params)
        {
            auto paramVal = paramMap[var];
            output.put(", " ~ var.toString() ~ ":" ~ paramVal.getName());
        }
        output.put(")");

        // Captured variables
        output.put(" [");
        foreach (varIdx, var; ast.captVars)
        {
            auto cellVal = cellMap[var];
            output.put(var.toString() ~ ":" ~ cellVal.getName());
            if (varIdx < ast.captVars.length - 1)
                output.put(", ");
        }
        output.put("]");

        output.put("\n{\n");

        for (IRBlock block = firstBlock; block !is null; block = block.next)
        {
            auto blockStr = block.toString();
            output.put(indent(blockStr, "  ") ~ "\n");
        }

        output.put("}");

        return output.data;
    }

    IRBlock newBlock(string name)
    {
        auto block = new IRBlock(name);
        this.addBlock(block);
        return block;
    }

    void addBlock(IRBlock block)
    {
        if (this.lastBlock)
        {
            block.prev = lastBlock;
            block.next = null;
            lastBlock.next = block;
            lastBlock = block;
        }
        else
        {
            block.prev = null;
            block.next = null;
            firstBlock = block;
            lastBlock = block;
        }

        block.fun = this;
    }

    void remBlock(IRBlock block)
    {
        if (block.prev)
            block.prev.next = block.next;
        else
            firstBlock = null;

        if (block.next)
            block.next.prev = block.prev;
        else
            lastBlock = null;

        block.prev = null;
        block.next = null;
    }
}

/// Compiled function entry point
alias void function() EntryFn;

/**
SSA IR basic block
*/
class IRBlock : IdObject
{
    /// Block name (non-unique)
    private string name;

    /// List of incoming branches
    private BranchDesc[] incoming;

    /// Execution count, for profiling
    uint64 execCount = 0;

    /// JIT code entry point function
    EntryFn entryFn = null;

    /// JIT code fast entry point
    ubyte* jitEntry = null;

    /// Parent function
    IRFunction fun = null;

    /// Linked list of phi nodes
    PhiNode firstPhi = null;
    PhiNode lastPhi = null;

    /// Linked list of instructions
    IRInstr firstInstr = null;
    IRInstr lastInstr = null;
    
    /// Previous and next block (linked list)
    IRBlock prev = null;
    IRBlock next = null;

    this(string name = "")
    {
        this.name = name;
    }

    IRBlock dup()
    {
        auto that = new IRBlock(this.name);

        that.execCount = this.execCount;
        that.fun = this.fun;

        for (auto phi = firstPhi; phi !is null; phi = phi.next)
            that.addPhi(phi.dup);
        
        for (auto instr = firstInstr; instr !is null; instr = instr.next)
            that.addInstr(instr.dup);

        return that;
    }

    string getName()
    {
        return this.name ~ "(" ~ idString() ~ ")";
    }

    override string toString()
    {
        auto output = appender!string();

        output.put(this.getName() ~ ":\n");

        for (auto phi = firstPhi; phi !is null; phi = phi.next)
        {
            auto phiStr = phi.toString();
            output.put(indent(phiStr, "  "));
            if (phi.next !is null || firstInstr !is null)
                output.put("\n");
        }

        for (auto instr = firstInstr; instr !is null; instr = instr.next)
        {
            auto instrStr = instr.toString();
            output.put(indent(instrStr, "  "));
            if (instr.next !is null)
                output.put("\n");
        }

        return output.data;
    }

    /**
    Add an instruction at the end of the block
    */
    IRInstr addInstr(IRInstr instr)
    {
        if (this.lastInstr)
        {
            instr.prev = lastInstr;
            instr.next = null;
            lastInstr.next = instr;
            lastInstr = instr;
        }
        else
        {
            instr.prev = null;
            instr.next = null;
            firstInstr = instr;
            lastInstr = instr;
        }

        instr.block = this;

        return instr;
    }

    /**
    Add an instruction after another instruction
    */
    IRInstr addInstrAfter(IRInstr instr, IRInstr prev)
    {
        auto next = prev.next;

        instr.prev = prev;
        instr.next = next;

        prev.next = instr;

        if (next !is null)
            next.prev = instr;
        else
            this.lastInstr = instr;

        instr.block = this;

        return instr;
    }

    /**
    Add an instruction before another instruction
    */
    IRInstr addInstrBefore(IRInstr instr, IRInstr next)
    {
        auto prev = next.prev;

        instr.prev = prev;
        instr.next = next;

        next.prev = instr;

        if (prev !is null)
            prev.next = instr;
        else
            this.firstInstr = instr;

        instr.block = this;

        return instr;
    }

    /**
    Remove an instruction
    */
    void remInstr(IRInstr instr)
    {
        if (instr.prev)
            instr.prev.next = instr.next;
        else
            firstInstr = instr.next;

        if (instr.next)
            instr.next.prev = instr.prev;
        else
            lastInstr = instr.prev;

        instr.prev = null;
        instr.next = null;
        instr.block = null;
    }

    /**
    Add a phi node to this block
    */
    PhiNode addPhi(PhiNode phi)
    {
        if (this.lastPhi)
        {
            phi.prev = lastPhi;
            phi.next = null;
            lastPhi.next = phi;
            lastPhi = phi;
        }
        else
        {
            phi.prev = null;
            phi.next = null;
            firstPhi = phi;
            lastPhi = phi;
        }

        phi.block = this;

        return phi;
    }

    /**
    Remove a phi node
    */
    void remPhi(PhiNode phi)
    {
        if (phi.prev)
            phi.prev.next = phi.next;
        else
            firstPhi = phi.next;

        if (phi.next)
            phi.next.prev = phi.prev;
        else
            lastPhi = phi.prev;

        phi.prev = null;
        phi.next = null;
        phi.block = null;

        // Remove the incoming arguments to this phi node
        foreach (descIdx, desc; incoming)
            desc.remPhiArg(phi);
    }

    void addIncoming(BranchDesc branch)
    {
        incoming ~= branch;
    }

    void remIncoming(BranchDesc branch)
    {
        foreach (idx, entry; incoming)
        {
            if (entry is branch)
            {
                incoming[idx] = incoming[$-1];
                incoming.length -= 1;
                return;
            }
        }

        assert (false);
    }
}

/**
Branch edge descriptor
*/
class BranchDesc
{
    /// Branch predecessor block
    IRBlock pred;

    /// Branch successor block
    IRBlock succ;

    /// Mapping of incoming phi values (block arguments)
    Use args[];

    this(IRBlock pred, IRBlock succ)
    {
        this.pred = pred;
        this.succ = succ;
    }

    /**
    Set the value of this edge's branch argument to a phi node
    */
    void setPhiArg(PhiNode phi, IRValue val)
    {
        // For each existing branch argument
        foreach (arg; args)
        {
            // If this pair goes to the selected phi node
            if (arg.owner is phi)
            {
                // If the argument changed, remove the current use
                if (arg.value !is null)
                    arg.value.remUse(arg);

                // Set the new value
                arg.value = val;

                // Add a use to the new value
                val.addUse(arg);

                return;
            }
        }

        // Create a new argument
        auto arg = new Use(val, phi);
        args ~= arg;

        // Add a use to the new source value
        val.addUse(arg);

        assert (arg.owner is phi);
    }

    /// Remove the argument to a phi node
    void remPhiArg(PhiNode phi)
    {
        writeln("******** REMOVING PHI ARG");

        // For each existing branch argument
        foreach (argIdx, arg; args)
        {
            // If this pair goes to the selected phi node
            if (arg.owner is phi)
            {
                args[argIdx] = args[$-1];
                args.length = args.length - 1;

                // TODO: remUse

                return;
            }
        }
    }
}

/**
IR value use instance
*/
class Use
{
    this(IRValue value, IRDstValue owner)
    {
        assert (owner !is null);
        this.value = value;
        this.owner = owner;
    }

    // Value this use refers to
    IRValue value = null;

    // Owner of this use
    IRDstValue owner = null;

    Use prev = null;
    Use next = null;
}

/**
Base class for IR/SSA values
*/
abstract class IRValue : IdObject
{
    /// Linked list of destinations
    private Use firstUse = null;

    /// Register a use of this value
    private void addUse(Use use)
    {
        assert (use !is null);
        assert (use.value is this);
        assert (use.owner !is null);

        use.prev = null;
        use.next = firstUse;

        firstUse = use;
    }

    /// Unregister a use of this value
    private void remUse(Use use)
    {
        assert (use.value is this);

        if (use.prev is null)
            firstUse = null;
        else
            use.prev.next = use.next;

        if (use.next !is null)
            use.next.prev = use.prev;
    }

    /// Get the first use of this value
    Use getFirstUse()
    {
        return firstUse;
    }

    /// Test if this value has a single use
    bool hasOneUse()
    {
        return firstUse !is null && firstUse.next is null;
    }

    /// Test if this value has no uses
    bool hasNoUses()
    {
        return firstUse is null;
    }

    /// Replace uses of this value by uses of another value
    void replUses(IRValue newVal)
    {
        assert (newVal !is null);


        writefln("************* replUses of: %s, by: %s", this.toString(), newVal.toString());



        // Find the last use of the new value
        auto lastUse = newVal.firstUse; 
        while (lastUse !is null && lastUse.next !is null)
            lastUse = lastUse.next;

        // Make all our uses point to the new value
        for (auto use = this.firstUse; use !is null; use = use.next)
            use.value = newVal;

        // Chain all our uses at end of the new value's uses
        if (lastUse !is null)
        {
            lastUse.next = this.firstUse;
            this.firstUse.prev = lastUse;
        }
        else
        {
            newVal.firstUse = this.firstUse;
        }

        // There are no more uses of this value
        this.firstUse = null;
    }

    /// Get the short name for this value
    string getName()
    {
        // By default, just use the string representation
        return toString();
    }
}

/**
SSA constant and constant pools/instances
*/
class IRConst : IRValue
{
    /// Value of this constant
    private ValuePair value;

    override string toString() 
    {
        return valToString(value);
    }

    ValuePair pair() { return value; }
    Word word() { return value.word; }
    Type type() { return value.type; }    

    static IRConst int32Cst(int32 val)
    {
        if (val in int32Vals)
            return int32Vals[val];

        auto cst = new IRConst(Word.int32v(val), Type.INT32);
        int32Vals[val] = cst;
        return cst;
    }

    static IRConst int64Cst(int64 val)
    {
        if (val in int64Vals)
            return int64Vals[val];

        auto cst = new IRConst(Word.int64v(val), Type.INT64);
        int64Vals[val] = cst;
        return cst;
    }

    static IRConst float64Cst(float64 val)
    {
        if (val in float64Vals)
            return float64Vals[val];

        auto cst = new IRConst(Word.float64v(val), Type.FLOAT64);
        float64Vals[val] = cst;
        return cst;
    }

    static IRConst trueCst() 
    { 
        if (!trueVal) trueVal = new IRConst(TRUE , Type.CONST); 
        return trueVal;
    }

    static IRConst falseCst()
    {
        if (!falseVal) falseVal = new IRConst(FALSE, Type.CONST); 
        return falseVal;
    }

    static IRConst undefCst()
    {
        if (!undefVal) undefVal = new IRConst(UNDEF, Type.CONST);
        return undefVal;
    }

    static IRConst missingCst()
    {
        if (!missingVal) missingVal = new IRConst(MISSING, Type.CONST);
        return missingVal;
    }

    static IRConst nullCst()  
    { 
        if (!nullVal) nullVal = new IRConst(NULL, Type.REFPTR);
        return nullVal;
    }

    private static IRConst trueVal = null;
    private static IRConst falseVal = null;
    private static IRConst undefVal = null;
    private static IRConst missingVal = null;
    private static IRConst nullVal = null;

    private static IRConst[int32] int32Vals;
    private static IRConst[int64] int64Vals;
    private static IRConst[float64] float64Vals;

    private this(Word word, Type type)
    {
        this.value = ValuePair(word, type);
    }
}

/**
String constant value
*/
class IRString : IRValue
{
    const wstring str;

    this(wstring str)
    {
        assert (str !is null);
        this.str = str;
    }

    override string toString()
    {
        return "\"" ~ to!string(str) ~ "\"";
    }
}

/**
Raw pointer constant
*/
class IRRawPtr : IRValue
{
    ValuePair ptr;

    this(rawptr ptr)
    {
        this.ptr = ValuePair(Word.ptrv(ptr), Type.RAWPTR);
    }

    override string toString()
    {
        auto p = ptr.word.ptrVal;
        return "<rawptr:" ~ ((p is null)? "NULL":"0x"~to!string(p)) ~ ">";
    }
}

/**
IR function pointer constant
*/
class IRFunPtr : IRValue
{
    IRFunction fun;

    this(IRFunction fun)
    {
        assert (fun !is null);
        this.fun = fun;
    }

    override string toString()
    {
        return "<fun:" ~ fun.getName() ~ ">";
    }
}

/**
Link index pointer value (stateful, non-constant, initially null)
*/
class IRLinkIdx : IRValue
{
    LinkIdx linkIdx = NULL_LINK;

    this()
    {
    }

    override string toString()
    {
        return "<link:" ~ ((linkIdx is NULL_LINK)? "NULL":to!string(linkIdx)) ~ ">";
    }
}

/**
Cached index value (stateful, non-constant)
*/
class IRCachedIdx : IRValue
{
    uint32_t idx = uint32_t.max;

    this()
    {
    }

    bool isNull()
    {
        return idx == idx.max;
    }

    override string toString()
    {
        return "<idx:" ~ ((idx is idx.max)? "NULL":to!string(idx)) ~ ">";
    }
}

/**
Code block pointer value (stateful, non-constant, initially null)
*/
class IRCodeBlock : IRValue
{
    CodeBlock codeBlock = null;

    this()
    {
    }

    override string toString()
    {
        return "<codeblock:" ~ ((codeBlock is null)? "NULL":"0x"~to!string(codeBlock.getAddress())) ~ ">";
    }
}

/**
Base class for IR values usable as destinations 
(phi nodes, fun params, instructions)
*/
abstract class IRDstValue : IRValue
{
    /// Parent block
    IRBlock block = null;

    /// Output stack slot
    LocalIdx outSlot = NULL_LOCAL;

    /// Get the short name string associated with this instruction
    override string getName()
    {
        if (outSlot !is NULL_LOCAL)
            return "$" ~ to!string(outSlot);

        return "t_" ~ idString();
    }
}

/**
Phi node value
*/
class PhiNode : IRDstValue
{
    /// Previous and next phi nodes (linked list)
    PhiNode prev = null;
    PhiNode next = null;

    /// Copy a phi node
    PhiNode dup()
    {
        auto that = new PhiNode();
        return that;
    }

    override string toString()
    {
        string output;

        output ~= getName() ~ " = [";          

        // For each incoming branch
        foreach (descIdx, desc; block.incoming)
        {
            // For each branch argument
            foreach (arg; desc.args)
            {
                if (arg.owner is this)
                {
                    if (descIdx > 0)
                        output ~= ", ";

                    // Find the index of this branch target
                    auto branch = desc.pred.lastInstr;
                    assert (branch !is null);
                    size_t tIdx = size_t.max;
                    for (size_t idx = 0; idx < branch.MAX_TARGETS; ++idx)
                        if (branch.getTarget(idx) is desc)
                            tIdx = idx;
                    assert (tIdx != size_t.max);

                    output ~= desc.pred.getName() ~ ":" ~ to!string(tIdx);
                    output ~= " => " ~ arg.value.getName();

                    break;
                }
            }
        }

        output ~= "]";

        return output;
    }
}

/**
Function parameter value
@extends PhiNode
*/
class FunParam : PhiNode
{
    wstring name;
    uint32_t idx;

    this(wstring name, uint32_t idx)
    {
        this.name = name;
        this.idx = idx;
    }

    /// Get the short name string associated with this argument
    override string getName()
    {
        if (outSlot !is NULL_LOCAL)
            return "$" ~ to!string(outSlot);

        return "arg_" ~ to!string(idx);
    }

    override string toString()
    {
        if (outSlot !is NULL_LOCAL)
            return "$" ~ to!string(outSlot) ~ " = arg_" ~ to!string(idx);

        return "arg_" ~ to!string(idx);
    }
}

/**
SSA instruction
*/
class IRInstr : IRDstValue
{
    /// Maximum number of branch targets
    static const MAX_TARGETS = 2;

    /// Opcode
    Opcode* opcode;

    /// Arguments to this instruction
    private Use[] args;

    /// Branch targets 
    private BranchDesc[MAX_TARGETS] targets = [null, null];

    /// Previous and next instructions (linked list)
    IRInstr prev = null;
    IRInstr next = null;

    /// Default constructor
    this(Opcode* opcode, size_t numArgs = 0)
    {
        assert (
            (numArgs == opcode.argTypes.length) ||
            (numArgs >  opcode.argTypes.length && opcode.isVarArg),
            "instr argument count mismatch for \"" ~ opcode.mnem ~ "\""
        );

        this.opcode = opcode;
        this.args.length = numArgs;
    }

    /// Trinary constructor
    this(Opcode* opcode, IRValue arg0, IRValue arg1, IRValue arg2)
    {
        assert (opcode.argTypes.length == 3);

        this(opcode, 3);
        setArg(0, arg0);
        setArg(1, arg1);
        setArg(2, arg2);
    }

    /// Binary constructor
    this(Opcode* opcode, IRValue arg0, IRValue arg1)
    {
        assert (
            opcode.argTypes.length == 2,
            "IR instruction does not take 2 arguments"
        );

        this(opcode, 2);
        setArg(0, arg0);
        setArg(1, arg1);
    }

    /// Unary constructor
    this(Opcode* opcode, IRValue arg0)
    {
        assert (
            opcode.argTypes.length == 1,
            "IR instruction does not take 1 argument"
        );

        this(opcode, 1);
        setArg(0, arg0);
    }

    /// Set an argument of this instruction
    void setArg(size_t idx, IRValue val)
    {
        assert (idx < args.length);

        // If this use is not yet initialized
        if (args[idx] is null)
        {
            args[idx] = new Use(val, this);
        }

        // If a value is already set for this
        // argument, remove the current use
        else if (args[idx].value !is null)
        {
            args[idx].value.remUse(args[idx]);
            args[idx].value = val;
        }

        // Add a use for the new value
        val.addUse(args[idx]);
    }

    /// Get the number of arguments
    size_t getNumArgs()
    {
        return args.length;
    }

    /// Get an argument of this instruction
    IRValue getArg(size_t idx)
    {
        assert (
            idx < args.length,
            "getArg: invalid arg index"
        );

        return args[idx].value;
    }

    /// Set a branch target with a branch descriptor
    void setTarget(size_t idx, BranchDesc desc)
    {
        assert (idx < targets.length);

        // Remove the existing target, if any
        if (targets[idx] !is null)
            targets[idx].succ.remIncoming(targets[idx]);

        // Create a branch edge descriptor
        targets[idx] = desc;

        // Add an incoming edge to the block
        desc.succ.addIncoming(desc);
    }

    BranchDesc setTarget(size_t idx, IRBlock succ)
    {
        auto pred = this.block;

        assert (
            pred !is null, 
            "setTarget: instr is not attached to a block"
        );

        auto desc = new BranchDesc(pred, succ);
        setTarget(idx, desc);

        return desc;
    }

    BranchDesc getTarget(size_t idx)
    {
        assert (idx < targets.length);
        return targets[idx];
    }

    /// Copy an instruction
    IRInstr dup()
    {
        auto that = new IRInstr(this.opcode, this.args.length);

        // Copy the arguments
        foreach (argIdx, arg; this.args)
            that.setArg(argIdx, arg.value);

        return that;
    }

    final override string toString()
    {
        string output;

        if (firstUse !is null || outSlot !is NULL_LOCAL)
            output ~= getName() ~ " = ";

        output ~= opcode.mnem;

        if (opcode.argTypes.length > 0)
            output ~= " ";

        foreach (argIdx, arg; args)
        {
            if (argIdx > 0)
                output ~= ", ";

            output ~= arg.value.getName();
        }

        if (targets[0] !is null)
        {
            output ~= " => " ~ targets[0].succ.getName();

            if (targets[1] !is null)
                output ~= ", " ~ targets[1].succ.getName();
        }

        return output;
    }
}

