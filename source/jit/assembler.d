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

import core.sys.posix.unistd;
//import core.sys.posix.sys.mman;
import core.sys.linux.sys.mman;
import core.memory;
import std.stdio;
import std.array;
import std.stdint;
import std.string;
import std.conv;
import std.array;
import std.range;
import std.typecons;
import util.string;
import jit.x86;
import jit.jit;

/**
Low-level machine code block implementation.
Stores generated machine code, external references and exposed labels.
*/
class CodeBlock
{
    /// Memory block size
    private size_t size;

    /// Memory block
    private ubyte* memBlock;

    /// Current writing position
    private size_t writePos;

    /// Disassembly/comment strings
    alias Tuple!(size_t, "pos", string, "str") CommentStr;
    private CommentStr[] strings;

    /// Flag to enable or disable comments
    private bool hasComments;

    this(size_t size, bool hasComments = false)
    {
        assert (
            size > 0,
            "cannot create zero-sized memory block"
        );

        // Map the memory as executable
        this.memBlock = cast(ubyte*)mmap(
            null,
            size,
            PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_PRIVATE | MAP_ANON,
            -1,
            0
        );

        // Check that the memory mapping was successful
        if (this.memBlock == MAP_FAILED)
            throw new Error("mmap call failed");

        //writefln("memBlock: %s", this.memBlock);
        //writefln("pa: %s", pa);

        this.size = size;

        this.writePos = 0;

        this.hasComments = hasComments;
    }

    ~this()
    {
        //writefln("freeing executable memory: %s", this.memBlock);

        auto ret = munmap(this.memBlock, this.size);

        if (ret != 0)
            throw new Error("munmap call failed");
    }

    /**
    Print the code block as a string
    */
    override string toString()
    {
        auto app = appender!string();

        // If there are comment/disassembly strings
        if (strings.length > 0)
        {
            size_t curPos = 0;
            string line = "";

            // For each string
            foreach (strIdx, str; strings)
            {
                // Start a new line for this string
                line = str.str;

                auto nextStrPos = (strIdx < strings.length - 1)? strings[strIdx+1].pos:this.writePos;

                // If the next string is past the current position
                if (nextStrPos > curPos)
                {
                    // Add padding space before the hex printout
                    line = rightPadStr(line, " ", 40);

                    // Print all the bytes until the next string
                    for (; curPos < nextStrPos; ++curPos)
                        line ~= format("%02X", this.memBlock[curPos]);
                }

                // Write the current line
                app.put(line);

                // If we are past the current write position, stop
                if (curPos >= this.writePos)
                    break;

                app.put("\n");
            }
        }
        else
        {
            // Produce a raw dump of the binary data
            for (size_t i = 0; i < this.writePos; ++i)
            {
                auto b = this.memBlock[i];

                if (i != 0)
                    app.put(' ');

                app.put(format("%02X", b));
            }
        }

        return app.data;
    }

    /**
    Get the size of the code block
    */
    auto length()
    {
        return size;
    }

    /**
    Clear the contents of the code block
    */
    void clear()
    {
        this.writePos = 0;
    }

    /**
    Set the current write position
    */
    void setWritePos(size_t pos)
    {
        assert (
            pos < size,
            "invalid code block position"
        );

        writePos = pos;
    }

    /**
    Get the current write position
    */
    size_t getWritePos()
    {
        return writePos;
    }

    /**
    Write a byte at the current position
    */
    void writeByte(ubyte val)
    {
        assert (
            this.memBlock,
            "invalid memory block"
        );

        assert (
            this.writePos + 1 <= this.size,
            "no space to write byte in code block"
        );

        this.memBlock[this.writePos++] = val;
    }

    /**
    Write a sequence of bytes at the current position
    */
    void writeBytes(immutable ubyte bytes[] ...)
    {
        assert (
            this.memBlock,
            "invalid memory block"
        );

        assert (
            this.writePos + bytes.length <= this.size,
            "no space to write bytes in code block"
        );

        foreach (b; bytes)
        {
            this.memBlock[this.writePos++] = b;
        }
    }

    /**
    Write a signed integer at the current position
    */
    void writeInt(uint64_t val, size_t numBits)
    {
        assert (
            numBits > 0 && numBits % 8 == 0,
            "the number of bits must be a positive multiple of 8"
        );

        // Compute the size in bytes
        auto numBytes = numBits / 8;

        // Write out the bytes
        for (size_t i = 0; i < numBytes; ++i)
        {
            auto byteVal = cast(ubyte)(val & 0xFF);

            this.writeByte(byteVal);

            val >>= 8;
        }
    }

