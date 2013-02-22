/* _________________________________________________________________________
 *
 *             Tachyon : A Self-Hosted JavaScript Virtual Machine
 *
 *
 *  This file is part of the Tachyon JavaScript project. Tachyon is
 *  distributed at:
 *  http://github.com/Tachyon-Team/Tachyon
 *
 *
 *  Copyright (c) 2011, Universite de Montreal
 *  All rights reserved.
 *
 *  This software is licensed under the following license (Modified BSD
 *  License):
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are
 *  met:
 *    * Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the Universite de Montreal nor the names of its
 *      contributors may be used to endorse or promote products derived
 *      from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 *  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 *  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 *  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL UNIVERSITE DE
 *  MONTREAL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * _________________________________________________________________________
 */

/**
@fileOverview
x86 assembler class implementation.

@author
Maxime Chevalier-Boisvert
*/

/**
x86 namespace
*/
var x86 = x86 || {};

/**
@class Assembler to assemble a function or block of assembler code.
*/
x86.Assembler = function (x86_64)
{
    assert (
        x86_64 === true || x86_64 === false,
        'must set assembler x86-64 flag'
    );

    /**
    @field x86-64 mode
    */
    this.x86_64 = x86_64;

    /**
    @field First instruction in the block
    */
    this.firstInstr = null;

    /**
    @field Last instruction in the block
    */
    this.lastInstr = null;

    /**
    @field Number of instructions
    */
    this.numInstrs = 0;
}

/**
Produce a string representation of the code block being assembled
*/
x86.Assembler.prototype.toString = function (printEnc)
{
    var str = '';

    // Assemble the code to get the final jump values
    this.assemble();

    // Code block to assemble individual instructions into
    var codeBlock = new CodeBlock(256);

    // For each instruction
    for (var instr = this.firstInstr; instr !== null; instr = instr.next)
    {
        if (str != '')
            str += '\n';

        var line = instr.toString();

        if (printEnc)
        {
            line = rightPadStr(line, ' ', 40);            

            codeBlock.clear();
            instr.encode(codeBlock, this.x86_64);

            line += codeBlock.toString();
        }

        str += line;
    }

    return str;
}

/**
Get the first instruction in the list
*/
x86.Assembler.prototype.getFirstInstr = function ()
{
    return this.firstInstr;
}

/**
Add an instruction at the end of the block
*/
x86.Assembler.prototype.addInstr = function (instr)
{
    assert (
        instr instanceof x86.Instruction,
        'invalid instruction'
    );

    if (this.lastInstr === null)
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
}

/**
Add an instruction after another instruction
*/
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

/**
Remove an instruction from the list
*/
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

/**
Replace an instruction
*/
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

