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

module ir.iir;

import std.stdio;
import std.string;
import std.conv;
import ir.ops;

/**
Inline IR prefix string
*/
immutable string IIR_PREFIX = "$ir_";

/**
Table of inlinable IR instructions (usable in library code)
*/
Opcode*[string] iir;

/// Initialize the inline IR table
static this()
{
    void addOp(ref Opcode op, string opName = null)
    { 
        if (opName is null)
            opName = op.mnem;

        assert (
            opName !in iir, 
            "duplicate op name " ~ opName
        );

        iir[opName] = &op; 
    }

    addOp(MAKE_VALUE);
    addOp(GET_WORD);
    addOp(GET_TYPE);

    addOp(IS_I32);
    addOp(IS_F64);
    addOp(IS_CONST);
    addOp(IS_RAWPTR);
    addOp(IS_REFPTR);
    addOp(IS_OBJECT);
    addOp(IS_ARRAY);
    addOp(IS_CLOSURE);
    addOp(IS_STRING);

    addOp(I32_TO_F64);
    addOp(F64_TO_I32);

    addOp(ADD_I32);
    addOp(SUB_I32);
    addOp(MUL_I32);
    addOp(DIV_I32);
    addOp(MOD_I32);

    addOp(ADD_I32_OVF);
    addOp(SUB_I32_OVF);
    addOp(MUL_I32_OVF);

    addOp(ADD_PTR_I32);

    addOp(AND_I32);
    addOp(OR_I32);
    addOp(XOR_I32);
    addOp(LSFT_I32);
    addOp(RSFT_I32);
    addOp(URSFT_I32);
    addOp(NOT_I32);

    addOp(ADD_F64);
    addOp(SUB_F64);
    addOp(MUL_F64);
    addOp(DIV_F64);
    addOp(MOD_F64);

    addOp(COS_F64);
    addOp(SIN_F64);
    addOp(SQRT_F64);
    addOp(CEIL_F64);
    addOp(FLOOR_F64);
    addOp(LOG_F64);
    addOp(EXP_F64);
    addOp(POW_F64);

    addOp(EQ_I8);
    addOp(EQ_I32);
    addOp(NE_I32);
    addOp(LT_I32);
    addOp(GT_I32);
    addOp(LE_I32);
    addOp(GE_I32);
    addOp(EQ_I64);

    addOp(EQ_REFPTR);
    addOp(NE_REFPTR);

    addOp(EQ_RAWPTR);
    addOp(NE_RAWPTR);

    addOp(EQ_CONST);
    addOp(NE_CONST);

    addOp(EQ_F64);
    addOp(NE_F64);
    addOp(LT_F64);
    addOp(GT_F64);
    addOp(LE_F64);
    addOp(GE_F64);

    addOp(LOAD_U8);
    addOp(LOAD_U16);
    addOp(LOAD_U32);
    addOp(LOAD_U64);
    addOp(LOAD_I8);
    addOp(LOAD_I16);
    addOp(LOAD_I32);
    addOp(LOAD_F64);
    addOp(LOAD_REFPTR);
    addOp(LOAD_RAWPTR);
    addOp(LOAD_FUNPTR);
    addOp(LOAD_MAPPTR);

    addOp(STORE_U8);
    addOp(STORE_U16);
    addOp(STORE_U32);
    addOp(STORE_I8);
    addOp(STORE_I16);
    addOp(STORE_I32);
    addOp(STORE_U64);
    addOp(STORE_F64);
    addOp(STORE_REFPTR);
    addOp(STORE_RAWPTR);
    addOp(STORE_FUNPTR);
    addOp(STORE_MAPPTR);

    addOp(THROW);
    addOp(CALL_APPLY);

    addOp(GET_ARG);

    addOp(GET_OBJ_PROTO);
    addOp(GET_ARR_PROTO);
    addOp(GET_FUN_PROTO);
    addOp(GET_GLOBAL_OBJ);
    addOp(GET_HEAP_SIZE);
    addOp(GET_HEAP_FREE);
    addOp(GET_GC_COUNT);

    addOp(ALLOC_REFPTR);
    addOp(ALLOC_OBJECT);
    addOp(ALLOC_ARRAY);
    addOp(ALLOC_CLOSURE);
    addOp(ALLOC_STRING);

    addOp(GC_COLLECT);
    addOp(MAKE_LINK);
    addOp(SET_LINK);
    addOp(GET_LINK);
    addOp(MAKE_MAP);
    addOp(MAP_NUM_PROPS);
    addOp(MAP_PROP_IDX);
    addOp(MAP_PROP_NAME);
    addOp(GET_STR);

    addOp(LOAD_FILE);
    addOp(EVAL_STR);
    addOp(PRINT_STR);
    addOp(GET_AST_STR);
    addOp(GET_IR_STR);
    addOp(GET_ASM_STR);
    addOp(F64_TO_STR);
    addOp(F64_TO_STR_LNG);
    addOp(GET_TIME_MS);
    addOp(LOAD_LIB);
    addOp(CLOSE_LIB);
    addOp(GET_SYM);
    addOp(CALL_FFI);
}

