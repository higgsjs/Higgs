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
    LOOP_TEST,
    LOOP_EXIT,
    DONE,
    TRUE,
    TRUE2,
    FALSE,
    FALSE2,
    JOIN,
    SKIP,
    THROW,
    FALLBACK,
    BAILOUT,
    FUN1,
    FUN2,
    BRANCH_TARGET0,
    BRANCH_TARGET1,
    AFTER_DATA
}

/// Code pointer type definition
alias const(ubyte)* CodePtr;

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

    /// Disassembly/comment strings, indexed by position
    alias Tuple!(size_t, "pos", string, "str") CommentStr;
    private CommentStr[][] strings;

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
        return toString(0, memSize);
    }

    /**
    Print the code block as a string
    */
    string toString(size_t startIdx, size_t endIdx)
    {
        assert (startIdx <= endIdx);
        assert (endIdx <= writePos, "endIdx=" ~ to!string(endIdx));

        auto app = appender!string();

        // For each byte to print
        for (size_t curPos = startIdx; curPos < endIdx; ++curPos)
        {
            // If there are strings at this position
            auto strs = (curPos < strings.length)? strings[curPos]:[];
            if (strs.length > 0)
            {
                // Start a new line
                if (app.data.length > 0)
                    app.put("\n");

                // Print each string on its own line
                foreach (str; strs[0..$-1])
                {
                    app.put(str.str);
                    app.put("\n");
                }

                // Add padding space before the hex printout
                app.put(rightPadStr(strs[$-1].str, " ", 40));
            }

            // Print all the bytes until the next string
            app.put(format("%02X", memBlock[curPos]));
        }

        return app.data;
    }

    /**
    Get a direct pointer into the executable memory block
    */
    CodePtr getAddress(size_t index = 0)
    {
        assert (
            index < memSize,
            "invalid index in getAddress: " ~ to!string(index)
        );

        return cast(CodePtr)&memBlock[index];
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
    void writeString(string str)
    {
        if (!hasComments)
            return;

        auto newStr = CommentStr(writePos, str);

        if (writePos >= strings.length)
            strings.length = writePos + 1;

        strings[writePos] ~= newStr;
    }

    /**
    Delete strings at or after a given position
    */
    void delStrings(size_t startIdx, size_t endIdx)
    {
        assert (endIdx >= startIdx);

        if (strings.length is 0)
            return;

        // Clear the strings at each byte position
        for (size_t curPos = startIdx; curPos < endIdx; ++curPos)
            if (curPos < strings.length)
                strings[curPos].length = 0;
    }

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

        return writeString(str);
    }

    /**
    Write a comment string. Does nothing if ASM dump is not enabled.
    */
    void comment(string str)
    {
        if (!hasComments)
            return;

        return writeString("; " ~ str);
    }

    /**
    Set the address of a label to the current write position
    */
    Label label(Label label)
    {
        auto labelAddr = labelAddrs[label];

        if (hasComments)
            writeString(to!string(label) ~ ":");

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
        debug
        {
            foreach (labelRef; labelRefs)
                assert (labelRef.pos != writePos);
        }

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

