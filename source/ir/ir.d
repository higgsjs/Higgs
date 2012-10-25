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

module ir.ir;

import std.stdio;
import std.array;
import std.string;
import std.conv;
import std.regex;
import util.id;
import util.string;
import parser.ast;
import interp.interp;
import interp.ops;

/// Local variable index type
alias size_t LocalIdx;

/// Null local constant
immutable LocalIdx NULL_LOCAL = LocalIdx.max;

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

    // Function parameters
    IdentExpr[] params;

    /// Entry block
    IRBlock entryBlock = null;

    /// First and last basic blocks
    IRBlock firstBlock = null;
    IRBlock lastBlock = null;

    // Number of local variables
    uint numLocals = 0;

    // Hidden argument slots
    LocalIdx closSlot;
    LocalIdx thisSlot;
    LocalIdx argcSlot;
    LocalIdx raSlot;

    /// Constructor
    this(FunExpr ast)
    {
        this.ast = ast;
        this.params = ast.params;

        this.name = ast.getName();

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

    string toString()
    {
        auto output = appender!string();

        output.put("function ");
        output.put(getName());
        output.put("(");

        for (size_t i = 0; i < params.length; ++i)
        {
            output.put(params[i].toString());
            if (i != params.length - 1)
                output.put(", ");
        }

        output.put(")\n");
        output.put("{\n");

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

/**
IR basic block
*/
class IRBlock : IdObject
{
    /// Block name (non-unique)
    private string name;

    IRInstr firstInstr;
    IRInstr lastInstr;
    
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

    void addInstr(IRInstr instr)
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
    }

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
    /// Maximum number of instruction arguments
    immutable int MAX_ARGS = 3;

    /// Instruction argument
    union Arg
    {
        long intVal;
        double floatVal;
        ubyte* ptrVal;
        wstring stringVal;
        LocalIdx localIdx;
        IRBlock block;
        IRFunction fun;
    }

    /// Opcode
    Opcode* opcode;

    /// Instruction arguments
    Arg[MAX_ARGS] args;

    /// Output local slot
    LocalIdx outSlot = NULL_LOCAL;
    
    /// Previous and next instructions
    IRInstr prev;
    IRInstr next;

    this(Opcode* opcode)
    {
        this.opcode = opcode;
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
        this.args[0].localIdx = arg0;
        this.args[1].localIdx = arg1;
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
        this.args[0].localIdx = arg0;
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

    /// Conditional branching constructor
    this(Opcode* opcode, LocalIdx arg0, IRBlock block)
    {
        assert (
            opcode.output == false &&
            opcode.argTypes.length == 2 &&
            opcode.argTypes[0] == OpArg.LOCAL &&
            opcode.argTypes[1] == OpArg.BLOCK,
            "invalid instruction for ctor: " ~ opcode.mnem
        );

        this.opcode = opcode;
        this.args[0].localIdx = arg0;
        this.args[1].block = block;
    }

    /// Integer constant
    static intCst(LocalIdx outSlot, long intVal)
    {
        auto cst = new this(&SET_INT);
        cst.args[0].intVal = intVal;
        cst.outSlot = outSlot;

        return cst;
    }

    /// Floating-point constant
    static floatCst(LocalIdx outSlot, double floatVal)
    {
        auto cst = new this(&SET_FLOAT);
        cst.args[0].floatVal = floatVal;
        cst.outSlot = outSlot;

        return cst;
    }

    /// String constant
    static strCst(LocalIdx outSlot, wstring stringVal)
    {
        auto cst = new this(&SET_STR);
        cst.args[0].stringVal = stringVal;
        cst.args[1].ptrVal = null;
        cst.outSlot = outSlot;

        return cst;
    }

    /// Jump instruction
    static jump(IRBlock block)
    {
        auto jump = new this(&JUMP);
        jump.args[0].block = block;

        return jump;
    }

    final string toString()
    {
        string output;

        if (opcode.output)
            output ~= "$" ~ to!string(outSlot) ~ " = ";

        output ~= opcode.mnem;

        if (opcode.argTypes.length > 0)
            output ~= " ";

        for (size_t i = 0; i < opcode.argTypes.length; ++i)
        {
            auto arg = args[i];

            if (i > 0)
                output ~= ", ";

            switch (opcode.argTypes[i])
            {
                case OpArg.INT    : output ~= to!string(arg.intVal); break;
                case OpArg.FLOAT  : output ~= to!string(arg.floatVal); break;
                case OpArg.STRING : output ~= "\"" ~ to!string(arg.stringVal) ~ "\""; break;
                case OpArg.LOCAL  : output ~= "$" ~ to!string(arg.localIdx); break;
                case OpArg.BLOCK  : output ~= arg.block.getName(); break;
                case OpArg.FUN    : output ~= "<fun:" ~ arg.fun.getName() ~ ">"; break;
                case OpArg.REFPTR : output ~= "<ref:" ~ to!string(arg.ptrVal) ~ ">"; break;
                default: assert (false, "unhandled arg type");
            }
        }

        return output;
    }
}

/**
Opcode argument type
*/
enum OpArg
{
    INT,
    FLOAT,
    REFPTR,
    STRING,
    LOCAL,
    BLOCK,
    FUN
}

/// Opcode implementation function
alias void function(Interp interp, IRInstr instr) OpFun;

/**
Opcode information
*/
struct OpInfo
{
    string mnem;
    bool output;
    OpArg[] argTypes;
    OpFun opFun = null;
}

/// Instruction type (opcode) alias
alias static immutable(OpInfo) Opcode;

// Set a local slot to a constant value    
Opcode SET_INT    = { "set_int"   , true, [OpArg.INT], &opSetInt };
Opcode SET_FLOAT  = { "set_float" , true, [OpArg.FLOAT]/*, &opSetFloat*/ };
Opcode SET_STR    = { "set_str"   , true, [OpArg.STRING, OpArg.REFPTR], &opSetStr };
Opcode SET_TRUE   = { "set_true"  , true, [], &opSetTrue };
Opcode SET_FALSE  = { "set_false" , true, [], &opSetFalse };
Opcode SET_NULL   = { "set_null"  , true, [], &opSetNull };
Opcode SET_UNDEF  = { "set_undef" , true, [], &opSetUndef };

// Move a value from one local to another
Opcode MOVE       = { "move", true, [OpArg.LOCAL], &opMove };

// Arithmetic operations
Opcode ADD        = { "add", true, [OpArg.LOCAL, OpArg.LOCAL], &opAdd };
Opcode SUB        = { "sub", true, [OpArg.LOCAL, OpArg.LOCAL], &opSub };
Opcode MUL        = { "mul", true, [OpArg.LOCAL, OpArg.LOCAL], &opMul };
Opcode DIV        = { "div", true, [OpArg.LOCAL, OpArg.LOCAL], &opDiv };
Opcode MOD        = { "mod", true, [OpArg.LOCAL, OpArg.LOCAL], &opMod };

// Bitwise operations
Opcode NOT        = { "xor"    , true, [OpArg.LOCAL] };
Opcode AND        = { "and"    , true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode OR         = { "or"     , true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode XOR        = { "xor"    , true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode LSHIFT     = { "lshift" , true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode RSHIFT     = { "rshift" , true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode URSHIFT    = { "urshift", true, [OpArg.LOCAL, OpArg.LOCAL] };

// Boolean value conversion
Opcode BOOL_VAL    = { "bool_val", true, [OpArg.LOCAL], &opBoolVal };

// Boolean (logical) negation
Opcode BOOL_NOT    = { "bool_not", true, [OpArg.LOCAL] };

// Comparison operations
Opcode CMP_SE     = { "cmp_se", true, [OpArg.LOCAL, OpArg.LOCAL], &opCmpSe };
Opcode CMP_NS     = { "cmp_ns", true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode CMP_EQ     = { "cmp_eq", true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode CMP_NE     = { "cmp_ne", true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode CMP_LT     = { "cmp_lt", true, [OpArg.LOCAL, OpArg.LOCAL], &opCmpLt };
Opcode CMP_LE     = { "cmp_le", true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode CMP_GT     = { "cmp_gt", true, [OpArg.LOCAL, OpArg.LOCAL] };
Opcode CMP_GE     = { "cmp_ge", true, [OpArg.LOCAL, OpArg.LOCAL] };

// Branching and conditional branching
Opcode JUMP       = { "jump"      , false, [OpArg.BLOCK], &opJump };
Opcode JUMP_TRUE  = { "jump_true" , false, [OpArg.LOCAL, OpArg.BLOCK], &opJumpTrue };
Opcode JUMP_FALSE = { "jump_false", false, [OpArg.LOCAL, OpArg.BLOCK], &opJumpFalse };

// SET_ARG <srcLocal> <argIdx>
Opcode SET_ARG    = { "set_arg", false, [OpArg.LOCAL, OpArg.INT], &opSetArg };

// CALL <closLocal> <thisArg> <numArgs>
// Makes the execution go to the callee entry
// Sets the frame pointer to the new frame's base
// Pushes the return address word
Opcode CALL       = { "call", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.INT], &opCall };

// PUSH_FRAME <numParams> <numLocals>
// On function entry, allocates/adjusts the callee's stack frame
Opcode PUSH_FRAME = { "push_frame", false, [OpArg.INT, OpArg.INT], &opPushFrame };

// RET <retLocal> <raSlot> <numLocals>
// Stores return value in special registers
// Pops the callee frame (size known by context)
Opcode RET        = { "ret", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.INT], &opRet };

// <retLocal> = GET_RET
// After call, extracts the callee's return value
Opcode GET_RET    = { "get_ret", true, [], &opGetRet };

// <dstLocal> = NEW_CLOS <funExpr>
// Create a new closure from a function's AST node
Opcode NEW_CLOS = { "new_clos", true, [OpArg.FUN], &opNewClos };

// SET_GLOBAL <prop_name> <value>
Opcode SET_GLOBAL = { "set_global", false, [OpArg.LOCAL, OpArg.LOCAL], &opSetGlobal };

// GET_GLOBAL <prop_name>
Opcode GET_GLOBAL = { "get_global", true, [OpArg.LOCAL], &opGetGlobal };

// Create new object
//NEW_OBJ,

// SET_FIELD <obj_local> <name_local> <src_local>
//SET_FIELD,

// <dst_local> = GET_FIELD <obj_local> <name_local>
//GET_FIELD,

