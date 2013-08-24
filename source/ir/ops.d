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

module ir.ops;

import ir.ir;
import interp.interp;
import interp.ops;

/**
Opcode argument type
*/
enum OpArg
{
    INT32,
    FLOAT64,
    RAWPTR,
    STRING,
    LOCAL,
    LINK,
    FUN,
    CODEBLOCK
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
        VAR_ARG     = 1 << 0,
        BRANCH      = 1 << 1,
        CALL        = 1 << 2,
        MAY_GC      = 1 << 3,
        BOOL_VAL    = 1 << 4,
        IMPURE      = 1 << 5
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
    bool boolVal () const { return (opFlags & BOOL_VAL) != 0; }
    bool isImpure() const { return (opFlags & IMPURE) != 0; }

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
Opcode SET_STR = { "set_str", true, [OpArg.STRING, OpArg.LINK], &op_set_str };

// Word/type manipulation primitives
Opcode MAKE_VALUE = { "make_value", true, [OpArg.LOCAL, OpArg.LOCAL], &op_make_value };
Opcode GET_WORD = { "get_word", true, [OpArg.LOCAL], &op_get_word };
Opcode GET_TYPE = { "get_type", true, [OpArg.LOCAL], &op_get_type };

// Type tag test
Opcode IS_I32 = { "is_i32", true, [OpArg.LOCAL], &op_is_i32, OpInfo.BOOL_VAL };
Opcode IS_I64 = { "is_i64", true, [OpArg.LOCAL], &op_is_i64, OpInfo.BOOL_VAL };
Opcode IS_F64 = { "is_f64", true, [OpArg.LOCAL], &op_is_f64, OpInfo.BOOL_VAL };
Opcode IS_REFPTR = { "is_refptr", true, [OpArg.LOCAL], &op_is_refptr, OpInfo.BOOL_VAL };
Opcode IS_RAWPTR = { "is_rawptr", true, [OpArg.LOCAL], &op_is_rawptr, OpInfo.BOOL_VAL };
Opcode IS_CONST  = { "is_const", true, [OpArg.LOCAL], &op_is_const, OpInfo.BOOL_VAL };

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
Opcode EQ_I32 = { "eq_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_i32, OpInfo.BOOL_VAL };
Opcode NE_I32 = { "ne_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_i32, OpInfo.BOOL_VAL };
Opcode LT_I32 = { "lt_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_lt_i32, OpInfo.BOOL_VAL };
Opcode GT_I32 = { "gt_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_gt_i32, OpInfo.BOOL_VAL };
Opcode LE_I32 = { "le_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_le_i32, OpInfo.BOOL_VAL };
Opcode GE_I32 = { "ge_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ge_i32, OpInfo.BOOL_VAL };
Opcode EQ_I8 = { "eq_i8", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_i8, OpInfo.BOOL_VAL };

// Pointer comparison instructions
Opcode EQ_REFPTR = { "eq_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_refptr, OpInfo.BOOL_VAL };
Opcode NE_REFPTR = { "ne_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_refptr, OpInfo.BOOL_VAL };
Opcode EQ_RAWPTR = { "eq_rawptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_rawptr, OpInfo.BOOL_VAL };
Opcode NE_RAWPTR = { "ne_rawptr", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_rawptr, OpInfo.BOOL_VAL };

// Constant comparison instructions
Opcode EQ_CONST = { "eq_const", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_const, OpInfo.BOOL_VAL };
Opcode NE_CONST = { "ne_const", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_const, OpInfo.BOOL_VAL };

// Floating-point comparison instructions
Opcode EQ_F64 = { "eq_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_eq_f64, OpInfo.BOOL_VAL };
Opcode NE_F64 = { "ne_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ne_f64, OpInfo.BOOL_VAL };
Opcode LT_F64 = { "lt_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_lt_f64, OpInfo.BOOL_VAL };
Opcode GT_F64 = { "gt_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_gt_f64, OpInfo.BOOL_VAL };
Opcode LE_F64 = { "le_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_le_f64, OpInfo.BOOL_VAL };
Opcode GE_F64 = { "ge_f64", true, [OpArg.LOCAL, OpArg.LOCAL], &op_ge_f64, OpInfo.BOOL_VAL };

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
Opcode STORE_U8 = { "store_u8", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u8, OpInfo.IMPURE };
Opcode STORE_U16 = { "store_u16", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u16, OpInfo.IMPURE };
Opcode STORE_U32 = { "store_u32", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u32, OpInfo.IMPURE };
Opcode STORE_U64 = { "store_u64", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_u64, OpInfo.IMPURE };
Opcode STORE_F64 = { "store_f64", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_f64, OpInfo.IMPURE };
Opcode STORE_REFPTR = { "store_refptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_refptr, OpInfo.IMPURE };
Opcode STORE_RAWPTR = { "store_rawptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_rawptr, OpInfo.IMPURE };
Opcode STORE_FUNPTR = { "store_funptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], &op_store_funptr, OpInfo.IMPURE };

// Unconditional jump
Opcode JUMP = { "jump", false, [], &op_jump, OpInfo.BRANCH };

// Branch based on a boolean value
Opcode IF_TRUE = { "if_true", false, [OpArg.LOCAL], &op_if_true, OpInfo.BRANCH };

// Test if a closure is an instance of a given
// function and branch based on the result
// This instruction is used for conditional inlining
Opcode IF_EQ_FUN = { "if_eq_fun", false, [OpArg.LOCAL, OpArg.FUN], &op_if_eq_fun, OpInfo.BRANCH };

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
Opcode GC_COLLECT = { "gc_collect", false, [OpArg.LOCAL], &op_gc_collect, OpInfo.MAY_GC | OpInfo.IMPURE };

/// Create a link table entry associated with this instruction
Opcode MAKE_LINK = { "make_link", true, [OpArg.LINK], &op_make_link };

/// Set the value of a link table entry
Opcode SET_LINK = { "set_link", false, [OpArg.LOCAL, OpArg.LOCAL], &op_set_link, OpInfo.IMPURE };

/// Get the value of a link table entry
Opcode GET_LINK = { "get_link", true, [OpArg.LOCAL], &op_get_link };

/// Compute the hash code for a string and
/// try to find the string in the string table
Opcode GET_STR = { "get_str", true, [OpArg.LOCAL], &op_get_str, OpInfo.MAY_GC };

/// GET_GLOBAL <propName>
/// Note: hidden parameter is cached global property index
Opcode GET_GLOBAL = { "get_global", true, [OpArg.STRING, OpArg.INT32], &op_get_global, OpInfo.MAY_GC | OpInfo.IMPURE };

/// SET_GLOBAL <propName> <value>
/// Note: hidden parameter is cached global property index
Opcode SET_GLOBAL = { "set_global", false, [OpArg.STRING, OpArg.LOCAL, OpArg.INT32], &op_set_global, OpInfo.MAY_GC | OpInfo.IMPURE };

/// <dstLocal> = NEW_CLOS <funExpr>
/// Create a new closure from a function's AST node
Opcode NEW_CLOS = { "new_clos", true, [OpArg.FUN, OpArg.LINK, OpArg.LINK], &op_new_clos, OpInfo.MAY_GC };

/// Load a source code unit from a file
Opcode LOAD_FILE = { "load_file", true, [OpArg.LOCAL], &op_load_file, OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC | OpInfo.IMPURE };

/// Evaluate a source string in the global scope
Opcode EVAL_STR = { "eval_str", true, [OpArg.LOCAL], &op_eval_str, OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC | OpInfo.IMPURE };

/// Print a string to standard output
Opcode PRINT_STR = { "print_str", false, [OpArg.LOCAL], &op_print_str, OpInfo.IMPURE };

/// Get a string representation of a function's AST
Opcode GET_AST_STR = { "get_ast_str", true, [OpArg.LOCAL], &op_get_ast_str, OpInfo.MAY_GC };

/// Get a string representation of a function's IR
Opcode GET_IR_STR = { "get_ir_str", true, [OpArg.LOCAL], &op_get_ir_str, OpInfo.MAY_GC };

/// Format a floating-point value as a string
Opcode F64_TO_STR = { "f64_to_str", true, [OpArg.LOCAL], &op_f64_to_str, OpInfo.MAY_GC };

/// Format a floating-point value as a string (long)
Opcode F64_TO_STR_LNG = { "f64_to_str_lng", true, [OpArg.LOCAL], &op_f64_to_str_lng, OpInfo.MAY_GC };

/// Get the time in milliseconds since process start
Opcode GET_TIME_MS = { "get_time_ms", true, [], &op_get_time_ms };

/// Load a shared lib
Opcode LOAD_LIB = { "load_lib", true, [OpArg.LOCAL], &op_load_lib };

/// Close shared lib
Opcode CLOSE_LIB = { "close_lib", false, [OpArg.LOCAL], &op_close_lib, OpInfo.IMPURE };

/// Lookup symbol in shared lib
Opcode GET_SYM = { "get_sym", true, [OpArg.LOCAL, OpArg.STRING], &op_get_sym };

/// Call function in shared lib
Opcode CALL_FFI = { "call_ffi", true, [OpArg.CODEBLOCK, OpArg.LOCAL, OpArg.STRING], &op_call_ffi, OpInfo.BRANCH | OpInfo.CALL | OpInfo.VAR_ARG };

