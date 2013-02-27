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

module jit.assembler;

import std.stdio;
import std.array;
import std.stdint;
import util.string;
import jit.codeblock;
import jit.x86;

/**
Assembler to assemble a function or block of assembler code.
*/
class Assembler
{
    /// First instruction in the block
    private JITInstr firstInstr = null;

    /// Last instruction in the block
    private JITInstr lastInstr = null;

    this ()
    {
    }

    override string toString()
    {
        return toString(true);
    }

    /**
    Produce a string representation of the code block being assembled
    */
    string toString(bool printBytes)
    {
        auto app = appender!string();

        // Assemble the code to get the final jump values
        this.assemble();

        // Code block to assemble individual instructions into
        auto codeBlock = new CodeBlock(256);

        // For each instruction
        for (auto instr = this.firstInstr; instr !is null; instr = instr.next)
        {
            if (instr != this.firstInstr)
                app.put('\n');

            auto line = instr.toString();

            if (printBytes)
            {
                line = rightPadStr(line, " ", 40);            

                codeBlock.clear();
                instr.encode(codeBlock);

                line ~= codeBlock.toString();
            }

            app.put(line);
        }

        return app.data;
    }

    /**
    Get the first instruction in the list
    */
    JITInstr getFirstInstr()
    {
        return this.firstInstr;
    }

    /**
    Add an instruction at the end of the block
    */
    JITInstr addInstr(JITInstr instr)
    {
        if (this.lastInstr is null)
        {
            this.firstInstr = instr;
            this.lastInstr = instr;

            instr.prev = null;
            instr.next = null;
        }
        else
        {
            this.lastInstr.next = instr;

            instr.prev = this.lastInstr;
            instr.next = null;

            this.lastInstr = instr;
        }

        return instr;
    }

    /**
    Add an instruction after another instruction
    */
    /*
    x86.Assembler.prototype.addInstrAfter = function (instr, prev)
    {
        assert (
            instr instanceof x86.Instruction,
            'invalid instruction'
        );

        assert (
            prev instanceof x86.Instruction,
            'invalid previous instruction'
        );

        var next = prev.next;

        instr.prev = prev;
        instr.next = next;

        prev.next = instr;

        if (next !== null)
            next.prev = instr;
        else
            this.lastInstr = instr;
    }
    */

    /**
    Remove an instruction from the list
    */
    /*
    x86.Assembler.prototype.remInstr = function (instr)
    {
        assert (
            instr instanceof x86.Instruction,
            'invalid instruction'
        );

        var prev = instr.prev;
        var next = instr.next;

        if (prev !== null)
            prev.next = next;
        else
            this.firstInstr = next;

        if (next !== null)
            next.prev = prev;
        else
            this.lastInstr = prev;
    }
    */

    /**
    Replace an instruction
    */
    /*
    x86.Assembler.prototype.replInstr = function (oldInstr, newInstr)
    {
        assert (
            oldInstr instanceof x86.Instruction,
            'invalid old instruction'
        );

        assert (
            newInstr instanceof x86.Instruction,
            'invalid new instruction'
        );

        var prev = oldInstr.prev;
        var next = oldInstr.next;

        if (prev !== null)
            prev.next = newInstr;
        else
            this.firstInstr = newInstr;

        if (next !== null)
            next.prev = newInstr;
        else
            this.lastInstr = newInstr;

        newInstr.prev = prev;
        newInstr.next = next;
    }
    */

