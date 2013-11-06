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

module jit.x86;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.stdint;
import jit.assembler;

/**
Representation of an x86 register
*/
struct X86Reg
{
    alias uint8_t Type;
    enum : Type
    {
        GP,
        FP,
        XMM,
        IP
    }

    /// Register type
    uint8_t type;

    /// Register index number
    uint8_t regNo;

    /// Size in bits
    uint16_t size;

    this(Type type, size_t regNo, size_t size)
    {
        assert (
            regNo < 16,
            "invalid register number"
        );

        assert (
            size <= 256,
            "invalid register size"
        );

        this.type = type;
        this.regNo = cast(uint8_t)regNo;
        this.size = cast(uint16_t)size;
    }

    /**
    Get a register with the same type and register number
    but a potentially different size
    */
    X86Reg ofSize(size_t numBits) const
    {
        if (numBits == this.size)
            return this;

        return X86Reg(this.type, this.regNo, numBits);
    }

    /**
    Produce a string representation of the register
    */
    string toString() const
    {
        switch (type)
        {
            case GP:
            if (regNo < 8)
            {
                auto rs = "";
                final switch (regNo)
                {
                    case 0: rs = "a"; break;
                    case 1: rs = "c"; break;
                    case 2: rs = "d"; break;
                    case 3: rs = "b"; break;
                    case 4: rs = "sp"; break;
                    case 5: rs = "bp"; break;
                    case 6: rs = "si"; break;
                    case 7: rs = "di"; break;
                }

                final switch (size)
                {
                    case 8 : return rs ~ "l";
                    case 16: return (rs.length == 1)? (rs ~ "x"):rs;
                    case 32: return (rs.length == 1)? ("e" ~ rs ~ "x"):("e" ~ rs);
                    case 64: return (rs.length == 1)? ("r" ~ rs ~ "x"):("r" ~ rs);
                }
            }
            else
            {
                final switch (size)
                {
                    case 8 : return "r" ~ to!string(regNo) ~ "l";
                    case 16: return "r" ~ to!string(regNo) ~ "w";
                    case 32: return "r" ~ to!string(regNo) ~ "d";
                    case 64: return "r" ~ to!string(regNo);
                }
            }
            assert (false);

            case XMM:
            return "xmm" ~ to!string(regNo);

            case FP:
            return "st" ~ to!string(regNo);

            case IP:
            return "rip";

            default:
            assert (false);
        }
    }

    /**
    Comparison operator
    */
    bool opEquals(immutable X86Reg that) const
    {
        return (
            this.type == that.type && 
            this.regNo == that.regNo && 
            this.size == that.size
        );
    }

    /**
    Test if the REX prefix is needed to encode this operand
    */
    bool rexNeeded() const
    {
        return (
            regNo > 7 ||
            (size == 8 && regNo >= 4 && regNo <= 7)
        );
    }
}

// Auto-generate named register constants
string genRegCsts()
{
    auto decls = appender!string();
    auto init = appender!string();

    init.put("static this()\n");
    init.put("{\n");

    void genCst(ubyte type, string typeStr, ubyte regNo, ubyte numBits)
    {
        auto regName = (new X86Reg(type, regNo, numBits)).toString();
        auto upName = regName.toUpper();

        decls.put("immutable X86Reg " ~ upName ~ ";\n");

        init.put(upName ~ " = X86Reg(" ~ typeStr ~ ", " ~ to!string(regNo) ~ ", " ~ to!string(numBits) ~ ");\n");
    }

    for (ubyte regNo = 0; regNo < 16; ++regNo)
    {
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 8);
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 16);
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 32);
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 64);

        genCst(X86Reg.XMM, "X86Reg.XMM", regNo, 128);
    }

    // RIP
    genCst(X86Reg.IP, "X86Reg.IP", 5, 64);

    // Floating-point registers (x87)
    genCst(X86Reg.FP, "X86Reg.FP", 0, 80);

    init.put("}\n");

    return decls.data ~ "\n" ~ init.data;
}
mixin(genRegCsts());

unittest
{
    X86Reg r = EAX;
    assert (r == EAX && EAX == EAX && EAX != EBX);
}

/**
Immediate operand value (constant)
*/
struct X86Imm
{
    union
    {
        // Signed immediate value
        int64_t imm;

        // Unsigned immediate value
        uint64_t unsgImm;
    }

    /**
    Create an immediate operand
    */
    this(int64_t imm)
    {
        this.imm = imm;
    }

    /**
    Create a pointer constant
    */
    this(void* ptr)
    {
        this.unsgImm = cast(uint64_t)ptr;
    }

    string toString() const
    {
        return to!string(this.imm);
    }

    /**
    Compute the immediate value size
    */
    size_t immSize() const
    {
        // Compute the smallest size this immediate fits in
        if (imm >= int8_t.min && imm <= int8_t.max)
            return 8;
        if (imm >= int16_t.min && imm <= int16_t.max)
            return 16;
        if (imm >= int32_t.min && imm <= int32_t.max)
            return 32;

        return 64;
    }

