/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011-2015, Maxime Chevalier-Boisvert. All rights reserved.
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
import parser.lexer;
import parser.ast;
import ir.ops;
import ir.livevars;
import runtime.gc;
import runtime.vm;
import runtime.layout;
import runtime.object;
import runtime.string;
import jit.codeblock;
import jit.jit;
import options;

/// Runtime name prefix
const wstring RT_PREFIX = "$rt_";

/// Stack variable index type
alias StackIdx = int32;

/// Link table index type
alias LinkIdx = uint32;

/// Null local constant
immutable StackIdx NULL_STACK = StackIdx.max;

/// Null link constant
immutable LinkIdx NULL_LINK = LinkIdx.max;

/// Number of hidden function arguments
immutable uint32_t NUM_HIDDEN_ARGS = 4;

/***
IR function
*/
class IRFunction : IdObject
{
    /// Corresponding Abstract Syntax Tree (AST) node
    FunExpr ast;

    /// Function name
    package string name = "";

    /// Entry block
    IRBlock entryBlock = null;

    /// First and last basic blocks
    IRBlock firstBlock = null;
    IRBlock lastBlock = null;

    /// Number of basic blocks
    uint32_t numBlocks = 0;

    // Number of visible parameters
    uint32_t numParams = 0;

    /// Total number of locals, including parameters and temporaries
    uint32_t numLocals = 0;

    /// Hidden parameter SSA values
    FunParam raVal;
    FunParam closVal;
    FunParam thisVal;
    FunParam argcVal;

    /// Visible parameter SSA values
    FunParam[] paramVals;

    /// Flag indicating this function reads arguments variadically
    bool usesVarArg;

    /// Map of identifiers to SSA cell values (closure/shared variables)
    IRValue[IdentExpr] cellMap;

    /// Global object value
    IRInstr globalVal = null;

    /// Liveness information
    LiveInfo liveInfo = null;

    /// Generic function entry point
    CodePtr entryCode = null;

    /// C entry point code
    CodeBlock cEntryCode;

    /// Map of blocks to lists of existing versions
    BlockVersion[][IRBlock] versionMap;

    /// Return type, if known
    ValType retType;

    /// Shapes changed flag, initially false
    bool shapeChg = false;

    /// Number of return compiled
    size_t numRets = 0;

    /// Direct call sites (possibly relying on the return type)
    BlockVersion[BlockVersion] callSites;

    /// Constructor
    this(FunExpr ast)
    {
        // Register this function in the live function reference set
        vm.funRefs[cast(void*)this] = this;

        // If shape change tracking is disabled
        if (opts.noshapechg)
            this.shapeChg = true;

        this.ast = ast;
        this.name = ast.getName();
        this.numParams = cast(uint32_t)ast.params.length;
        this.numLocals = this.numParams + NUM_HIDDEN_ARGS;

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

    /// Destructor
    ~this()
    {
        //writeln("destroying fun");
    }

    /// Test if this is a unit-level function
    bool isUnit() const
    {
        return cast(ASTProgram)ast !is null;
    }

    /// Test if this is a runtime primitive function
    bool isPrim() const
    {
        return name.startsWith(RT_PREFIX);
    }

    string getName() const
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

        foreach (argIdx, paramVal; paramVals)
        {
            auto var = ast.params[argIdx];
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

        numBlocks++;
    }

    /**
    Remove and destroy a block
    */
    void delBlock(IRBlock block)
    {
        if (block.prev)
            block.prev.next = block.next;
        else
            firstBlock = block.next;

        if (block.next)
            block.next.prev = block.prev;
        else
            lastBlock = block.prev;

        // Destroy the phi nodes
        for (auto phi = block.firstPhi; phi !is null; phi = phi.next)
            block.delPhi(phi);

        // Destroy the instructions
        for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
            block.delInstr(instr);

        // Nullify the parent pointer
        block.fun = null;

        numBlocks--;
    }
}

/**
SSA IR basic block
*/
class IRBlock : IdObject
{
    /// Block name (non-unique)
    package string name;

    /// List of incoming branches
    private BranchEdge[] incoming;

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

    string getName()
    {
        return this.name ~ "(" ~ idString() ~ ")";
    }

