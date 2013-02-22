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

module jit.codeblock;

import std.stdio;
import std.stdint;

class JITInstr
{
    abstract size_t length();

    abstract void encode();

    abstract override string toString();

    JITInstr prev;
    JITInstr next;
}

/**
Label inserted into an instruction stream
*/
class Label : JITInstr
{
    this(string name, bool exported)
    {
        this.name = name;
        this.exported = exported;
    }

    /**
    Get the string representation of a label
    */
    override string toString()
    {
        return this.name ~ (this.exported? " (exported)":"") ~ ":";
    }

    /**
    Find an encoding for a label, does nothing
    */
    /*
    void findEncoding()
    {
    }
    */

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
    override void encode(/*codeBlock*/)
    {
        // TODO

        // If this label is to be exported
        if (this.exported == true)
        {
            // Add the export to the code block
            //codeBlock.exportLabel(this.name);
        }
    }

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
}

/**
@class Low-level machine code block implementation.
Stores generated machine code, external references and exposed labels.
*/
/*
function CodeBlock(size)
{
    assert (
        isPosInt(size),
        'invalid code block size: ' + size
    );

    /// Executable memory block
    this.memBlock = allocMemoryBlock(size, true);

    /// Memory block size
    this.size = size;

    /// Current writing position
    this.writePos = 0;

    /// Exported labels in this block
    this.exports = {};
}
*/

/**
Print the code block as a string
*/
/*
CodeBlock.prototype.toString = function ()
{
    var str = '';

    for (var i = 0; i < this.writePos; ++i)
    {
        var byteVal = this.readByte(i);

        var byteStr = byteVal.toString(16);
        byteStr = byteStr.toUpperCase();
        if (byteStr.length === 1)
            byteStr = '0' + byteStr;

        if (i !== 0)
            str += ' ';

        str += byteStr;
    }

    return str;
}
*/

/**
Get the address of an offset in the code block
*/
/*
CodeBlock.prototype.getAddress = function (idx)
{
    if (idx === undefined)
        idx = 0;

    return getBlockAddr(this.memBlock, idx);
}
*/

/**
Get the address of an exported label in the code block
*/
/*
CodeBlock.prototype.getExportAddr = function (name)
{
    assert (
        this.exports[name] !== undefined,
        'invalid exported label'
    );

    return getBlockAddr(this.memBlock, this.exports[name]);
}
*/

/**
Clear the contents of the code block
*/
/*
CodeBlock.prototype.clear = function ()
{
    this.writePos = 0;
}
*/

/**
Set the current write position
*/
/*
CodeBlock.prototype.setWritePos = function (pos)
{
    assert (
        pos < this.size,
        'invalid code block position'
    );

    this.writePos = pos;
}
*/

/**
Write a byte at the current position
*/
/*
CodeBlock.prototype.writeByte = function (val)
{
    assert (
        this.memBlock,
        'invalid memory block'
    );

    assert (
        this.writePos + 1 <= this.size,
        'no space to write byte in code block ' +
        '(pos ' + this.writePos + '/' + this.size + ')'
    );

    assert (
        isNonNegInt(val) && val <= 255,
        'invalid byte value: ' + val
    );

    writeToMemoryBlock(this.memBlock, this.writePos, val);

    this.writePos += 1;
}
*/

/**
Write a sequence of bytes at the current position
*/
/*
CodeBlock.prototype.writeBytes = function (bytes)
{
    for (var i = 0; i < bytes.length; ++i)
        this.writeByte(bytes[i]);
}
*/

/**
Write a signed integer at the current position
*/
/*
CodeBlock.prototype.writeInt = function (val, numBits)
{
    assert (
        isPosInt(numBits) && numBits % 8 === 0,
        'the number of bits must be a positive multiple of 8'
    );

    assert (
        num_ge(val, getIntMin(numBits)) &&
        num_le(val, getIntMax(numBits, true)),
        'integer value does not fit within ' + numBits + ' bits: ' + val
    );

    // Compute the size in bytes
    var numBytes = numBits / 8;

    // Write out the bytes
    for (var i = 0; i < numBytes; ++i)
    {
        //print(num_to_string(val));

        var byteVal = num_and(val, 0xFF);

        this.writeByte(byteVal);

        val = num_shift(val, -8);
    }
}
*/

/**
Write a link value at the current position
*/
/*
CodeBlock.prototype.writeLink = function (linkVal, numBits)
{
    assert (
        numBits === 32 || numBits === 64,
        'invalid link value size'
    );

    // Store the link value and its position
    this.imports.push(
        {
            value: linkVal,
            pos: this.writePos
        }
    );

    // Compute the size in bytes
    var numBytes = numBits / 8;

    // Write placeholder bytes for the value
    for (var i = 0; i < numBytes; ++i)
        this.writeByte(0);
}
*/

/**
Add an exported label at the the current position
*/
/*
CodeBlock.prototype.exportLabel = function (name)
{
    assert (
        this.exports.hasOwnProperty(name) === false,
        'exported label already exists: "' + name + '"'
    );

    // Store the link value and its position
    this.exports[name] = this.writePos
}
*/