    /**
    Immediate value size if treated as unsigned
    */
    size_t unsgSize() const
    {
        if (unsgImm <= uint8_t.max)
            return 8;
        else if (unsgImm <= uint16_t.max)
            return 16;
        else if (unsgImm <= uint32_t.max)
            return 32;

        return 64;
    }
}

/**
Memory location operand
*/
struct X86Mem
{
    X86Reg base; 

    X86Reg index;

    /// Constant displacement from the base, not scaled
    int32_t disp; 

    /// Memory location size
    uint8_t memSize;

    /// Index scale value, zero if not using an index
    uint8_t scale;

    this(
        size_t size, 
        X86Reg base, 
        int32_t disp    = 0, 
        size_t scale    = 0,
        X86Reg index    = EAX, 
    )
    {
        this.memSize = cast(uint8_t)size;
        this.base    = base;
        this.disp    = disp;
        this.index   = index;
        this.scale   = cast(uint8_t)scale;
    }

    /**
    Equality comparison operator
    */
    bool opEquals(X86Mem that) const
    {
        return (
            this.base is that.base &&
            this.index is that.index &&
            this.disp is that.disp &&
            this.memSize is that.memSize &&
            this.scale is that.scale
        );
    }

    string toString() const
    {
        return toString(this.disp/*, null*/);
    }

    string toString(int32_t disp/*, const Label label*/) const
    {
        auto str = "";

        /*
        assert (
            !(label && this.base != RIP),
            "label provided when base is not RIP"
        );
        */

        switch (this.memSize)
        {
            case 8:     str ~= "byte"; break;
            case 16:    str ~= "word"; break;
            case 32:    str ~= "dword"; break;
            case 64:    str ~= "qword"; break;
            case 128:   str ~= "oword"; break;
            default:
            assert (false, "unknown operand size");
        }

        if (str != "")
            str ~= " ";
        str ~= this.base.toString();

        /*
        if (label)
        {
            if (str != "")
                str ~= " ";
            str ~= label.name;
        }
        */

        if (disp)
        {
            if (str != "")
            {
                if (disp < 0)
                    str ~= " - " ~ to!string(-disp);
                else
                    str ~= " + " ~ to!string(disp);
            }
            else
            {
                str ~= disp;
            }
        }

        if (this.scale !is 0)
        {
            if (str != "")
                str ~= " + ";
            if (this.scale !is 1)
                str ~= to!string(this.scale) ~ " * ";
            str ~= this.index.toString();
        }

        return '[' ~ str ~ ']';
    }

    /**
    Test if the REX prefix is needed to encode this operand
    */
    bool rexNeeded() const
    {
        return base.rexNeeded || (scale && index.rexNeeded);
    }

    /**
    Test if an SIB byte is needed to encode this operand
    */
    bool sibNeeded() const
    {
        return (
            this.scale != 0 ||
            this.base == ESP ||
            this.base == RSP ||
            this.base == R12
        );
    }

    /**
    Compute the size of the displacement field needed
    */
    size_t dispSize() const
    {
        // If using RIP as the base, use disp32
        if (/*(!base && !scale) || (!base && scale) ||*/ (base == RIP))
            return 32;

        // Compute the required displacement size
        if (disp != 0)
        {
            if (disp >= int8_t.min && disp <= int8_t.max)
                return 8;
            if (disp >= int32_t.min && disp <= int32_t.max)
                return 32;

            assert (false, "displacement does not fit in 32 bits: " ~ to!string(disp));
        }

        // If EBP or RBP or R13 is used as the base, displacement must be encoded
        if (base == EBP || base == RBP || base == R13)
            return 8;

        return 0;
    }
}

/**
IP-relative memory location
*/
// TODO: reimplement without inheritance, when needed
// just store an X86Mem inside
/*
class X86IPRel : X86Mem
{
    /// Label to use as a reference
    Label label;

    /// Additional displacement relative to the label
    int32_t labelDisp;

    this(
        size_t size, 
        Label label,  
        int32_t disp    = 0,
        X86Reg index    = null, 
        size_t scale    = 1
    )
    {
        super(size, RIP, disp, index, scale);
        this.label = label;
        this.labelDisp = disp;
    }

    override string toString() const
    {
        return super.toString(this.labelDisp, this.label);
    }
}
*/

/*
TODO: x86 encoding methods
- First goal is basic system working, don't write all encodings now
  - But begin testing early
- Lower-level encoding functions should work with CodeBlock objects
- Some op like move, cmp, if should work on CodeBlock
  - But can be aliased for Assembler (possibly with an easy macro!)
- Some ops only fit in innerCode, should apply to Assembler only
nop(CodeBlock cb, size_t length = 1)
jmp(CodeBlock cb, Label label)
*/


