/**
Assemble a code block from the instruction list
@returns a code block object
*/
x86.Assembler.prototype.assemble = function (codeOnly)
{
    //print('assembling machine code');

    // Total code length
    var codeLength;

    // Flag to indicate an encoding changed
    var changed = true;

    // Until no encodings changed
    while (changed === true)
    {
        //print('iterating');

        // Reset the code length
        codeLength = 0;

        // No changes for this iteration yet
        changed = false;

        // For each instruction
        for (var instr = this.firstInstr; instr !== null; instr = instr.next)
        {
            if (DEBUG === true && (instr instanceof x86.Instruction) === false)
                error('invalid instruction: ' + instr);

            // If this instruction is a label
            if (instr instanceof x86.Label)
            {
                // If the position of the label did not change, do nothing
                if (instr.offset === codeLength)
                    continue;

                //print('label position changed for ' + instr + ' (' + codeLength + ')');

                // Note that the offset changed
                changed = true;

                // Store the offset where the label currently is
                instr.offset = codeLength;
            }
            else
            {
                // Get the current instruction length
                var curInstrLen = instr.getLength(this.x86_64);

                // Add the current instruction length to the total
                codeLength += curInstrLen;

                // For each operand of the instruction
                for (var i = 0; i < instr.opnds.length; ++i)
                {
                    var opnd = instr.opnds[i];

                    // If this is a label reference
                    if (opnd instanceof x86.LabelRef)
                    {
                        // Get a reference to the label
                        var label = opnd.label;

                        // Compute the relative offset to the label
                        var relOffset = label.offset - codeLength;

                        // Store the computed relative offset on the operand
                        opnd.relOffset = relOffset;

                        // Compute the updated relative offset size
                        var offSize;
                        if (num_ge(relOffset, getIntMin(8)) && num_le(relOffset, getIntMax(8)))
                            offSize = 8;
                        else if (num_ge(relOffset, getIntMin(16)) && num_le(relOffset, getIntMax(16)))
                            offSize = 16;
                        else if (num_ge(relOffset, getIntMin(32)) && num_le(relOffset, getIntMax(32)))
                            offSize = 32;
                        else
                            error('relative offset does not fit within 32 bits');

                        // If the offset size did not change, do nothing
                        if (offSize === opnd.size)
                            continue;

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

                        /*
                        print('offset size changed for ' + instr);
                        instr.findEncoding(this.x86_64);
                        print('instr length: ' + instr.getLength());
                        */

                        // Find an encoding for this instruction
                        instr.findEncoding(this.x86_64);

                        // Get the updated instruction length
                        var newInstrLen = instr.getLength();
               
                        // Correct the total code length
                        codeLength -= curInstrLen;
                        codeLength += newInstrLen;

                        // Note that the offset changed
                        changed = true;                        
                    }
                }
            }
        }
    }

    // If we are doing a raw assembly (code only)
    if (codeOnly === true)
    {
        // Allocate a new code block for the code onlu
        var codeBlock = new CodeBlock(codeLength);

        // Encode the instructions into the code block
        for (var instr = this.firstInstr; instr !== null; instr = instr.next)
            instr.encode(codeBlock, this.x86_64);
    }
    else
    {
        // Count the number of imported references
        var numLinks = 0;
        for (var instr = this.firstInstr; instr !== null; instr = instr.next)
        {
            for (var i = 0; i < instr.opnds.length; ++i)
            {
                var opnd = instr.opnds[i];

                if (opnd instanceof x86.LinkValue)
                    numLinks++;
            }
        }

        // Compute the total code block size
        var totalSize = CodeBlock.HEADER_SIZE + codeLength + numLinks * CodeBlock.REF_ENTRY_SIZE;

        // Allocate a new code block for the code and metadata
        var codeBlock = new CodeBlock(totalSize);

        // Write the code block header:
        // - Last collection number (32-bit)
        // - Ref encoding offset (32-bit)
        // - Num ref entries (32-bit)
        codeBlock.writeInt(0, 32);
        codeBlock.writeInt(CodeBlock.HEADER_SIZE + codeLength, 32);
        codeBlock.writeInt(numLinks, 32);

        // Encode the instructions into the code block
        for (var instr = this.firstInstr; instr !== null; instr = instr.next)
            instr.encode(codeBlock, this.x86_64);

        // For each value linked in the code block
        for (var i = 0; i < codeBlock.imports.length; ++i)
        {
            var ref = codeBlock.imports[i];

            // Write the linked value position
            codeBlock.writeInt(ref.pos, 32);

            var val = ref.value;

            // Encode the value kind
            var kind = 0;
            if (val instanceof IRFunction)
                kind = 1;
            else if (val.type === IRType.ref)
                kind = 2;
            else if (val.type === IRType.box)
                kind = 3;

            // Write the linked value info
            codeBlock.writeInt(kind, 32);
        }
    }

    // Return the code block we assembled into
    return codeBlock;
};

/**
Anonymous function to initialize the assembler class
*/
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

    // Create method to create labels on the assembler
    x86.Assembler.prototype.label = function (name)
    {
        var label = new x86.Label(name);

        this.addInstr(label);

        return label;
    }

    // Create an assembler field for each register
    for (var reg in x86.regs)
        x86.Assembler.prototype[reg] = x86.regs[reg];

    // Create a method to encode memory locations on the assembler
    x86.Assembler.prototype.mem = function (size, base, disp, index, scale)
    {
        return new x86.MemLoc(size, base, disp, index, scale);
    }

})();

