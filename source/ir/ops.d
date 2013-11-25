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
import jit.codeblock;
import jit.ops;

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
    MAP
}

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
    GenFn genFn;
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
Opcode SET_STR = { "set_str", true, [OpArg.STRING, OpArg.LINK], /*&gen_set_str*/null };

// Word/type manipulation primitives
Opcode MAKE_VALUE = { "make_value", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_make_value*/null };
Opcode GET_WORD = { "get_word", true, [OpArg.LOCAL], /*&gen_get_word*/null };
Opcode GET_TYPE = { "get_type", true, [OpArg.LOCAL], /*&gen_get_type*/null };

// Type tag test
Opcode IS_I32 = { "is_i32", true, [OpArg.LOCAL], /*&gen_is_i32*/null , OpInfo.BOOL_VAL };
Opcode IS_I64 = { "is_i64", true, [OpArg.LOCAL], /*&gen_is_i64*/null , OpInfo.BOOL_VAL };
Opcode IS_F64 = { "is_f64", true, [OpArg.LOCAL], /*&gen_is_f64*/null , OpInfo.BOOL_VAL };
Opcode IS_REFPTR = { "is_refptr", true, [OpArg.LOCAL], /*&gen_is_refptr*/null , OpInfo.BOOL_VAL };
Opcode IS_RAWPTR = { "is_rawptr", true, [OpArg.LOCAL], /*&gen_is_rawptr*/null , OpInfo.BOOL_VAL };
Opcode IS_CONST  = { "is_const", true, [OpArg.LOCAL], /*&gen_is_const*/null , OpInfo.BOOL_VAL };

// Type conversion
Opcode I32_TO_F64 = { "i32_to_f64", true, [OpArg.LOCAL], /*&gen_i32_to_f64*/null };
Opcode F64_TO_I32 = { "f64_to_i32", true, [OpArg.LOCAL], /*&gen_f64_to_i32*/null };

