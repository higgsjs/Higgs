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
import std.stdint;
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
immutable size_t NUM_HIDDEN_ARGS = 4;

/***
IR function
*/
class IRFunction : IdObject
{
    /// Corresponding AST node
    FunExpr ast;

    /// Function name
    string name = "";

    /// Function parameters
    IdentExpr[] params;

    /// Captured closure variables
    IdentExpr[] captVars;

    /// Entry block
    IRBlock entryBlock = null;

    /// First and last basic blocks
    IRBlock firstBlock = null;
    IRBlock lastBlock = null;

    // Number of visible parameters
    uint32_t numParams = 0;

    /// Total number of locals, including parameters and temporaries
    uint32_t numLocals = 0;

    /// Hidden argument slots
    LocalIdx raSlot;
    LocalIdx closSlot;
    LocalIdx thisSlot;
    LocalIdx argcSlot;

    /// Map of shared variable declarations (captured/escaping) to
    /// local slots where their closure cells are stored
    LocalIdx[IdentExpr] cellMap;

    /// Map of variable declarations to local slots
    LocalIdx[IdentExpr] localMap;

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
        this.params = ast.params;
        this.captVars = ast.captVars;
        this.numParams = cast(uint32_t)this.params.length;

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
        output.put("ra:$" ~ to!string(raSlot) ~ ", ");
        output.put("clos:$" ~ to!string(closSlot) ~ ", ");
        output.put("this:$" ~ to!string(thisSlot) ~ ", ");
        output.put("argc:$" ~ to!string(argcSlot));
        for (size_t i = 0; i < params.length; ++i)
        {
            auto param = params[i];
            auto localIdx = localMap[param];
            output.put(", " ~ param.toString() ~ ":$" ~ to!string(localIdx));
        }
        output.put(")");