    /**
    Assemble a code block from the instruction list
    @returns a code block object
    */
    CodeBlock assemble()
    {
        // Total code length
        size_t codeLength;

        // Flag to indicate an encoding changed
        bool changed = true;

        // Until no encodings changed
        while (changed == true)
        {
            //print('iterating');

            // Reset the code length
            codeLength = 0;

            // No changes for this iteration yet
            changed = false;

            // For each instruction
            for (auto instr = this.firstInstr; instr !is null; instr = instr.next)
            {
                // If this instruction is a label
                if (auto label = cast(Label)instr)
                {
                    // If the position of the label did not change, do nothing
                    if (label.offset == codeLength)
                        continue;

                    //print('label position changed for ' + instr + ' (' + codeLength + ')');

                    // Note that the offset changed
                    changed = true;

                    // Store the offset where the label currently is
                    label.offset = cast(uint32_t)codeLength;
                }

                // If this is a machine instruction
                if (auto x86Instr = cast(X86Instr)instr)
                {
                    // Get the current instruction length
                    auto curInstrLen = instr.length();

                    // Add the current instruction length to the total
                    codeLength += curInstrLen;

                    // For each operand of the instruction
                    for (size_t i = 0; i < x86Instr.opnds.length; ++i)
                    {
                        auto opnd = &x86Instr.opnds[i];

                        // If this is a label reference
                        if (opnd.type == X86Opnd.REL)
                        {
                            // Get a reference to the label
                            auto label = opnd.label;

                            // Compute the relative offset to the label
                            auto relOffset = label.offset - codeLength;

                            // Get the previous offset size
                            auto prevOffSize = opnd.immSize();

                            // Store the computed relative offset on the operand
                            opnd.imm = relOffset;

                            // Compute the updated relative offset size
                            auto offSize = opnd.immSize();

                            // If the offset size did not change, do nothing
                            if (offSize == prevOffSize)
                                continue;

                            /*
                            // If the offset size is fixed, do not change it
                            if (opnd.fixedSize === true)
                            {
                                assert (
                                    offSize < opnd.size,
                                    'fixed size specified is insufficient'
                                );

                                continue;
                            }

                            // Update the offset size
                            opnd.size = offSize;
                            */

                            // Find an encoding for this instruction
                            x86Instr.findEncoding();

                            // Get the updated instruction length
                            auto newInstrLen = instr.length();
                   
                            // Correct the total code length
                            codeLength -= curInstrLen;
                            codeLength += newInstrLen;

                            // Note that the offset changed
                            changed = true;

                        } // if (label)
                    } // foreach(opnd)
                }
            } // foreach (instr)
        } // while (changed)

        // Allocate a new code block for the code onlu
        auto codeBlock = new CodeBlock(codeLength);

        // Encode the instructions into the code block
        for (auto instr = this.firstInstr; instr !is null; instr = instr.next)
            instr.encode(codeBlock);

        // Return the code block we assembled into
        return codeBlock;
    }

    X86Instr instr(X86OpPtr opcode)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode));
    }

    // Unary instruction helper methods
    X86Instr instr(X86OpPtr opcode, X86Opnd a)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, a));
    }
    X86Instr instr(X86OpPtr opcode, X86RegPtr a)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, X86Opnd(a)));
    }
    X86Instr instr(X86OpPtr opcode, int64_t imm)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, X86Opnd(imm)));
    }
    X86Instr instr(X86OpPtr opcode, Label a)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, X86Opnd(a)));
    }

    // Binary instruction helper methods
    X86Instr instr(X86OpPtr opcode, X86Opnd a, X86Opnd b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, a, b));
    }
    X86Instr instr(X86OpPtr opcode, X86RegPtr a, X86RegPtr b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, X86Opnd(a), X86Opnd(b)));
    }
    X86Instr instr(X86OpPtr opcode, X86RegPtr a, int64_t b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, X86Opnd(a), X86Opnd(b)));
    }
    X86Instr instr(X86OpPtr opcode, X86RegPtr a, X86Opnd b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, X86Opnd(a), b));
    }
    X86Instr instr(X86OpPtr opcode, X86Opnd a, X86RegPtr b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, a, X86Opnd(b)));
    }
    X86Instr instr(X86OpPtr opcode, X86Opnd a, int64_t b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, a, X86Opnd(b)));
    }

    // Trinary instruction helper methods
    X86Instr instr(X86OpPtr opcode, X86RegPtr a, X86RegPtr b, int64_t imm)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, X86Opnd(a), X86Opnd(b), X86Opnd(imm)));
    }

    Label label(string name)
    {
        auto label = new Label(name);
        this.addInstr(label);
        return label;
    }
}

/*
(function ()
{
    // Create an assembler method for this instruction
    function makeInstrMethod(mnem)
    {
        x86.Assembler.prototype[mnem] = function ()
        {
            var opnds = [];

            for (var i = 0; i < arguments.length; ++i)
            {
                var opnd = arguments[i];

                if (!(opnd instanceof x86.Operand))
                {
                    if (opnd instanceof x86.Label)
                        opnd = new x86.LabelRef(opnd);
                    else if (num_instance(opnd) === true)
                        opnd = new x86.Immediate(opnd);
                    else
                        error('invalid operand: ' + opnd);
                }

                if (DEBUG === true && !(opnd instanceof x86.Operand))
                    error('invalid operand argument: ' + opnd);

                opnds.push(opnd);
            }

            var instr = new x86.instrs[mnem](opnds, this.x86_64);

            this.addInstr(instr);
        };
    }

    // Create an assembler method for each instruction
    for (var instr in x86.instrs)
        makeInstrMethod(instr);

})();
*/

