/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module jit.jit;

import std.stdio;
import std.string;
import std.array;
import std.stdint;
import ir.ir;
import interp.interp;
import jit.codeblock;
import jit.assembler;
import jit.x86;
import jit.encodings;

/// Trace function pointer
alias void function() TraceFn;

// TODO: IR-level optimization pass on blocks
// - Do this in separate function

// TODO: Optimize the generated machine code with peephole patterns
// - Port existing Tachyon code?

TraceFn compileBlock(Interp interp, IRBlock block)
{
    assert (
        block.firstInstr !is null,
        "first instr of block is null"
    );

    assert (
        block.fun !is null,
        "block fun ptr is null"
    );

    writefln("compiling tracelet in %s:\n%s\n", block.fun.getName(), block.toString());

    // Assembler to write code into
    auto as = new Assembler();

    // Save the GP registers
    as.instr(PUSH, RBX);
    as.instr(PUSH, RBP);
    // r12-r15

    // TODO: increment block exec count


    // Store a pointer to the interpreter in RBX
    as.instr(MOV, RBX, X86Opnd(cast(void*)interp));



    // For each instruction of the block
    for (auto instr = block.firstInstr; instr !is null; instr = instr.next)
    {
        auto opcode = instr.opcode;

        // Get the function corresponding to this instruction
        // alias void function(Interp interp, IRInstr instr) OpFn;
        // RDI: first argument (interp)
        // RSI: second argument (instr)
        auto opFn = opcode.opFn;

        // Move the interpreter pointer into RDI
        as.instr(MOV, RDI, RBX);
        
        // Store a pointer to the instruction in RSI
        as.instr(MOV, RSI, X86Opnd(cast(void*)instr));

        // Call the op function
        as.instr(MOV, RAX, X86Opnd(cast(void*)opFn));
        as.instr(jit.encodings.CALL, RAX);

        // If this instruction is a branch
        if (opcode.isBranch)
        {
            // TODO
            // Need special handling of branch instructions
            // Some we can handle, others not so easy
            //
            // jump_true, jump_false => need to read from the stacks
            // interp pointer register + offset
            //
            // jump or call or ret or throw => stop the block compilation

            // If we know the instruction will leave this block, 
            // stop the block compilation
            if (opcode == &ir.ir.CALL || 
                opcode == &ir.ir.RET  || 
                opcode == &JUMP       ||
                opcode == &THROW)
                break;

            // TODO: For now, other kinds of branches unsupported,
            // compilation fails
            return null;
        }
    }

    // Restore the GP registers
    as.instr(POP, RBP);
    as.instr(POP, RBX);

    // Return to the interpreter
    as.instr(jit.encodings.RET);

    writefln("%s\n", as.toString(true));

    // Assemble the machine code
    auto codeBlock = as.assemble();

    // Return a pointer to the compiled code
    return cast(TraceFn)codeBlock.getAddress();
}