    override string toString()
    {
        auto output = appender!string();

        output.put(this.getName() ~ ":\n");

        //writeln("printing phis");

        for (auto phi = firstPhi; phi !is null; phi = phi.next)
        {
            auto phiStr = phi.toString();
            output.put(indent(phiStr, "  "));
            if (phi.next !is null || firstInstr !is null)
                output.put("\n");
        }

        //writeln("printing instrs");

        for (auto instr = firstInstr; instr !is null; instr = instr.next)
        {
            auto instrStr = instr.toString();
            output.put(indent(instrStr, "  "));
            if (instr.next !is null)
                output.put("\n");
        }

        //writeln("done");

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
    Remove and destroy an instruction
    */
    void delInstr(IRInstr instr)
    {
        assert (instr.block is this);

        if (instr.prev)
            instr.prev.next = instr.next;
        else
            firstInstr = instr.next;

        if (instr.next)
            instr.next.prev = instr.prev;
        else
            lastInstr = instr.prev;

        // If this is a branch instruction
        if (instr.opcode.isBranch)
        {
            // Remove branch edges from successors
            for (size_t tIdx = 0; tIdx < IRInstr.MAX_TARGETS; ++tIdx)
            {
                auto edge = instr.getTarget(tIdx);
                if (edge !is null)
                    edge.target.remIncoming(edge);
            }
        }

        // Unregister uses of other values
        foreach (arg; instr.args)
        {
            assert (arg.value !is null);
            arg.value.remUse(arg);
        }

        // Nullify the parent pointer
        instr.block = null;
    }

    /**
    Move an instruction to another block
    */
    void moveInstr(IRInstr instr, IRBlock dstBlock)
    {
        assert (instr.block is this);

        if (instr.prev)
            instr.prev.next = instr.next;
        else
            firstInstr = instr.next;

        if (instr.next)
            instr.next.prev = instr.prev;
        else
            lastInstr = instr.prev;

        // Add the instruction to the destination block
        dstBlock.addInstr(instr);
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
    Remove and destroy a phi node
    */
    void delPhi(PhiNode phi)
    {
        if (phi.prev)
            phi.prev.next = phi.next;
        else
            firstPhi = phi.next;

        if (phi.next)
            phi.next.prev = phi.prev;
        else
            lastPhi = phi.prev;

        // Remove the incoming arguments to this phi node
        foreach (edge; incoming)
            edge.remPhiArg(phi);

        // Nullify the parent pointer
        phi.block = null;
    }

    /**
    Register an incoming branch edge on this block
    */
    void addIncoming(BranchEdge edge)
    {
        debug
        {
            foreach (entry; incoming)
                if (entry is edge)
                    assert (false, "duplicate incoming edge");
        }

        incoming ~= edge;
    }

    /**
    Remove (unregister) an incoming branch edge
    */
    void remIncoming(BranchEdge edge)
    {
        foreach (idx, entry; incoming)
        {
            if (entry is edge)
            {
                incoming[idx] = incoming[$-1];
                incoming.length -= 1;

                // Unregister the phi arguments
                foreach (arg; edge.args)
                    arg.value.remUse(arg);

                edge.args = [];
                edge.target = null;

                return;
            }
        }

        assert (false);
    }

    auto numIncoming()
    {
        return incoming.length;
    }

    auto getIncoming(size_t idx)
    {
        assert (idx < incoming.length);
        return incoming[idx];
    }
}

/**
Branch edge descriptor
*/
class BranchEdge : IdObject
{
    /// Owner branch instruction
    IRInstr branch;

    /// Branch target block
    IRBlock target;

    /// Mapping of incoming phi values (block arguments)
    Use[] args;

    this(IRInstr branch, IRBlock target)
    {
        this.branch = branch;
        this.target = target;
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

    /**
    Get the argument to a phi node
    */
    IRValue getPhiArg(PhiNode phi)
    {
        // For each existing branch argument
        foreach (arg; args)
            if (arg.owner is phi)
                return arg.value;

        // Not found
        return null;
    }

    /// Remove the argument to a phi node
    void remPhiArg(PhiNode phi)
    {
        // For each existing branch argument
        foreach (argIdx, arg; args)
        {
            // If this pair goes to the selected phi node
            if (arg.owner is phi)
            {
                args[argIdx] = args[$-1];
                args.length = args.length - 1;

                arg.value.remUse(arg);

                return;
            }
        }

        assert (false, "phi arg not found");
    }
}

/**
IR value use instance
*/
private class Use
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

        debug
        {
            auto dstThis = cast(IRDstValue)this;
            auto dstUse = cast(IRDstValue)use;
            assert (
                !dstThis || !dstUse || dstThis.block is dstUse.block,
                "use owner is not in the same block as value"
            );
        }

        if (firstUse !is null)
        {
            assert (firstUse.prev is null);
            firstUse.prev = use;
        }

        use.prev = null;
        use.next = firstUse;

        firstUse = use;
    }

    /// Unregister a use of this value
    private void remUse(Use use)
    {
        assert (
            use.value is this,
            "use does not point to this value"
        );

        if (use.prev !is null)
        {
            assert (firstUse !is use);
            use.prev.next = use.next;
        }
        else
        {
            assert (firstUse !is null);
            assert (firstUse is use);
            firstUse = use.next;
        }

        if (use.next !is null)
        {
            use.next.prev = use.prev;
        }

        use.prev = null;
        use.next = null;
        use.value = null;
    }

    /// Get the first use of this value
    Use getFirstUse()
    {
        return firstUse;
    }

    /// Test if this value has no uses
    bool hasNoUses()
    {
        return firstUse is null;
    }

    /// Test if this has uses
    bool hasUses()
    {
        return firstUse !is null;
    }

    /// Test if this value has a single use
    bool hasOneUse()
    {
        return firstUse !is null && firstUse.next is null;
    }

    /// Test if this value has more than one use
    bool hasManyUses()
    {
        return firstUse !is null && firstUse.next !is null;
    }

    /// Replace uses of this value by uses of another value
    void replUses(IRValue newVal)
    {
        //assert (false, "replUses");

        assert (newVal !is null);

        //writefln("*** replUses of: %s, by: %s", this.toString(), newVal.getName());

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
            assert (lastUse.next is null);
            lastUse.next = this.firstUse;
            if (this.firstUse !is null)
                this.firstUse.prev = lastUse;
        }
        else
        {
            assert (newVal.firstUse is null);
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

    /// Get the constant value pair for this IR value
    ValuePair cstValue()
    {
        assert (
            false,
            "cannot get constant value for: \"" ~ toString() ~ "\""
        );
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
        return value.toString();
    }

    /// Get the constant value pair for this IR value
    override ValuePair cstValue()
    {
        return value;
    }

    auto isInt32 () { return value.tag == Tag.INT32; }

    auto pair() { return value; }
    auto word() { return value.word; }
    auto tag() { return value.tag; }
    auto int32Val() { return value.word.int32Val; }

    static IRConst int32Cst(int32_t val)
    {
        if (val in int32Vals)
            return int32Vals[val];

        auto cst = new IRConst(Word.int32v(val), Tag.INT32);
        int32Vals[val] = cst;
        return cst;
    }

    static IRConst int64Cst(int64_t val)
    {
        if (val in int64Vals)
            return int64Vals[val];

        auto cst = new IRConst(Word.int64v(val), Tag.INT64);
        int64Vals[val] = cst;
        return cst;
    }

    static IRConst float64Cst(float64 val)
    {
        // Hash the bit representation which might differ even though
        // two values compare equal, e.g. 0.0 == -0.0 but 0.0 !is -0.0
        static assert(uint64_t.sizeof == float64.sizeof);
        ulong repr = *cast(uint64_t*)&val;

        if (auto p = repr in float64Vals)
            return *p;

        auto cst = new IRConst(Word.float64v(val), Tag.FLOAT64);
        float64Vals[repr] = cst;
        return cst;
    }

    static IRConst trueCst()
    { 
        if (!trueVal) trueVal = new IRConst(TRUE);
        return trueVal;
    }

    static IRConst falseCst()
    {
        if (!falseVal) falseVal = new IRConst(FALSE);
        return falseVal;
    }

    static IRConst undefCst()
    {
        if (!undefVal) undefVal = new IRConst(UNDEF);
        return undefVal;
    }

    static IRConst nullCst()
    {
        if (!nullVal) nullVal = new IRConst(NULL);
        return nullVal;
    }

    static IRConst nullPtrCst()
    { 
        if (!nullPtrVal) nullPtrVal = new IRConst(Word.int64v(0), Tag.RAWPTR);
        return nullPtrVal;
    }

    private static IRConst trueVal = null;
    private static IRConst falseVal = null;
    private static IRConst undefVal = null;
    private static IRConst nullVal = null;
    private static IRConst nullPtrVal = null;

    // Integer constants
    private static IRConst[int32] int32Vals;
    private static IRConst[int64] int64Vals;

    // Floating-point constants
    // Note: we hash the bit representation, not the float
    private static IRConst[uint64_t] float64Vals;

    private this(Word word, Tag tag)
    {
        this.value = ValuePair(word, tag);
    }

    private this(ValuePair value)
    {
        this.value = value;
    }
}

/**
String constant value
*/
class IRString : IRValue
{
    /// String value
    const wstring str;

    /// String pointer in JS heap
    refptr ptr;

    this(wstring str)
    {
        assert (str !is null);
        this.str = str;
        this.ptr = null;
    }

    override string toString()
    {
        return "\"" ~ to!string(str) ~ "\"";
    }

    refptr getPtr(VM vm)
    {
        if (ptr is null)
            ptr = getString(vm, str);

        assert (runtime.gc.inFromSpace(vm, ptr));

        return ptr;
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
        this.ptr = ValuePair(Word.ptrv(ptr), Tag.RAWPTR);
    }

    override string toString()
    {
        auto p = ptr.word.ptrVal;
        return "<rawptr:" ~ ((p is null)? "NULL":"0x"~to!string(p)) ~ ">";
    }

    /// Get the constant value pair for this IR value
    override ValuePair cstValue()
    {
        return ptr;
    }
}

/**
IR function pointer constant (stateful, non-constant, may be null)
*/
class IRFunPtr : IRValue
{
    IRFunction fun;

    this(IRFunction fun)
    {
        this.fun = fun;
    }

    override string toString()
    {
        return "<fun:" ~ (fun? fun.getName():"NULL") ~ ">";
    }
}

/**
Link tanle index value (stateful, non-constant, initially null)
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
Base class for IR values usable as destinations 
(phi nodes, fun params, instructions)
*/
abstract class IRDstValue : IRValue
{
    /// Parent block
    IRBlock block = null;

    /// Output stack slot
    StackIdx outSlot = NULL_STACK;

    /// Get the short name string associated with this instruction
    override string getName()
    {
        if (outSlot !is NULL_STACK)
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

    override string toString()
    {
        assert (
            block !is null, 
            "phi node is not attached to a block: " ~ getName()
        );

        string output;

        output ~= getName() ~ " = phi [";

        // For each incoming branch edge
        foreach (edgeIdx, edge; block.incoming)
        {
            // For each branch argument
            foreach (arg; edge.args)
            {
                assert (arg !is null);

                if (arg.owner is this)
                {
                    if (edgeIdx > 0)
                        output ~= ", ";

                    // Find the index of this branch target
                    auto branch = edge.branch;
                    assert (branch !is null);
                    size_t tIdx = size_t.max;
                    for (size_t idx = 0; idx < branch.MAX_TARGETS; ++idx)
                        if (branch.getTarget(idx) is edge)
                            tIdx = idx;
                    assert (tIdx != size_t.max);

                    assert (branch.block !is null);
                    output ~= branch.block.getName() ~ ":" ~ to!string(tIdx);
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
        if (outSlot !is NULL_STACK)
            return "$" ~ to!string(outSlot);

        return "arg_" ~ to!string(idx);
    }

    override string toString()
    {
        string str;

        if (outSlot !is NULL_STACK)
            str ~= "$" ~ to!string(outSlot) ~ " = ";

        str ~= "arg " ~ to!string(idx) ~ " \"" ~ to!string(name) ~ "\"";

        return str;
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
    private BranchEdge[MAX_TARGETS] targets = [null, null];

    /// Previous and next instructions (linked list)
    IRInstr prev = null;
    IRInstr next = null;

    // Source position, may be null
    SrcPos srcPos = null;

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
            "IR instruction does not take 2 arguments \"" ~ opcode.mnem ~ "\""
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
            "IR instruction does not take 1 argument \"" ~ opcode.mnem ~ "\""
        );

        this(opcode, 1);
        setArg(0, arg0);
    }

    /// Set an argument of this instruction
    void setArg(size_t idx, IRValue val)
    {
        assert (idx < args.length);
        assert (val !is null);

        // If this use is not yet initialized
        if (args[idx] is null)
        {
            args[idx] = new Use(val, this);
        }
        else
        {
            // If a value is already set for this
            // argument, remove the current use
            if (args[idx].value !is null)
                args[idx].value.remUse(args[idx]);

            args[idx].value = val;
        }

        // Add a use for the new value
        val.addUse(args[idx]);
    }

    /// Remove an argument use
    void remArg(size_t idx)
    {
        assert (idx < args.length);

        if (args[idx].value !is null)
            args[idx].value.remUse(args[idx]);

        args[idx].value = null;
    }

    /// Get the number of arguments
    size_t numArgs()
    {
        return args.length;
    }

    /// Get the number of variable length (extra) arguments
    size_t numVarArgs()
    {
        return args.length - opcode.argTypes.length;
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

    /// Test if this instruction uses a given value as argument
    bool hasArg(IRValue value)
    {
        foreach (arg; args)
            if (arg.value is value)
                return true;

        return false;
    }

    /// Set a branch target and create a new branch edge descriptor
    BranchEdge setTarget(size_t idx, IRBlock target)
    {
        assert (idx < this.targets.length);

        // Remove the existing target, if any
        if (this.targets[idx] !is null)
            this.targets[idx].target.remIncoming(targets[idx]);

        auto edge = new BranchEdge(this, target);

        // Set the branch edge descriptor
        this.targets[idx] = edge;

        // Add an incoming edge to the block
        target.addIncoming(edge);

        return edge;
    }

    BranchEdge getTarget(size_t idx)
    {
        assert (idx < targets.length);
        return targets[idx];
    }

    final override string toString()
    {
        string output;

        if (firstUse !is null || outSlot !is NULL_STACK)
            output ~= getName() ~ " = ";

        output ~= opcode.mnem;

        if (args.length > 0)
            output ~= " ";

        foreach (argIdx, arg; args)
        {
            if (argIdx > 0)
                output ~= ", ";

            if (arg.value is null)
                output ~= "<NULL ARG>";
            else
                output ~= arg.value.getName();
        }

        if (targets[0] !is null)
        {
            output ~= " => " ~ targets[0].target.getName();

            if (targets[1] !is null)
                output ~= ", " ~ targets[1].target.getName();
        }

        return output;
    }
}

/**
Test if an instruction is followed by an if_true branching on its value
*/
bool ifUseNext(IRInstr instr)
{
    return (
        instr.next &&
        instr.next.opcode is &IF_TRUE &&
        instr.next.getArg(0) is instr
    );
}

/**
Test if our argument precedes and generates a boolean value
*/
bool boolArgPrev(IRInstr instr)
{
    return (
        instr.getArg(0) is instr.prev &&
        instr.prev.opcode.boolVal
    );
}

/**
Attempt to get the value of a constant string argument.
Produces null if the argument is not a constant string.
*/
wstring getArgStrCst(IRInstr instr, size_t argIdx)
{
    auto irString = cast(IRString)instr.getArg(argIdx);
    if (!irString)
        return null;

    return irString.str;
}

/**
Recover the callee name for a call instruction, if possible.
This function is used to help print sensible error messages.
*/
string getCalleeName(IRInstr callInstr)
{
    assert (callInstr.opcode.isCall);

    /// Recover the property name for a get instruction
    string getPropName(IRInstr getInstr)
    {
        // If this is a primitive call
        if (getInstr.opcode == &CALL_PRIM)
        {
            auto primName = cast(IRString)getInstr.getArg(0);

            if (primName.str == "$rt_getGlobalInl"w)
                return to!string(getInstr.getArgStrCst(1));
            if (primName.str == "$rt_getGlobal"w)
                return to!string(getInstr.getArgStrCst(2));
            if (primName.str == "$rt_getPropField"w)
                return to!string(getInstr.getArgStrCst(2));
            if (primName.str == "$rt_getProp"w)
                return to!string(getInstr.getArgStrCst(2));
        }

        // If this is an object property read
        if (getInstr.opcode == &OBJ_GET_PROP)
        {
            return to!string(getInstr.getArgStrCst(1));
        }

        // Callee name unrecoverable
        return null;
    }

    // If this is a regular call instruction
    if (callInstr.opcode is &CALL)
    {
        // Get the closure argument
        auto closArg = callInstr.getArg(0);

        // If the closure argument is a phi node
        if (auto closPhi = cast(PhiNode)closArg)
        {
            // For each phi argument
            for (size_t iIdx = 0; iIdx < closPhi.block.numIncoming; ++iIdx)
            {
                auto branch = closPhi.block.getIncoming(iIdx);
                auto arg = branch.getPhiArg(closPhi);

                if (auto instrArg = cast(IRInstr)arg)
                {
                    return getPropName(instrArg);
                }
            }
        }

        // If the closure argument is an instruction
        if (auto closInstr = cast(IRInstr)closArg)
        {
            return getPropName(closInstr);
        }
    }

    // Callee name unrecoverable
    return null;
}