        // Captured variables
        output.put(" [");
        for (size_t i = 0; i < captVars.length; ++i)
        {
            auto var = captVars[i];
            auto localIdx = cellMap[var];
            output.put(var.toString() ~ ":$" ~ to!string(localIdx));
            if (i < captVars.length - 1)
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
IR basic block
*/
class IRBlock : IdObject
{
    /// Block name (non-unique)
    private string name;

    /// Execution count, for profiling
    uint64 execCount = 0;

    /// JIT code entry point function
    EntryFn entryFn = null;

    /// JIT code fast entry point
    ubyte* jitEntry = null;

    /// Parent function
    IRFunction fun = null;

    IRInstr firstInstr = null;
    IRInstr lastInstr = null;
    
    IRBlock prev;
    IRBlock next;

    this(string name = "")
    {
        this.name = name;
    }

    IRBlock dup()
    {
        auto that = new IRBlock(this.name);

        that.execCount = this.execCount;
        that.fun = this.fun;
        
        for (auto instr = firstInstr; instr !is null; instr = instr.next)
            that.addInstr(instr.dup);

        return that;
    }

    string getName()
    {
        return this.name ~ "(" ~ idString() ~ ")";
    }

    string toString()
    {
        auto output = appender!string();

        output.put(this.getName() ~ ":\n");

        for (IRInstr instr = firstInstr; instr !is null; instr = instr.next)
        {
            auto instrStr = instr.toString();
            output.put(indent(instrStr, "  "));
            if (instr !is lastInstr)
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
    }
}

/**
IR instruction
*/
class IRInstr : IdObject
{
    /// Instruction argument
    union Arg
    {
        int32_t int32Val;
        int64_t int64Val;
        double float64Val;
        rawptr ptrVal;
        wstring stringVal;
        LocalIdx localIdx;
        LinkIdx linkIdx;
        IRFunction fun;
        CodeBlock codeBlock;
    }

    /// Opcode
    Opcode* opcode;

    /// Instruction arguments
    Arg[] args;

    /// Output local slot
    LocalIdx outSlot = NULL_LOCAL;

    /// Default branch target
    IRBlock target = null;

    /// Exception branch target
    IRBlock excTarget = null;

    /// Parent block
    IRBlock block = null;

    /// Previous and next instructions (linked list)
    IRInstr prev = null;
    IRInstr next = null;

    this(Opcode* opcode)
    {
        this.opcode = opcode;
    }

    /// Trinary constructor
    this(Opcode* opcode, LocalIdx outSlot, LocalIdx arg0, LocalIdx arg1, LocalIdx arg2)
    {
        assert (
            (opcode.output == true || outSlot == NULL_LOCAL) &&
            opcode.argTypes.length == 3 &&
            opcode.argTypes[0] == OpArg.LOCAL &&
            opcode.argTypes[1] == OpArg.LOCAL &&
            opcode.argTypes[2] == OpArg.LOCAL
        );

        this.opcode = opcode;
        this.outSlot = outSlot;
        this.args = [Arg(arg0), Arg(arg1), Arg(arg2)];
    }

    /// Binary constructor
    this(Opcode* opcode, LocalIdx outSlot, LocalIdx arg0, LocalIdx arg1)
    {
        assert (
            (opcode.output == true || outSlot == NULL_LOCAL) &&
            opcode.argTypes.length == 2 &&
            opcode.argTypes[0] == OpArg.LOCAL &&
            opcode.argTypes[1] == OpArg.LOCAL
        );

        this.opcode = opcode;
        this.outSlot = outSlot;
        this.args = [Arg(arg0), Arg(arg1)];
    }

    /// Unary constructor
    this(Opcode* opcode, LocalIdx outSlot, LocalIdx arg0)
    {
        assert (
            (opcode.output == true || outSlot == NULL_LOCAL) &&
            opcode.argTypes.length == 1 &&
            opcode.argTypes[0] == OpArg.LOCAL,
            "invalid instruction for ctor: " ~ opcode.mnem
        );

        this.opcode = opcode;
        this.outSlot = outSlot;
        this.args = [Arg(arg0)];
    }

    /// No argument constructor
    this(Opcode* opcode, LocalIdx outSlot)
    {
        assert (
            opcode.output == true &&
            opcode.argTypes.length == 0,
            "invalid instruction for ctor: " ~ opcode.mnem
        );

        this.opcode = opcode;
        this.outSlot = outSlot;
    }

    /// Copy an instruction
    IRInstr dup()
    {
        auto that = new IRInstr(this.opcode);

        that.args = this.args.dup;
        that.outSlot = this.outSlot;
        that.target = this.target;
        that.excTarget = this.excTarget;
        that.block = this.block;
        that.prev = this.prev;
        that.next = this.next;

        return that;
    }

    /// Integer constant
    static intCst(LocalIdx outSlot, int intVal)
    {
        auto cst = new this(&SET_I32);
        cst.outSlot = outSlot;
        cst.args = [Arg(intVal)];

        return cst;
    }

    /// Floating-point constant
    static floatCst(LocalIdx outSlot, double floatVal)
    {
        auto cst = new this(&SET_F64);
        cst.outSlot = outSlot;
        cst.args.length = 1;
        cst.args[0].float64Val = floatVal;

        return cst;
    }

    /// String constant
    static strCst(LocalIdx outSlot, wstring stringVal)
    {
        auto cst = new this(&SET_STR);
        cst.outSlot = outSlot;
        cst.args.length = 2;
        cst.args[0].stringVal = stringVal;
        cst.args[1].linkIdx = NULL_LINK;

        return cst;
    }

    /// Jump instruction
    static jump(IRBlock block)
    {
        auto jump = new this(&JUMP);
        jump.target = block;
        return jump;

    }

    /// Conditional branching instruction
    static ifTrue(LocalIdx arg0, IRBlock trueBlock, IRBlock falseBlock)
    {
        auto ift = new this(&IF_TRUE);
        ift.args = [Arg(arg0)];
        ift.target = trueBlock;
        ift.excTarget = falseBlock;
        return ift;
    }

    /// Make link instruction
    static makeLink(LocalIdx outSlot)
    {
        auto instr = new this(&MAKE_LINK);
        instr.outSlot = outSlot;
        instr.args.length = 1;
        instr.args[0].linkIdx = NULL_LINK;
        return instr;
    }

    /// Test if this instruction has a specific local as an argument
    bool hasArg(LocalIdx local)
    {
        foreach (idx, arg; args)
            if (opcode.getArgType(idx) == OpArg.LOCAL && arg.localIdx == local)
                return true;

        return false;
    }

    final override string toString()
    {
        string output;

        if (outSlot !is NULL_LOCAL)
            output ~= "$" ~ to!string(outSlot) ~ " = ";

        output ~= opcode.mnem;

        if (opcode.argTypes.length > 0)
            output ~= " ";

        for (size_t i = 0; i < args.length; ++i)
        {
            auto arg = args[i];

            if (i > 0)
                output ~= ", ";

            switch (opcode.getArgType(i))
            {
                case OpArg.INT32:
                output ~= to!string(arg.int32Val);
                break;
                case OpArg.FLOAT64:
                output ~= to!string(arg.float64Val);
                break;
                case OpArg.RAWPTR:
                output ~= "<rawptr:" ~ ((arg.ptrVal is null)? "NULL":"0x"~to!string(arg.ptrVal)) ~ ">";
                break;
                case OpArg.STRING:
                output ~= "\"" ~ to!string(arg.stringVal) ~ "\"";
                break;
                case OpArg.LOCAL:
                output ~= "$" ~ ((arg.localIdx is NULL_LOCAL)? "NULL":to!string(arg.localIdx)); 
                break;
                case OpArg.LINK:
                output ~= "<link:" ~ ((arg.linkIdx is NULL_LINK)? "NULL":to!string(arg.linkIdx)) ~ ">"; 
                break;
                case OpArg.FUN:
                output ~= "<fun:" ~ arg.fun.getName() ~ ">";
                break;
                case OpArg.CODEBLOCK:
                output ~= "<codeblock:" ~ ((arg.codeBlock is null)? "NULL":"0x"~to!string(arg.codeBlock.getAddress())) ~ ">";
                break; 
                default:
                assert (false, "unhandled arg type");
            }
        }

        if (target !is null)
        {
            output ~= " => " ~ target.getName();
            if (excTarget !is null)
                output ~= ", " ~ excTarget.getName();
        }

        return output;
    }
}










/**
SSA IR basic block
*/
class SSABlock : IdObject
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
    SSAInstr firstInstr = null;
    SSAInstr lastInstr = null;
    
    /// Previous and next block (linked list)
    IRBlock prev = null;
    IRBlock next = null;

    this(string name = "")
    {
        this.name = name;
    }

    SSABlock dup()
    {
        auto that = new SSABlock(this.name);

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
            if (phi.next !is null)
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
    SSAInstr addInstr(SSAInstr instr)
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
    /*
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
    */

    /**
    Add an instruction before another instruction
    */
    /*
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
    */

    /**
    Remove an instruction
    */
    /*
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
    }
    */

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
Base class for IR/SSA values
*/
class IRValue : IdObject
{
    struct Use
    {
        Use* prev;
        Use* next;
        IRValue value;
        IRValue dst;
    }

    /// Linked list of destinations
    Use* firstDst = null;

    private void addDst(ref Use dst)
    {
        assert (dst.value is this);

        dst.prev = null;
        dst.next = firstDst;

        firstDst = &dst;
    }

    private void remDst(ref Use dst)
    {
        assert (dst.value is this);

        if (dst.prev is null)
            firstDst = null;
        else
            dst.prev.next = dst.next;

        if (dst.next !is null)
            dst.next.prev = dst.prev;
    }
}

/**
Branch edge descriptor
*/
class BranchDesc
{
    /// Branch predecessor block
    SSABlock pred;

    /// Branch successor block
    SSABlock succ;

    /// Mapping of incoming phi values (block arguments)
    Tuple!(IRValue, "src", PhiNode, "dst") args[];

    this(SSABlock pred, SSABlock succ)
    {
        this.pred = pred;
        this.succ = succ;
    }

    // TODO: method to set/add argument?
    // May want to wait until AST->IR implementation
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

    static IRConst nullCst()  
    { 
        if (!nullVal) nullVal = new IRConst(NULL, Type.REFPTR);
        return nullVal;
    }

    private static IRConst trueVal;
    private static IRConst falseVal;
    private static IRConst undefVal;
    private static IRConst nullVal;

    private static IRConst[int32] int32Vals;
    private static IRConst[int64] int64Vals;
    private static IRConst[float64] float64Vals;

    private this(Word word, Type type)
    {
        this.value = ValuePair(word, type);
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
Link index pointer value (non-constant, initially null)
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
Code block pointer value (non-constant, initially null)
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
Phi node value
*/
class PhiNode : IRValue
{
    /// Previous and next phi nodes (linked list)
    PhiNode prev = null;
    PhiNode next = null;

    /// Parent block
    SSABlock block = null;

    /// Output stack slot
    LocalIdx outSlot = NULL_LOCAL;

    /// Copy a phi node
    PhiNode dup()
    {
        auto that = new PhiNode();
        return that;
    }

    override string toString()
    {
        // TODO
        return "";
    }
}

/**
Function parameter value
@extends PhiNode
*/
class FunParam : PhiNode
{
    string name;
    size_t idx;

    this(string name, size_t idx)
    {
        this.name = name;
        this.idx = idx;
    }

    override string toString()
    {
        // TODO
        return "";
    }
}

/**
SSA instruction
*/
class SSAInstr : IRValue
{
    /// Opcode
    Opcode* opcode;

    /// Arguments to this instruction
    private Use[] args;

    /// Branch targets 
    private BranchDesc[2] targets = [null, null];

    /// Parent block
    SSABlock block = null;

    /// Previous and next instructions (linked list)
    SSAInstr prev = null;
    SSAInstr next = null;

    /// Assigned output stack slot
    LocalIdx outSlot = NULL_LOCAL;

    /// Default constructor
    this(Opcode* opcode, size_t numArgs = 0)
    {
        this.opcode = opcode;
        this.args.length = numArgs;
    }

    /// Set an argument of this instruction
    void setArg(size_t idx, IRValue val)
    {
        assert (idx < args.length);

        if (args[idx].value is val)
            return;

        if (args[idx].value !is null)
            args[idx].value.remDst(args[idx]);

        args[idx].value = val;
        val.addDst(args[idx]);
    }

    void setTarget(size_t idx, SSABlock succ)
    {
        assert (idx < targets.length);

        // Remove the existing target, if any
        if (targets[idx] !is null)
            targets[idx].succ.remIncoming(targets[idx]);

        // Create a branch edge descriptor
        auto desc = new BranchDesc(this.block, succ);
        targets[idx] = desc;

        // Add an incoming edge to the block
        block.addIncoming(desc);
    }

    /// Copy an instruction
    SSAInstr dup()
    {
        auto that = new SSAInstr(this.opcode, this.args.length);

        // Copy the arguments
        foreach (argIdx, arg; this.args)
            that.setArg(argIdx, arg.value);

        return that;
    }

    /// Get the short name string associated with this instruction
    string getName()
    {
        if (outSlot !is NULL_LOCAL)
            return "$" ~ to!string(outSlot);

        return "t_" ~ idString();
    }

    final override string toString()
    {
        string output;

        if (firstDst !is null)
            output ~= getName() ~ " = ";

        output ~= opcode.mnem;

        if (opcode.argTypes.length > 0)
            output ~= " ";

        foreach (argIdx, arg; args)
        {
            if (argIdx > 0)
                output ~= ", ";

            if (auto instr = cast(SSAInstr)arg.value)
                output ~= instr.getName();
            else
                output ~= arg.value.toString();
        }

        if (targets[0] !is null)
        {
            output ~= " => " ~ targets[0].succ.getName();

            if (targets[1] !is null)
                output ~= ", " ~ targets[1].succ.getName();
        }

        return output;
    }

    /// Jump instruction
    static jump(SSABlock block)
    {
        auto jump = new this(&JUMP);
        jump.setTarget(0, block);
        return jump;

    }

    /// Conditional branching instruction
    static ifTrue(IRValue arg0, SSABlock trueBlock, SSABlock falseBlock)
    {
        auto ift = new this(&IF_TRUE, 2);
        ift.setArg(0, arg0);
        ift.setTarget(0, trueBlock);
        ift.setTarget(1, falseBlock);
        return ift;
    }
}