// Integer arithmetic
Opcode ADD_I32 = { "add_i32", true, [OpArg.LOCAL, OpArg.LOCAL], &gen_add_i32 };
Opcode SUB_I32 = { "sub_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_sub_i32*/null };
Opcode MUL_I32 = { "mul_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_mul_i32*/null };
Opcode DIV_I32 = { "div_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_div_i32*/null };
Opcode MOD_I32 = { "mod_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_mod_i32*/null };

// Bitwise operations
Opcode AND_I32 = { "and_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_and_i32*/null };
Opcode OR_I32 = { "or_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_or_i32*/null };
Opcode XOR_I32 = { "xor_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_xor_i32*/null };
Opcode LSFT_I32 = { "lsft_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_lsft_i32*/null };
Opcode RSFT_I32 = { "rsft_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_rsft_i32*/null };
Opcode URSFT_I32 = { "ursft_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ursft_i32*/null };
Opcode NOT_I32 = { "not_i32", true, [OpArg.LOCAL], /*&gen_not_i32*/null };

// Floating-point arithmetic
Opcode ADD_F64 = { "add_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_add_f64*/null };
Opcode SUB_F64 = { "sub_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_sub_f64*/null };
Opcode MUL_F64 = { "mul_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_mul_f64*/null };
Opcode DIV_F64 = { "div_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_div_f64*/null };
Opcode MOD_F64 = { "mod_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_mod_f64*/null };

// Higher-level floating-point functions
Opcode SIN_F64 = { "sin_f64", true, [OpArg.LOCAL], /*&gen_sin_f64*/null };
Opcode COS_F64 = { "cos_f64", true, [OpArg.LOCAL], /*&gen_cos_f64*/null };
Opcode SQRT_F64 = { "sqrt_f64", true, [OpArg.LOCAL], /*&gen_sqrt_f64*/null };
Opcode CEIL_F64 = { "ceil_f64", true, [OpArg.LOCAL], /*&gen_ceil_f64*/null };
Opcode FLOOR_F64 = { "floor_f64", true, [OpArg.LOCAL], /*&gen_floor_f64*/null };
Opcode LOG_F64 = { "log_f64", true, [OpArg.LOCAL], /*&gen_log_f64*/null };
Opcode EXP_F64 = { "exp_f64", true, [OpArg.LOCAL], /*&gen_exp_f64*/null };
Opcode POW_F64 = { "pow_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_pow_f64*/null };

// Integer operations with overflow handling
Opcode ADD_I32_OVF = { "add_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_add_i32_ovf*/null , OpInfo.BRANCH };
Opcode SUB_I32_OVF = { "sub_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_sub_i32_ovf*/null , OpInfo.BRANCH };
Opcode MUL_I32_OVF = { "mul_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_mul_i32_ovf*/null , OpInfo.BRANCH };
Opcode LSFT_I32_OVF = { "lsft_i32_ovf", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_lsft_i32_ovf*/null , OpInfo.BRANCH };

// Integer comparison instructions
Opcode EQ_I32 = { "eq_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_eq_i32*/null , OpInfo.BOOL_VAL };
Opcode NE_I32 = { "ne_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ne_i32*/null , OpInfo.BOOL_VAL };
Opcode LT_I32 = { "lt_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_lt_i32*/null , OpInfo.BOOL_VAL };
Opcode GT_I32 = { "gt_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_gt_i32*/null , OpInfo.BOOL_VAL };
Opcode LE_I32 = { "le_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_le_i32*/null , OpInfo.BOOL_VAL };
Opcode GE_I32 = { "ge_i32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ge_i32*/null , OpInfo.BOOL_VAL };
Opcode EQ_I8 = { "eq_i8", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_eq_i8*/null , OpInfo.BOOL_VAL };

// Pointer comparison instructions
Opcode EQ_REFPTR = { "eq_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_eq_refptr*/null , OpInfo.BOOL_VAL };
Opcode NE_REFPTR = { "ne_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ne_refptr*/null , OpInfo.BOOL_VAL };
Opcode EQ_RAWPTR = { "eq_rawptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_eq_rawptr*/null , OpInfo.BOOL_VAL };
Opcode NE_RAWPTR = { "ne_rawptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ne_rawptr*/null , OpInfo.BOOL_VAL };

// Constant comparison instructions
Opcode EQ_CONST = { "eq_const", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_eq_const*/null , OpInfo.BOOL_VAL };
Opcode NE_CONST = { "ne_const", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ne_const*/null , OpInfo.BOOL_VAL };

// Floating-point comparison instructions
Opcode EQ_F64 = { "eq_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_eq_f64*/null , OpInfo.BOOL_VAL };
Opcode NE_F64 = { "ne_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ne_f64*/null , OpInfo.BOOL_VAL };
Opcode LT_F64 = { "lt_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_lt_f64*/null , OpInfo.BOOL_VAL };
Opcode GT_F64 = { "gt_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_gt_f64*/null , OpInfo.BOOL_VAL };
Opcode LE_F64 = { "le_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_le_f64*/null , OpInfo.BOOL_VAL };
Opcode GE_F64 = { "ge_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_ge_f64*/null , OpInfo.BOOL_VAL };

// Load instructions
Opcode LOAD_U8 = { "load_u8", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_u8*/null };
Opcode LOAD_U16 = { "load_u16", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_u16*/null };
Opcode LOAD_U32 = { "load_u32", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_u32*/null };
Opcode LOAD_U64 = { "load_u64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_u64*/null };
Opcode LOAD_I8 = { "load_i8", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_i8*/null };
Opcode LOAD_I16 = { "load_i16", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_i16*/null };
Opcode LOAD_F64 = { "load_f64", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_f64*/null };
Opcode LOAD_REFPTR = { "load_refptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_refptr*/null };
Opcode LOAD_RAWPTR = { "load_rawptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_rawptr*/null };
Opcode LOAD_FUNPTR = { "load_funptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_funptr*/null };
Opcode LOAD_MAPPTR = { "load_mapptr", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_load_mapptr*/null };

// Store instructions
Opcode STORE_U8 = { "store_u8", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_u8*/null , OpInfo.IMPURE };
Opcode STORE_U16 = { "store_u16", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_u16*/null , OpInfo.IMPURE };
Opcode STORE_U32 = { "store_u32", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_u32*/null , OpInfo.IMPURE };
Opcode STORE_U64 = { "store_u64", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_u64*/null , OpInfo.IMPURE };
Opcode STORE_I8 = { "store_i8", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_i8*/null , OpInfo.IMPURE };
Opcode STORE_I16 = { "store_i16", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_i16*/null , OpInfo.IMPURE };
Opcode STORE_F64 = { "store_f64", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_f64*/null , OpInfo.IMPURE };
Opcode STORE_REFPTR = { "store_refptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_refptr*/null , OpInfo.IMPURE };
Opcode STORE_RAWPTR = { "store_rawptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_rawptr*/null , OpInfo.IMPURE };
Opcode STORE_FUNPTR = { "store_funptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_funptr*/null , OpInfo.IMPURE };
Opcode STORE_MAPPTR = { "store_mapptr", false, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_store_mapptr*/null , OpInfo.IMPURE };

// Unconditional jump
Opcode JUMP = { "jump", false, [], /*&gen_jump*/null , OpInfo.BRANCH };

// Branch based on a boolean value
Opcode IF_TRUE = { "if_true", false, [OpArg.LOCAL], &gen_if_true, OpInfo.BRANCH };

// <dstLocal> = CALL <closLocal> <thisArg> ...
// Makes the execution go to the callee entry
// Sets the frame pointer to the new frame's base
// Pushes the return address word
Opcode CALL = { "call", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_call*/null , OpInfo.VAR_ARG | OpInfo.BRANCH | OpInfo.CALL };

// <dstLocal> = CALL_NEW <closLocal> ...
// Implements the JavaScript new operator.
// Creates the this object
// Makes the execution go to the callee entry
// Sets the frame pointer to the new frame's base
// Pushes the return address word
Opcode CALL_NEW = { "call_new", true, [OpArg.LOCAL], /*&gen_call_new*/null , OpInfo.VAR_ARG | OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC };

// <dstLocal> = CALL_APPLY <closArg> <thisArg> <argTable> <numArgs>
// Call with an array of arguments
Opcode CALL_APPLY = { "call_apply", true, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_call_apply*/null , OpInfo.BRANCH | OpInfo.CALL };

// <dstLocal> = CALL_PRIM <primName> <primFun> ...
// Call a primitive function by name
// Note: the second argument is a cached function reference
Opcode CALL_PRIM = { "call_prim", true, [OpArg.STRING, OpArg.FUN], /*&gen_call_prim*/null , OpInfo.VAR_ARG | OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC };

// RET <retLocal>
// Pops the callee frame (size known by context)
Opcode RET = { "ret", false, [OpArg.LOCAL], &gen_ret, OpInfo.BRANCH };

// THROW <excLocal>
// Throws an exception, unwinds the stack
Opcode THROW = { "throw", false, [OpArg.LOCAL], /*&gen_throw*/null , OpInfo.BRANCH };

// Access visible arguments by index
Opcode GET_ARG = { "get_arg", true, [OpArg.LOCAL], /*&gen_get_arg*/null };

// Special implementation object/value access instructions
Opcode GET_OBJ_PROTO = { "get_obj_proto", true, [], /*&gen_get_obj_proto*/null };
Opcode GET_ARR_PROTO = { "get_arr_proto", true, [], /*&gen_get_arr_proto*/null };
Opcode GET_FUN_PROTO = { "get_fun_proto", true, [], /*&gen_get_fun_proto*/null };
Opcode GET_GLOBAL_OBJ = { "get_global_obj", true, [], /*&gen_get_global_obj*/null };
Opcode GET_HEAP_SIZE = { "get_heap_size", true, [], /*&gen_get_heap_size*/null };
Opcode GET_HEAP_FREE = { "get_heap_free", true, [], /*&gen_get_heap_free*/null };
Opcode GET_GC_COUNT = { "get_gc_count", true, [], /*&gen_get_gc_count*/null };

/// Allocate a block of memory on the heap
Opcode HEAP_ALLOC = { "heap_alloc", true, [OpArg.LOCAL], /*&gen_heap_alloc*/null , OpInfo.MAY_GC };

/// Trigger a garbage collection
Opcode GC_COLLECT = { "gc_collect", false, [OpArg.LOCAL], /*&gen_gc_collect*/null , OpInfo.MAY_GC | OpInfo.IMPURE };

/// Create a link table entry associated with this instruction
Opcode MAKE_LINK = { "make_link", true, [OpArg.LINK], /*&gen_make_link*/null };

/// Set the value of a link table entry
Opcode SET_LINK = { "set_link", false, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_set_link*/null , OpInfo.IMPURE };

/// Get the value of a link table entry
Opcode GET_LINK = { "get_link", true, [OpArg.LOCAL], /*&gen_get_link*/null };

/// Create a map object associated with this instruction
Opcode MAKE_MAP = { "make_map", true, [OpArg.MAP, OpArg.LOCAL], /*&gen_make_map*/null };

/// Get the number of properties to allocate for objects with a given map
Opcode MAP_NUM_PROPS = { "map_num_props", true, [OpArg.LOCAL], /*&gen_map_num_props*/null };

/// Get the index for a given property name in a given map
Opcode MAP_PROP_IDX = { "map_prop_idx", true, [OpArg.LOCAL, OpArg.LOCAL, OpArg.LOCAL], /*&gen_map_prop_idx*/null };

/// Get the name for a given property index in a given map
Opcode MAP_PROP_NAME = { "map_prop_name", true, [OpArg.LOCAL, OpArg.LOCAL], /*&gen_map_prop_name*/null , OpInfo.MAY_GC };

/// Compute the hash code for a string and
/// try to find the string in the string table
Opcode GET_STR = { "get_str", true, [OpArg.LOCAL], /*&gen_get_str*/null , OpInfo.MAY_GC };

/// GET_GLOBAL <propName>
/// Note: hidden parameter is a cached global property index
Opcode GET_GLOBAL = { "get_global", true, [OpArg.STRING], &gen_get_global, OpInfo.MAY_GC | OpInfo.IMPURE };

/// SET_GLOBAL <propName> <value>
/// Note: hidden parameter is a cached global property index
Opcode SET_GLOBAL = { "set_global", false, [OpArg.STRING, OpArg.LOCAL], &gen_set_global, OpInfo.MAY_GC | OpInfo.IMPURE };

/// <dstLocal> = NEW_CLOS <funExpr>
/// Create a new closure from a function's AST node
Opcode NEW_CLOS = { "new_clos", true, [OpArg.FUN, OpArg.LINK, OpArg.LINK], /*&gen_new_clos*/null , OpInfo.MAY_GC };

/// Load a source code unit from a file
Opcode LOAD_FILE = { "load_file", true, [OpArg.LOCAL], /*&gen_load_file*/null , OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC | OpInfo.IMPURE };

/// Evaluate a source string in the global scope
Opcode EVAL_STR = { "eval_str", true, [OpArg.LOCAL], /*&gen_eval_str*/null , OpInfo.BRANCH | OpInfo.CALL | OpInfo.MAY_GC | OpInfo.IMPURE };

/// Print a string to standard output
Opcode PRINT_STR = { "print_str", false, [OpArg.LOCAL], /*&gen_print_str*/null , OpInfo.IMPURE };

/// Get a string representation of a function's AST
Opcode GET_AST_STR = { "get_ast_str", true, [OpArg.LOCAL], /*&gen_get_ast_str*/null , OpInfo.MAY_GC };

/// Get a string representation of a function's IR
Opcode GET_IR_STR = { "get_ir_str", true, [OpArg.LOCAL], /*&gen_get_ir_str*/null , OpInfo.MAY_GC };

/// Format a floating-point value as a string
Opcode F64_TO_STR = { "f64_to_str", true, [OpArg.LOCAL], /*&gen_f64_to_str*/null , OpInfo.MAY_GC };

/// Format a floating-point value as a string (long)
Opcode F64_TO_STR_LNG = { "f64_to_str_lng", true, [OpArg.LOCAL], /*&gen_f64_to_str_lng*/null , OpInfo.MAY_GC };

/// Get the time in milliseconds since process start
Opcode GET_TIME_MS = { "get_time_ms", true, [], /*&gen_get_time_ms*/null };

/// Load a shared lib
Opcode LOAD_LIB = { "load_lib", true, [OpArg.LOCAL], /*&gen_load_lib*/null };

/// Close shared lib
Opcode CLOSE_LIB = { "close_lib", false, [OpArg.LOCAL], /*&gen_close_lib*/null , OpInfo.IMPURE };

/// Lookup symbol in shared lib
Opcode GET_SYM = { "get_sym", true, [OpArg.LOCAL, OpArg.STRING], /*&gen_get_sym*/null };

/// Call function in shared lib
Opcode CALL_FFI = { "call_ffi", true, [OpArg.LOCAL, OpArg.STRING], /*&gen_call_ffi*/null , OpInfo.BRANCH | OpInfo.CALL | OpInfo.VAR_ARG };