    /**
    Write a disassembly/comment string at the current position
    */
    void writeStr(string str)
    {
        auto newStr = CommentStr(writePos, str);

        if (strings.length is 0 || strings[$-1].pos <= writePos)
        {
            strings ~= newStr;
        }
        else
        {
            // Replace other strings of equal position by the new string
            auto r = assumeSorted!"a.pos < b.pos"(strings).trisect(newStr);
            //auto newRange = assumeSorted!"a.pos < b.pos"([newStr]);
            strings = r[0].release() ~ newStr ~ r[2].release();
        }
    }

    /**
    Write a comment string. Does nothing if ASM dump is not enabled.
    */
    void writeComment(string str)
    {
        if (!hasComments)
            return;

        return writeStr(str);
    }

    /**
    Write a formatted disassembly string
    */
    void writeASM(T...)(string mnem, T args)
    {
        if (!hasComments)
            return;

        auto str = mnem;

        foreach (argIdx, arg; args)
        {
            str ~= (argIdx > 0)? ", ":" ";
            str ~= to!string(arg);
        }

        str ~= ";";

        return writeStr(str);
    }

    /**
    Write the contents of another code block at the given position
    */
    void writeBlock(CodeBlock cb)
    {
        assert (
            this.writePos + cb.size <= this.size,
            "cannot write code block, size too large"
        );

        // If the other block has comment strings
        if (cb.strings.length > 0)
        {
            // Get the strings that come before and after the other block's
            auto range = assumeSorted!"a.pos < b.pos"(strings);
            auto lower = range.lowerBound(cb.strings.front);
            auto upper = range.lowerBound(cb.strings.back);

            // Insert the block's strings in between
            strings = lower.release() ~ cb.strings ~ upper.release();
        }

        // Copy the bytes from the other code block
        this.memBlock[this.writePos..this.writePos+cb.size] = cb.memBlock[0..cb.size];
        this.writePos += cb.size;   
    }

    /**
    Read the byte at the given index
    */
    ubyte readByte(size_t index)
    {
        assert (
            index < size
        );

        return memBlock[index];
    }
}

/**
Block internal label enumeration
*/
enum Label : size_t
{
    LOOP,
    DONE
}

/**
Code block with address linking capabilities
*/
class ASMBlock : CodeBlock
{
    // Table of label addresses
    private size_t[Label.max+1] labelAddrs;

    // Label reference list
    alias Tuple!(size_t, "pos", Label, "label") LabelRef;
    private LabelRef labelRefs[];

    this(size_t size, bool hasComments = false)
    {
        super(size, hasComments);
        clear();
    }

    /**
    Clear the contents of the code block
    */
    override void clear()
    {
        super.clear();

        for (auto label = Label.min; label < Label.max; ++label)
            labelAddrs[label] = size_t.max;

        labelRefs = [];
    }

    /**
    Add a label reference at the current write position
    */
    void addLabelRef(Label label)
    {
        // TODO debug {} block? Check for duplicates at same pos

        labelRefs ~= LabelRef(writePos, label);
    }

    /**
    Link internal label references
    */
    void link()
    {
        auto origPos = writePos;

        // For each label reference
        foreach (labelRef; labelRefs)
        {
            assert (labelRef.pos < length);
            auto labelAddr = labelAddrs[labelRef.label];
            assert (labelAddr < length);

            setWritePos(labelRef.pos);
            writeInt(labelAddr, 32);
        }

        writePos = origPos;
    }
}

/**
Micro-assembler for code generation
*/
class Assembler
{
    /// Inner instruction code
    CodeBlock code;

    /// Edge transition move code for each target
    CodeBlock branchCode[BlockVersion.MAX_TARGETS];

    // TODO: final branch descriptors

    // Target block versions
    private BlockVersion targets[BlockVersion.MAX_TARGETS];

    this()
    {
        clear();
    }

    /**
    Clear the contents of the assembler
    */
    void clear()
    {
        code.clear();

        foreach (code; branchCode)
            code.clear();

        // TODO: clear branch descriptors

        for (size_t tIdx = 0; tIdx < targets.length; ++tIdx)
            targets[tIdx] = null;
    }

    // TODO: method to copy into a code block and finalize into a BlockVersion
    // Must store offsets + length, etc
    // Must write to code block
}

