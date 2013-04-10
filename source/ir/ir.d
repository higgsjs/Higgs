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
import std.conv;
import std.regex;
import std.stdint;
import util.id;
import util.string;
import parser.ast;
import ir.init;
import interp.interp;
import interp.layout;
import interp.ops;
import jit.codeblock;
import util.bitset;

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

    /// Number of local variables, including temporaries
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

    /// Maps of initialized stack slots for call/alloc instructions
    BitSetCW[IRInstr] initMaps;

    /// Callee profiling information (filled by interpreter)
    uint64_t[IRFunction][IRInstr] callCounts;  

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
            firstInstr = null;

        if (instr.next)
            instr.next.prev = instr.prev;
        else
            lastInstr = null;

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
        int int32Val;
        double floatVal;
        wstring stringVal;
        LocalIdx localIdx;
        LinkIdx linkIdx;
        IRFunction fun;
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
    IRInstr prev;
    IRInstr next;

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

    /// Integer constant
    static intCst(LocalIdx outSlot, int intVal)
    {
        auto cst = new this(&SET_INT32);
        cst.outSlot = outSlot;
        cst.args = [Arg(intVal)];

        return cst;
    }

    /// Floating-point constant
    static floatCst(LocalIdx outSlot, double floatVal)
    {
        auto cst = new this(&SET_FLOAT);
        cst.outSlot = outSlot;
        cst.args.length = 1;
        cst.args[0].floatVal = floatVal;

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
                case OpArg.FLOAT:
                output ~= to!string(arg.floatVal);
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
Opcode argument type
*/
enum OpArg
{
    INT32,
    FLOAT,
    STRING,
    LOCAL,
    LINK,
    FUN
}

/// Opcode implementation function
alias extern (C) void function(Interp interp, IRInstr instr) OpFn;

/**
Opcode information
*/
struct OpInfo
{
    alias uint OpFlag;
    enum : OpFlag
    {
        VAR_ARG = 1 << 0,
        BRANCH  = 1 << 1,
        CALL    = 1 << 2,
        MAY_GC  = 1 << 3
    }

    string mnem;
    bool output;
    OpArg[] argTypes;
    OpFn opFn = null;
    OpFlag opFlags = 0;

    bool isVarArg() const { return (opFlags & VAR_ARG) != 0; }
    bool isBranch() const { return (opFlags & BRANCH) != 0; }
    bool isCall  () const { return (opFlags & CALL) != 0; }
    bool mayGC   () const { return (opFlags & MAY_GC) != 0; }

    OpArg getArgType(size_t i) immutable
    {
        if (i < argTypes.length)
            return argTypes[i];
        else if (isVarArg)
            return OpArg.LOCAL;
        else
            assert (false, "invalid arg index");
    }
}

/// Instruction type (opcode) alias
alias static immutable(OpInfo) Opcode;

// Set a local slot to a constant value    
Opcode SET_INT32 = { "set_int32"   , true, [OpArg.INT32], &op_set_int32 };
Opcode SET_FLOAT = { "set_float" , true, [OpArg.FLOAT], &op_set_float };
Opcode SET_STR = { "set_str"   , true, [OpArg.STRING, OpArg.LINK], &op_set_str };
Opcode SET_TRUE = { "set_true"  , true, [], &op_set_true };
Opcode SET_FALSE = { "set_false" , true, [], &op_set_false };
Opcode SET_NULL = { "set_null"  , true, [], &op_set_null };
Opcode SET_UNDEF = { "set_undef" , true, [], &op_set_undef };
Opcode SET_MISSING = { "set_missing" , true, [], &op_set_missing };

// Word/type manipulation primitives
Opcode SET_VALUE = { "set_value", true, [OpArg.LOCAL, OpArg.LOCAL], &op_set_value };
Opcode GET_WORD = { "get_word", true, [OpArg.LOCAL], &op_get_word };
Opcode GET_TYPE = { "get_type", true, [OpArg.LOCAL], &op_get_type };

// Move a value from one stack slot to another
Opcode MOVE = { "move", true, [OpArg.LOCAL], &op_move };

// Type tag test
Opcode IS_INT32 = { "is_int32", true, [OpArg.LOCAL], &op_is_int32 };
Opcode IS_FLOAT = { "is_float", true, [OpArg.LOCAL], &op_is_float };
Opcode IS_REFPTR = { "is_refptr", true, [OpArg.LOCAL], &op_is_refptr };
Opcode IS_RAWPTR = { "is_rawptr", true, [OpArg.LOCAL], &op_is_rawptr };
Opcode IS_CONST  = { "is_const", true, [OpArg.LOCAL], &op_is_const };

// Type conversion
Opcode I32_TO_F64 = { "i32_to_f64", true, [OpArg.LOCAL], &op_i32_to_f64 };
Opcode F64_TO_I32 = { "f64_to_i32", true, [OpArg.LOCAL], &op_f64_to_i32 };

// Integer arithmetic
Opcode ADD_I32 = { "add_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_add_i32 };
Opcode SUB_I32 = { "sub_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_sub_i32 };
Opcode MUL_I32 = { "mul_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_mul_i32 };
Opcode DIV_I32 = { "div_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_div_i32 };
Opcode MOD_I32 = { "mod_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_mod_i32 };

// Bitwise operations
Opcode AND_I32 = { "and_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_and_i32 };
Opcode OR_I32 = { "or_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_or_i32 };
Opcode XOR_I32 = { "xor_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_xor_i32 };
Opcode LSFT_I32 = { "lsft_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_lsft_i32 };
Opcode RSFT_I32 = { "rsft_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_rsft_i32 };
Opcode URSFT_I32 = { "ursft_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ursft_i32 };
Opcode NOT_I32 = { "not_i32", true, [OpArg.LOCAL], &op_not_i32 };

// Floating-point arithmetic
Opcode ADD_F64 = { "add_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_add_f64 };
Opcode SUB_F64 = { "sub_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_sub_f64 };
Opcode MUL_F64 = { "mul_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_mul_f64 };
Opcode DIV_F64 = { "div_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_div_f64 };
Opcode MOD_F64 = { "mod_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_mod_f64 };

// Higher-level floating-point functions
Opcode SIN_F64 = { "sin_f64", true, [OpArg.LOCAL], &op_sin_f64 };
Opcode COS_F64 = { "cos_f64", true, [OpArg.LOCAL], &op_cos_f64 };
Opcode SQRT_F64 = { "sqrt_f64", true, [OpArg.LOCAL], &op_sqrt_f64 };
Opcode CEIL_F64 = { "ceil_f64", true, [OpArg.LOCAL], &op_ceil_f64 };
Opcode FLOOR_F64 = { "floor_f64", true, [OpArg.LOCAL], &op_floor_f64 };
Opcode LOG_F64 = { "log_f64", true, [OpArg.LOCAL], &op_log_f64 };
Opcode EXP_F64 = { "exp_f64", true, [OpArg.LOCAL], &op_exp_f64 };
Opcode POW_F64 = { "pow_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_pow_f64 };

// Integer operations with overflow handling
Opcode ADD_I32_OVF = { "add_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], &op_add_i32_ovf, OpInfo.BRANCH };
Opcode SUB_I32_OVF = { "sub_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], &op_sub_i32_ovf, OpInfo.BRANCH };
Opcode MUL_I32_OVF = { "mul_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], &op_mul_i32_ovf, OpInfo.BRANCH };
Opcode LSFT_I32_OVF = { "lsft_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], &op_lsft_i32_ovf, OpInfo.BRANCH };

// Integer comparison instructions
Opcode EQ_I32 = { "eq_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_i32 };
Opcode NE_I32 = { "ne_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_i32 };
Opcode LT_I32 = { "lt_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_lt_i32 };
Opcode GT_I32 = { "gt_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_gt_i32 };
Opcode LE_I32 = { "le_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_le_i32 };
Opcode GE_I32 = { "ge_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ge_i32 };
Opcode EQ_I8 = { "eq_i8", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_i8 };

// Pointer comparison instructions
Opcode EQ_REFPTR = { "eq_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_refptr };
Opcode NE_REFPTR = { "ne_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_refptr };

// Constant comparison instructions
Opcode EQ_CONST = { "eq_const", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_const };
Opcode NE_CONST = { "ne_const", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_const };

// Floating-point comparison instructions
Opcode EQ_F64 = { "eq_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_f64 };
Opcode NE_F64 = { "ne_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_f64 };
Opcode LT_F64 = { "lt_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_lt_f64 };
Opcode GT_F64 = { "gt_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_gt_f64 };
Opcode LE_F64 = { "le_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_le_f64 };
Opcode GE_F64 = { "ge_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ge_f64 };

// Load instructions
Opcode LOAD_U8 = { "load_u8", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_u8 };
Opcode LOAD_U16 = { "load_u16", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_u16 };
Opcode LOAD_U32 = { "load_u32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_u32 };
Opcode LOAD_U64 = { "load_u64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_u64 };
Opcode LOAD_F64 = { "load_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_f64 };
Opcode LOAD_REFPTR = { "load_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_refptr };
Opcode LOAD_RAWPTR = { "load_rawptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_rawptr };
Opcode LOAD_FUNPTR = { "load_funptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_load_funptr };

// Store instructions
Opcode STORE_U8 = { "store_u8", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u8 };
Opcode STORE_U16 = { "store_u16", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u16 };
Opcode STORE_U32 = { "store_u32", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u32 };
Opcode STORE_U64 = { "store_u64", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u64 };
Opcode STORE_F64 = { "store_f64", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_f64 };
Opcode STORE_REFPTR = { "store_refptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_refptr };
Opcode STORE_RAWPTR = { "store_rawptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_rawptr };
Opcode STORE_FUNPTR = { "store_funptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_funptr };

// Branching and conditional branching
Opcode JUMP = { "jump", false, [], &op_jump, OpInfo.BRANCH };
Opcode IF_TRUE = { "if_true", false, [OpArg.LOCAL], &op_if_true, OpInfo.BRANCH };

// <dstLocal> = CALL <closLocal> <thisArg> ...
// Makes the execution go to the callee entry
// Sets the frame pointer to the new frame's base
// Pushes the return address word
Opcode CALL = { "call", true, [OpArg.LOCAL, OpArg.LOCAL], &op_call, OpInfo.VAR_ARG | OpInfo.BRANCH | OpInfo.CALL };

// <dstLocal> = CALL_NEW <closLocal> ...
// Implements the JavaScript new operator.
// Creates the this object
// Makes the execution go to the callee entry
// Sets the frame pointer to the new frame's base
// Pushes the return address word
Opcode CALL_NEW = { "call_new", true, [OpArg.LOCAL], &op_call_new, OpInfo.VAR_ARG | OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC };

// <dstLocal> = CALL_APPLY <closArg> <thisArg> <argTable> <numArgs>
// Call with an array of arguments
Opcode CALL_APPLY = { "call_apply", true, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_call_apply, OpInfo.BRANCH | OpInfo.CALL };

// RET <retLocal>
// Pops the callee frame (size known by context)
Opcode RET = { "ret", false, [OpArg.LOCAL], &op_ret, OpInfo.BRANCH };

// THROW <excLocal>
// Throws an exception, unwinds the stack
Opcode THROW = { "throw", false, [OpArg.LOCAL], &op_throw, OpInfo.BRANCH };

// Access visible arguments by index
Opcode GET_ARG = { "get_arg", true, [OpArg.LOCAL], &op_get_arg };

// Get a pointer to an IRFunction object
Opcode GET_FUN_PTR = { "get_fun_ptr", true, [OpArg.FUN], &op_get_fun_ptr };

// Special implementation object/value access instructions
Opcode GET_OBJ_PROTO = { "get_obj_proto", true, [], &op_get_obj_proto };
Opcode GET_ARR_PROTO = { "get_arr_proto", true, [], &op_get_arr_proto };
Opcode GET_FUN_PROTO = { "get_fun_proto", true, [], &op_get_fun_proto };
Opcode GET_GLOBAL_OBJ = { "get_global_obj", true, [], &op_get_global_obj };
Opcode GET_HEAP_SIZE = { "get_heap_size", true, [], &op_get_heap_size };
Opcode GET_HEAP_FREE = { "get_heap_free", true, [], &op_get_heap_free };
Opcode GET_GC_COUNT = { "get_gc_count", true, [], &op_get_gc_count };

/// Allocate a block of memory on the heap
Opcode HEAP_ALLOC = { "heap_alloc", true, [OpArg.LOCAL], &op_heap_alloc, OpInfo.MAY_GC };

/// Trigger a garbage collection
Opcode GC_COLLECT = { "gc_collect", false, [OpArg.LOCAL], &op_gc_collect, OpInfo.MAY_GC };

/// Create a link table entry associated with this instruction
Opcode MAKE_LINK = { "make_link", true, [OpArg.LINK], &op_make_link };

/// Set the value of a link table entry
Opcode SET_LINK = { "set_link", false, [OpArg.LOCAL, OpArg.LOCAL], &op_set_link };

/// Get the value of a link table entry
Opcode GET_LINK = { "get_link", true, [OpArg.LOCAL], &op_get_link };

/// Compute the hash code for a string and
/// try to find the string in the string table
Opcode GET_STR = { "get_str", true, [OpArg.LOCAL], &op_get_str, OpInfo.MAY_GC };

/// GET_GLOBAL <propName>
/// Note: hidden parameter is cached global property index
Opcode GET_GLOBAL = { "get_global", true, [OpArg.STRING, OpArg.INT32], &op_get_global, OpInfo.MAY_GC };

/// SET_GLOBAL <propName> <value>
/// Note: hidden parameter is cached global property index
Opcode SET_GLOBAL = { "set_global", false, [OpArg.STRING, OpArg.LOCAL, OpArg.INT32], &op_set_global, OpInfo.MAY_GC };

/// <dstLocal> = NEW_CLOS <funExpr>
/// Create a new closure from a function's AST node
Opcode NEW_CLOS = { "new_clos", true, [OpArg.FUN, OpArg.LINK, OpArg.LINK], &op_new_clos, OpInfo.MAY_GC };

/// Load a source code unit from a file
Opcode LOAD_FILE = { "load_file", true, [OpArg.LOCAL], &op_load_file, OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC };

/// Evaluate a source string in the global scope
Opcode EVAL_STR = { "eval_str", true, [OpArg.LOCAL], &op_eval_str, OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC };

/// Print a string to standard output
Opcode PRINT_STR = { "print_str", false, [OpArg.LOCAL], &op_print_str };

/// Get a string representation of a function's AST
Opcode GET_AST_STR = { "get_ast_str", true, [OpArg.LOCAL], &op_get_ast_str, OpInfo.MAY_GC };

/// Get a string representation of a function's IR
Opcode GET_IR_STR = { "get_ir_str", true, [OpArg.LOCAL], &op_get_ir_str, OpInfo.MAY_GC };

/// Format a floating-point value as a string
Opcode F64_TO_STR = { "f64_to_str", true, [OpArg.LOCAL], &op_f64_to_str, OpInfo.MAY_GC };

/// Get the time in milliseconds since process start
Opcode GET_TIME_MS = { "get_time_ms", true, [], &op_get_time_ms };

