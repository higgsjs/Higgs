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

/// Local variable index type
alias uint LocalIdx;

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
            if (i != params.length - 1)
                output.put(", ");
            output.put(params[i].toString());
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
        /// Instruction argument type
        alias uint Type;
        enum : Type
        {
            INT,
            FLOAT,
            STRING,
            LOCAL,
            BLOCK,
            FUN
        }

        long intVal;
        double floatVal;
        string stringVal;
        LocalIdx localIdx;
        IRBlock block;
        IRFunction fun;
    }

    /// Instruction type information
    struct TypeInfo
    {
        string mnem;
        bool output;
        Arg.Type[] argTypes;
    }

    /// Instruction type (opcode) alias
    alias static immutable(TypeInfo) Type;

    // Set a local slot to a constant value    
    Type SET_INT    = { "set_int"   , true, [Arg.INT] };
    Type SET_FLOAT  = { "set_float" , true, [Arg.FLOAT] };
    //FIXME: need string table
    //Type SET_STR    = { "set_str"   , true, [Arg.STRING] };
    Type SET_TRUE   = { "set_true"  , true, [] };
    Type SET_FALSE  = { "set_false" , true, [] };
    Type SET_NULL   = { "set_null"  , true, [] };
    Type SET_UNDEF  = { "set_undef" , true, [] };

    // Move a value from one local to another
    Type MOVE       = { "move", true, [Arg.LOCAL] };

    // Arithmetic operations
    Type ADD        = { "add", true, [Arg.LOCAL, Arg.LOCAL] };
    Type SUB        = { "sub", true, [Arg.LOCAL, Arg.LOCAL] };
    Type MUL        = { "mul", true, [Arg.LOCAL, Arg.LOCAL] };
    Type DIV        = { "div", true, [Arg.LOCAL, Arg.LOCAL] };
    Type MOD        = { "mod", true, [Arg.LOCAL, Arg.LOCAL] };

    // Bitwise operations
    Type NOT        = { "xor"    , true, [Arg.LOCAL] };
    Type AND        = { "and"    , true, [Arg.LOCAL, Arg.LOCAL] };
    Type OR         = { "or"     , true, [Arg.LOCAL, Arg.LOCAL] };
    Type XOR        = { "xor"    , true, [Arg.LOCAL, Arg.LOCAL] };
    Type LSHIFT     = { "lshift" , true, [Arg.LOCAL, Arg.LOCAL] };
    Type RSHIFT     = { "rshift" , true, [Arg.LOCAL, Arg.LOCAL] };
    Type URSHIFT    = { "urshift", true, [Arg.LOCAL, Arg.LOCAL] };

    // Boolean value conversion
    Type BOOL_VAL    = { "bool_val", true, [Arg.LOCAL] };

    // Boolean (logical) negation
    Type BOOL_NOT    = { "bool_not", true, [Arg.LOCAL] };

    // Comparison operations
    Type CMP_SE     = { "cmp_se", true, [Arg.LOCAL, Arg.LOCAL] };
    Type CMP_NS     = { "cmp_ns", true, [Arg.LOCAL, Arg.LOCAL] };
    Type CMP_EQ     = { "cmp_eq", true, [Arg.LOCAL, Arg.LOCAL] };
    Type CMP_NE     = { "cmp_ne", true, [Arg.LOCAL, Arg.LOCAL] };
    Type CMP_LT     = { "cmp_lt", true, [Arg.LOCAL, Arg.LOCAL] };
    Type CMP_LE     = { "cmp_le", true, [Arg.LOCAL, Arg.LOCAL] };
    Type CMP_GT     = { "cmp_gt", true, [Arg.LOCAL, Arg.LOCAL] };
    Type CMP_GE     = { "cmp_ge", true, [Arg.LOCAL, Arg.LOCAL] };

    // Branching and conditional branching
    Type JUMP       = { "jump"      , false, [Arg.BLOCK] };
    Type JUMP_TRUE  = { "jump_true" , false, [Arg.LOCAL, Arg.BLOCK] };
    Type JUMP_FALSE = { "jump_false", false, [Arg.LOCAL, Arg.BLOCK] };

    // SET_ARG <srcLocal> <argIdx>
    Type SET_ARG    = { "ret", false, [Arg.LOCAL, Arg.INT] };

    // CALL <fnLocal> <thisArg> <numArgs>
    // Makes the execution go to the callee entry
    // Sets the frame pointer to the new frame's base
    // Pushes the return address word
    Type CALL       = { "call", false, [Arg.LOCAL, Arg.LOCAL, Arg.INT] };

    // PUSH_FRAME <numArgs> <numLocals>
    // On function entry, allocates/adjusts the callee's stack frame
    Type PUSH_FRAME = { "push_frame", false, [Arg.INT, Arg.INT] };

    // <retLocal> = GET_RET
    // After call, extracts the callee's return value
    Type GET_RET    = { "get_ret", true, [] };

    // RET <retLocal> <raSlot> <numLocals>
    // Stores return value in special registers
    // Pops the callee frame (size known by context)
    Type RET        = { "ret", false, [Arg.LOCAL, Arg.LOCAL, Arg.INT] };

    // <dstLocal> = NEW_CLOS <funExpr>
    // Create a new closure from a function's AST node
    Type NEW_CLOS = { "new_clos", true, [Arg.FUN] };

    // Create new object
    //NEW_OBJ,

    //SET_GLOBAL,
    //GET_GLOBAL,

    // SET_FIELD <obj_local> <name_local> <src_local>
    //SET_FIELD,

    // <dst_local> = GET_FIELD <obj_local> <name_local>
    //GET_FIELD,

    /// Instruction type
    Type* type;

    /// Instruction arguments
    Arg[MAX_ARGS] args;

    /// Output local slot
    LocalIdx outSlot = NULL_LOCAL;
    
    /// Previous and next instructions
    IRInstr prev;
    IRInstr next;

    this(Type* type)
    {
        this.type = type;
    }

    /// Binary constructor
    this(Type* type, LocalIdx outSlot, LocalIdx arg0, LocalIdx arg1)
    {
        assert (
            type.output == true &&
            type.argTypes.length == 2 &&
            type.argTypes[0] == Arg.LOCAL &&
            type.argTypes[1] == Arg.LOCAL
        );

        this.type = type;
        this.outSlot = outSlot;
        this.args[0].localIdx = arg0;
        this.args[1].localIdx = arg1;
    }

    /// Unary constructor
    this(Type* type, LocalIdx outSlot, LocalIdx arg0)
    {
        assert (
            (type.output == true || outSlot == NULL_LOCAL) &&
            type.argTypes.length == 1 &&
            type.argTypes[0] == Arg.LOCAL,
            "invalid instruction for ctor: " ~ type.mnem
        );

        this.type = type;
        this.outSlot = outSlot;
        this.args[0].localIdx = arg0;
    }

    /// No argument constructor
    this(Type* type, LocalIdx outSlot)
    {
        assert (
            type.output == true &&
            type.argTypes.length == 0,
            "invalid instruction for ctor: " ~ type.mnem
        );

        this.type = type;
        this.outSlot = outSlot;
    }

    /// Conditional branching constructor
    this(Type* type, LocalIdx arg0, IRBlock block)
    {
        assert (
            type.output == false &&
            type.argTypes.length == 2 &&
            type.argTypes[0] == Arg.LOCAL &&
            type.argTypes[1] == Arg.BLOCK,
            "invalid instruction for ctor: " ~ type.mnem
        );

        this.type = type;
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

        if (type.output)
            output ~= "$" ~ to!string(outSlot) ~ " = ";

        output ~= type.mnem;

        if (type.argTypes.length > 0)
            output ~= " ";

        for (size_t i = 0; i < type.argTypes.length; ++i)
        {
            auto arg = args[i];

            if (i > 0)
                output ~= ", ";

            switch (type.argTypes[i])
            {
                case Arg.INT    : output ~= to!string(arg.intVal); break;
                case Arg.FLOAT  : output ~= to!string(arg.floatVal); break;
                case Arg.STRING : output ~= arg.stringVal; break;
                case Arg.LOCAL  : output ~= "$" ~ to!string(arg.localIdx); break;
                case Arg.BLOCK  : output ~= arg.block.getName(); break;
                case Arg.FUN    : output ~= "<fun:" ~ arg.fun.getName() ~ ">"; break;

                default: assert (false, "unhandled arg type");
            }
        }

        return output;
    }
}

