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
import std.string;
import util.string;
import jit.codeblock;
import jit.x86;

/**
JIT compiler instruction
*/
class JITInstr
{
    JITInstr prev;
    JITInstr next;

    abstract override string toString();

    abstract size_t length();

    abstract void encode(CodeBlock codeBlock);
}

/**
Label inserted into an instruction stream
*/
class Label : JITInstr
{
    /**
    Label name
    */
    string name;

    /**
    Offset at which this label is located
    */
    uint32_t offset = 0;

    /**
    Reference count for this label
    */
    uint32_t refCount = 0;

    /**
    Flag to indicate this label will be externally visible
    and usable for linking.
    */
    bool exported;

    this(string name, bool exported = false)
    {
        this.name = name;
        this.exported = exported;
    }

    /**
    Get the string representation of a label
    */
    override string toString()
    {
        return xformat("%s(%s)%s:", this.name, this.offset, (this.exported? " (exported)":""));
    }

    /**
    Get the length of a label, always 0
    */
    override size_t length()
    {
        return 0;
    }

    /**
    Encode a label into a code block
    */
    override void encode(CodeBlock codeBlock)
    {
        // If this label is to be exported
        if (this.exported == true)
        {
            // Add the export to the code block
            codeBlock.exportLabel(this.name);
        }
    }
}

/**
Integer data inserted into an instruction stream
*/
class IntData : JITInstr
{
    uint64_t value;

    size_t numBits;

    this(uint64_t value, size_t numBits)
    {
        assert (numBits % 8 == 0 && numBits > 0);

        this.value = value;
        this.numBits = numBits;
    }

    override string toString()
    {
        return xformat("%s (%s)", value, numBits);
    }

    override size_t length()
    {
        return numBits / 8;
    }

    override void encode(CodeBlock codeBlock)
    {
        codeBlock.writeInt(value, numBits);
    }
}

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
        assert (
            instr.prev is null && instr.next is null,
            "instr is already part of a list"
        );

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
    void addInstrAfter(JITInstr instr, JITInstr prev)
    {
        auto next = prev.next;

        instr.prev = prev;
        instr.next = next;

        prev.next = instr;

        if (next !is null)
            next.prev = instr;
        else
            this.lastInstr = instr;
    }

    /**
    Remove an instruction from the list
    */
    void remInstr(JITInstr instr)
    {
        auto prev = instr.prev;
        auto next = instr.next;

        if (prev !is null)
            prev.next = next;
        else
            this.firstInstr = next;

        if (next !is null)
            next.prev = prev;
        else
            this.lastInstr = prev;
    }

    /**
    Replace an instruction
    */
    void replInstr(JITInstr oldInstr, JITInstr newInstr)
    {
        auto prev = oldInstr.prev;
        auto next = oldInstr.next;

        if (prev !is null)
            prev.next = newInstr;
        else
            this.firstInstr = newInstr;

        if (next !is null)
            next.prev = newInstr;
        else
            this.lastInstr = newInstr;

        newInstr.prev = prev;
        newInstr.next = next;
    }

    /**
    Append the instructions from another assembler
    Note: this removes instructions from the other assembler
    */
    void append(Assembler that)
    {
        if (!this.lastInstr)
        {
            this.firstInstr = that.firstInstr;
            this.lastInstr = that.lastInstr;
        }
        else if (that.lastInstr)
        {

            that.firstInstr.prev = this.lastInstr;
            this.lastInstr.next = that.firstInstr;            
            this.lastInstr = that.lastInstr;
        }

        that.firstInstr = null;
        that.lastInstr = null;
    }

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
                    assert (
                        x86Instr.valid(),
                        "cannot assemble invalid instruction:\n" ~ instr.toString()
                    );

                    // Get the current instruction length
                    auto curInstrLen = instr.length();

                    // Add the current instruction length to the total
                    codeLength += curInstrLen;

                    // For each operand of the instruction
                    foreach (i, opnd; x86Instr.opnds)
                    {
                        if (opnd is null)
                            break;

                        auto rel = cast(X86LabelRef)opnd;
                        auto ipr = cast(X86IPRel)opnd;

                        // If this is a label reference or an 
                        // ip-relative memory location
                        if (rel !is null || ipr !is null)
                        {
                            // Get a reference to the label
                            auto label = rel? rel.label:ipr.label;

                            // Compute the relative offset to the label
                            auto relOffset = label.offset - codeLength;

                            // Get the previous offset size
                            auto prevOffSize = rel? rel.immSize():ipr.dispSize();

                            // Store the computed relative offset on the operand
                            if (rel)
                                rel.imm = relOffset;
                            else
                                ipr.disp = cast(int32_t)(relOffset + ipr.labelDisp);

                            // Compute the updated relative offset size
                            auto offSize = rel? rel.immSize():ipr.dispSize();

                            // If the offset size did not change, do nothing
                            if (offSize == prevOffSize)
                                continue;

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
                } // if (X86Instr)

                // If this is integer data
                if (auto intData = cast(IntData)instr)
                {
                    // Add its length to the total
                    codeLength += instr.length();
                }

            } // foreach (instr)
        } // while (changed)

        // Allocate a new code block for the code
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
    X86Instr instr(X86OpPtr opcode, int64_t imm)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, new X86Imm(imm)));
    }
    X86Instr instr(X86OpPtr opcode, Label a)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, new X86LabelRef(a)));
    }

    // Binary instruction helper methods
    X86Instr instr(X86OpPtr opcode, X86Opnd a, X86Opnd b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, a, b));
    }
    X86Instr instr(X86OpPtr opcode, X86Opnd a, int64_t b)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, a, new X86Imm(b)));
    }

    // Trinary instruction helper methods
    X86Instr instr(X86OpPtr opcode, X86Opnd a, X86Opnd b, int64_t imm)
    {
        return cast(X86Instr)addInstr(new X86Instr(opcode, a, b, new X86Imm(imm)));
    }

    /// Create and insert a label
    Label label(string name)
    {
        auto label = new Label(name);
        this.addInstr(label);
        return label;
    }
}

