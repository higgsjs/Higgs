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
import std.algorithm;
import util.string;
import jit.x86;
import jit.jit;
import options;

/**
Block internal label enumeration
*/
enum Label : size_t
{
    LOOP,
    DONE,
    TRUE,
    FALSE,
    FUN1,
    FUN2,
    BRANCH_TARGET0,
    BRANCH_TARGET1
}

/**
Low-level machine code block implementation. Stores generated machine code.
*/
class CodeBlock
{
    /// Memory block
    private ubyte* memBlock;

    /// Memory block size
    private size_t memSize;

    /// Current writing position
    private size_t writePos = 0;

    /// Disassembly/comment strings
    alias Tuple!(size_t, "pos", string, "str") CommentStr;
    private CommentStr[] strings;

    // Table of label addresses
    private size_t[Label.max+1] labelAddrs;

    // Label reference list
    alias Tuple!(size_t, "pos", Label, "label") LabelRef;
    private LabelRef labelRefs[];

    /// Flag to enable or disable comments
    private bool hasComments;

    this(size_t memSize, bool hasComments)
    {
        assert (
            memSize > 0,
            "cannot create zero-sized memory block"
        );

        this.memSize = memSize;
        this.hasComments = hasComments;

        // Map the memory as executable
        this.memBlock = cast(ubyte*)mmap(
            null,
            memSize,
            PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_PRIVATE | MAP_ANON,
            -1,
            0
        );

        // Check that the memory mapping was successful
        if (this.memBlock == MAP_FAILED)
            throw new Error("mmap call failed");

        for (auto label = Label.min; label <= Label.max; ++label)
            labelAddrs[label] = size_t.max;
    }

    ~this()
    {
        //writefln("freeing executable memory: %s", this.memBlock);

        auto ret = munmap(this.memBlock, this.memSize);

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
    Get a direct pointer into the executable memory block
    */
    auto getAddress(size_t index = 0)
    {
        assert (
            index < memSize,
            "invalid index in getAddress: " ~ to!string(index)
        );

        return cast(const ubyte*)&memBlock[index];
    }

    /**
    Set the current write position
    */
    void setWritePos(size_t pos)
    {
        assert (
            pos < memSize,
            "invalid code block position: " ~ to!string(pos)
        );

        writePos = pos;
    }

    /**
    Get the current write position
    */
    size_t getWritePos() const
    {
        return writePos;
    }

    /**
    Get the size of the code block
    */
    size_t getSize() const
    {
        return memSize;
    }

    /**
    Get the remaining space available
    */
    size_t getRemSpace() const
    {
        return memSize - writePos;
    }

    /**
    Test if the code block is empty
    */
    bool empty() const
    {
        return writePos is 0;
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
            this.writePos + 1 <= this.memSize,
            "memory block out of space"
        );

        this.memBlock[this.writePos++] = val;
    }

    /**
    Write a sequence of bytes at the current position
    */
    void writeBytes(T...)(T bytes)
    {
        assert (
            this.writePos + bytes.length <= this.memSize,
            "memory block out of space"
        );

        foreach (b; bytes)
        {
            this.memBlock[this.writePos++] = cast(ubyte)b;
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

        // Switch on the number of bits
        switch (numBits)
        {
            case 8:
            this.writeByte(cast(ubyte)val);
            break;

            case 16:
            this.writeBytes(
                cast(ubyte)((val >> 0) & 0xFF),
                cast(ubyte)((val >> 8) & 0xFF),
            );
            break;

            case 32:
            this.writeBytes(
                cast(ubyte)((val >>  0) & 0xFF),
                cast(ubyte)((val >>  8) & 0xFF),
                cast(ubyte)((val >> 16) & 0xFF),
                cast(ubyte)((val >> 24) & 0xFF),
            );
            break;

            default:
            {
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
    Write the contents of another code block at the given position
    */
    /*
    void writeBlock(CodeBlock cb)
    {
        if (this.writePos + cb.writePos > this.memSize)
            noSpace(this.writePos + cb.writePos);

        // If the other block has comment strings
        if (cb.strings.length > 0)
        {
            //writeln("merging strings (", strings.length, ")");

            // Translate the positions of the strings being written
            auto newStrs = array(map!(s => CommentStr(writePos + s.pos, s.str))(cb.strings));

            // Get the strings that come before and after the other block's
            auto range = assumeSorted!"a.pos < b.pos"(strings);
            auto lower = range.lowerBound(newStrs.front);
            auto upper = range.upperBound(newStrs.back);

            //writeln("lower.length: ", lower.length);
            //writeln("upper.length: ", upper.length);

            // Insert the new strings in between
            strings = lower.release() ~ newStrs ~ upper.release();
        }

        // Copy the bytes from the other code block
        this.memBlock[this.writePos..this.writePos+cb.writePos] = cb.memBlock[0..cb.writePos];
        this.writePos += cb.writePos;   
    }
    */

    /**
    Read the byte at the given index
    */
    ubyte readByte(size_t index)
    {
        assert (
            index < memSize
        );

        return memBlock[index];
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
    Write a comment string. Does nothing if ASM dump is not enabled.
    */
    void comment(string str)
    {
        if (!hasComments)
            return;

        return writeStr("; " ~ str);
    }

    /**
    Set the address of a label to the current write position
    */
    Label label(Label label)
    {
        auto labelAddr = labelAddrs[label];

        if (hasComments)
            writeStr(to!string(label) ~ ":");

        assert (
            labelAddr is size_t.max,
            "label \"" ~ to!string(label) ~ 
            "\" already defined at position " ~
            to!string(labelAddr)
        );

        labelAddrs[label] = getWritePos();
        return label;
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
    void linkLabels()
    {
        auto origPos = writePos;

        // For each label reference
        foreach (labelRef; labelRefs)
        {
            assert (labelRef.pos < memSize);
            auto labelAddr = labelAddrs[labelRef.label];
            assert (labelAddr < memSize);

            // Compute the offset from the reference's end to the label
            auto offset = labelAddr - (labelRef.pos + 4);

            setWritePos(labelRef.pos);
            writeInt(offset, 32);
        }

        writePos = origPos;

        // Clear the label positions and references
        for (auto label = Label.min; label <= Label.max; ++label)
            labelAddrs[label] = size_t.max;
        labelRefs.clear();
    }
}

