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
import jit.codeblock;

/**
Base class for X86 operands
*/
class X86Opnd
{
    bool rexNeeded() const
    {
        return false;
    }
}

/**
Representation of an x86 register
*/
class X86Reg : X86Opnd
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
    X86Reg ofSize(size_t numBits)
    {
        if (numBits == this.size)
            return this;

        return new X86Reg(this.type, this.regNo, numBits);
    }

    /**
    Produce a string representation of the register
    */
    override string toString() const
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
    override bool opEquals(Object o)
    {
        auto that = cast(X86Reg)o;

        if (that is null)
            return false;

        return (
            this.type == that.type && 
            this.regNo == that.regNo && 
            this.size == that.size
        );
    }

    /**
    Test if the REX prefix is needed to encode this operand
    */
    override bool rexNeeded() const
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

        decls.put("X86Reg " ~ upName ~ ";\n");

        init.put(upName ~ " = new X86Reg(" ~ typeStr ~ ", " ~ to!string(regNo) ~ ", " ~ to!string(numBits) ~ ");\n");
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

/**
Immediate operand value (constant)
*/
class X86Imm : X86Opnd
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

    override string toString() const
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
Reference to a label (relative operand)
*/
class X86LabelRef : X86Imm
{
    this(Label label)
    {
        super(0);
        this.label = label;
    }

    override string toString() const
    {
        return format("%s(%s)", this.label.name, this.label.offset);
    }

    Label label;
}

/**
Absolute memory offset
*/
class X86MOffs : X86Imm
{
    this(void* ptr)
    {
        super(ptr);
    }

    override string toString() const
    {
        return format("[%X]", this.unsgImm);
    }
}

/**
Memory location operand
*/
class X86Mem : X86Opnd
{
    X86Reg base; 

    X86Reg index; 

    int32_t disp; 

    uint8_t memSize;

    uint8_t scale;

    this(
        size_t size, 
        X86Reg base, 
        int32_t disp    = 0, 
        X86Reg index    = null, 
        size_t scale    = 1
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
    override bool opEquals(Object that) 
    {
        auto a = cast(X86Mem)this;
        auto b = cast(X86Mem)that;

        return (
            b !is null &&
            a.base is b.base &&
            a.index is b.index &&
            a.disp is b.disp &&
            a.memSize is b.memSize &&
            a.scale is b.scale
        );
    }

    override string toString() const
    {
        return toString(this.disp, null);
    }

    string toString(int32_t disp, const Label label) const
    {
        auto str = "";

        assert (
            !(label && this.base != RIP),
            "label provided when base is not RIP"
        );

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

        if (this.base && !label)
        {
            if (str != "")
                str ~= " ";
            str ~= this.base.toString();
        }

        if (label)
        {
            if (str != "")
                str ~= " ";
            str ~= label.name;
        }

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

        if (this.index)
        {
            if (str != "")
                str ~= " + ";
            if (this.scale != 1)
                str ~= to!string(this.scale) ~ " * ";
            str ~= this.index.toString();
        }

        return '[' ~ str ~ ']';
    }

    /**
    Test if the REX prefix is needed to encode this operand
    */
    override bool rexNeeded() const
    {
        return (base && base.rexNeeded) || (index && index.rexNeeded);
    }

    /**
    Test if an SIB byte is needed to encode this operand
    */
    bool sibNeeded()
    {
        return (
            this.index || 
            this.scale != 1 ||
            (!this.base && !this.index) ||
            this.base == ESP ||
            this.base == RSP ||
            this.base == R12
        );
    }

    /**
    Compute the size of the displacement field needed
    */
    size_t dispSize()
    {
        // If using displacement only or if using an index only or if using
        // RIP as the base, use disp32
        if ((!base && !index) || (!base && index) || (base == RIP))
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

/**
X86 opcode and list of associated encodings
*/
struct X86Op
{
    /// Mnemonic name string
    string mnem;

    /// List of possible encodings
    X86Enc[] encs;
}

alias immutable(X86Op)* X86OpPtr;

/**
X86 instruction encoding
*/
struct X86Enc
{
    enum : uint8_t
    {
        R,
        M,
        R_OR_M,
        XMM,
        XMM_OR_M,
        IMM,
        MOFFS,
        REL,
        REGA,   // AL/AX/EAX/RAX
        REGC,   // CL
        CST1    // Constant 1
    }

    uint8_t[] opndTypes;
    uint8_t[] opndSizes;

    uint8_t[] prefix;
    uint8_t[] opcode;
    uint8_t opExt;

    uint opndSize;
    bool szPref;
    bool rexW;
}

alias immutable(X86Enc)* X86EncPtr;

/**
X86 machine instruction representation
*/
class X86Instr : ASMInstr
{
    /// Maximum number of operands
    static const MAX_OPNDS = 4;

    /// Opcode (instruction type)
    X86OpPtr opcode = null;

    /// Operands
    X86Opnd[MAX_OPNDS] opnds;

    /// Encoding found
    X86EncPtr enc = null;

    /// Encoding length
    uint8_t encLength = 0;

    this(X86OpPtr opcode)
    {
        this.opcode = opcode;
    }

    this(X86OpPtr opcode, X86Opnd opnd0)
    {
        this.opcode = opcode;
        this.opnds = [opnd0, null, null, null];
    }

    this(X86OpPtr opcode, X86Opnd opnd0, X86Opnd opnd1)
    {
        this.opcode = opcode;
        this.opnds = [opnd0, opnd1, null, null];
    }

    this(X86OpPtr opcode, X86Opnd opnd0, X86Opnd opnd1, X86Opnd opnd2)
    {
        this.opcode = opcode;
        this.opnds = [opnd0, opnd1, opnd2, null];
    }

    /**
    Produce a string representation of this instruction
    */
    override string toString()
    {
        auto str = "";

        str ~= opcode.mnem;

        foreach (i, opnd; opnds)
        {
            if (opnd is null)
                break;

            if (i == 0)
                str ~= " ";
            else
                str ~= ", ";

            str ~= opnd.toString();
        }

        str ~= ';';

        return str;
    }

    /**
    Test if this instruction has a valid encoding
    */
    bool valid()
    {
        if (enc !is null)
            return true;

        findEncoding();

        return (enc !is null);
    }

    /**
    Get the length of the best encoding of this instruction
    */
    override size_t length()
    {
        // If no encoding is yet found, find one
        if (enc is null)
            findEncoding();

        assert (
            this.enc !is null,
            "cannot compute length, no encoding found"
        );

        // Return the encoding length
        return this.encLength;
    }

    /**
    Encode the instruction into a byte array
    */
    override void encode(CodeBlock codeBlock)
    {
        // If no encoding is yet found, find one
        if (this.enc is null)
            this.findEncoding();

        assert (
            this.enc !is null,
            "cannot encode instruction, no encoding found for:\n" ~
            this.toString()
        );

        // Flag to indicate the REX prefix is needed
        bool rexNeeded = (enc.rexW == 1);

        // Flags to indicate if the ModRM and SIB bytes needed
        bool rmNeeded = false;
        bool sibNeeded = false;

        // r and r/m operands
        X86Reg rOpnd = null;
        X86Mem rmOpndM = null;
        X86Reg rmOpndR = null;

        // Immediate operand size and value
        size_t immSize = 0;
        int64_t immVal = 0;

        // Displacement size and value
        size_t dispSize = 0;
        int32_t dispVal = 0;

        // For each operand
        for (size_t i = 0; i < enc.opndTypes.length; ++i)
        {
            auto opnd = this.opnds[i];

            auto opndType = enc.opndTypes[i];
            auto opndSize = enc.opndSizes[i];

            if (opnd.rexNeeded == true)
                rexNeeded = true;

            if (opndType == X86Enc.IMM ||
                opndType == X86Enc.MOFFS ||
                opndType == X86Enc.REL)
            {
                immSize = opndSize;
                immVal = (cast(X86Imm)opnd).imm;
            }

            else if (opndType == X86Enc.R ||
                     opndType == X86Enc.XMM)
            {
                rOpnd = cast(X86Reg)opnd;
            }

            else if (opndType == X86Enc.M ||
                     opndType == X86Enc.R_OR_M ||
                     opndType == X86Enc.XMM_OR_M)
            {
                rmNeeded = true;

                rmOpndM = cast(X86Mem)opnd;

                if (rmOpndM !is null)
                {
                    if (rmOpndM.sibNeeded)
                    {
                        sibNeeded = true;
                    }

                    if (rmOpndM.dispSize > 0)
                    {
                        dispSize = rmOpndM.dispSize;
                        dispVal = rmOpndM.disp;
                    }
                }
                else
                {
                    rmOpndR = cast(X86Reg)opnd;
                }
            }
        }

        // Get the index in the code block before the encoding
        auto startIndex = codeBlock.getWritePos();

        // Add the address-size prefix, if needed
        if (rmOpndM)
        {
            if ((rmOpndM.base && rmOpndM.base.size == 32) ||
                (rmOpndM.index && rmOpndM.index.size == 32))
                    codeBlock.writeByte(0x67);
        }

        // Add the operand-size prefix, if needed
        if (enc.szPref == true)
            codeBlock.writeByte(0x66);

        // Write the prefix bytes to the code block
        codeBlock.writeBytes(enc.prefix);

        // Add the REX prefix, if needed
        if (rexNeeded)
        {
            // 0 1 0 0 w r x b
            // w - 64-bit operand size flag
            // r - MODRM.reg extension
            // x - SIB.index extension
            // b - MODRM.rm or SIB.base extension

            uint w = enc.rexW? 1:0;

            uint r;
            if (rOpnd && rmNeeded)
                r = (rOpnd.regNo & 8)? 1:0;
            else
                r = 0;

            uint x;
            if (sibNeeded && rmOpndM.index)
                x = (rmOpndM.index.regNo & 8)? 1:0;
            else
                x = 0;

            uint b;
            if (rmOpndR)
                b = (rmOpndR.regNo & 8)? 1:0;
            else if (rOpnd && !rmNeeded)
                b = (rOpnd.regNo & 8)? 1:0;
            else if (rmOpndM && rmOpndM.base)
                b = (rmOpndM.base.regNo & 8)? 1:0;
            else
                b = 0;

            // Encode and write the REX byte
            auto rexByte = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
            codeBlock.writeByte(cast(byte)rexByte);
        }

        // If an opcode reg field is to be used
        if (rOpnd && !rmNeeded)
        {
            // Write the reg field into the opcode byte
            uint8_t opByte = enc.opcode[0] | (rOpnd.regNo & 7);
            codeBlock.writeByte(opByte);
        }
        else
        {
            // Write the opcode bytes to the code block
            codeBlock.writeBytes(enc.opcode);
        }

        // Add the ModR/M byte, if needed
        if (rmNeeded)
        {
            // MODRM.mod (2 bits)
            // MODRM.reg (3 bits)
            // MODRM.rm  (3 bits)

            assert (
                !(enc.opExt != 0xFF && rOpnd),
                "opcode extension and register operand present"
            );

            // Encode the mod field
            int mod;
            if (rmOpndR)
            {
                mod = 3;
            }
            else
            {
                if (dispSize == 0 || !rmOpndM.base || rmOpndM.base == RIP)
                    mod = 0;
                else if (dispSize == 8)
                    mod = 1;
                else if (dispSize == 32)
                    mod = 2;
            }

            // Encode the reg field
            int reg;
            if (enc.opExt != 0xFF)
                reg = enc.opExt;
            else if (rOpnd)
                reg = rOpnd.regNo & 7;
            else
                reg = 0;

            // Encode the rm field
            int rm;
            if (rmOpndR)
            {
                rm = rmOpndR.regNo & 7;
            }
            else
            {
                if (sibNeeded)
                    rm = 4;
                else if (rmOpndM.base == RIP)
                    rm = 5;
                else if (rmOpndM.base)
                    rm = rmOpndM.base.regNo & 7;
                else
                    rm = 0;
            }

            // Encode and write the ModR/M byte
            auto rmByte = (mod << 6) + (reg << 3) + (rm);
            codeBlock.writeByte(cast(ubyte)rmByte);

            //writefln("rmByte: %s", rmByte);
        }

        // Add the SIB byte, if needed
        if (sibNeeded)
        {
            // SIB.scale (2 bits)
            // SIB.index (3 bits)
            // SIB.base  (3 bits)

            assert (
                rmOpndM !is null,
                "expected r/m opnd to be mem loc"
            );

            // Encode the scale value
            int scale;
            switch (rmOpndM.scale)
            {
                case 1: scale = 0; break;
                case 2: scale = 1; break;
                case 4: scale = 2; break;
                case 8: scale = 3; break;
                default: assert (false, "invalid SIB scale");
            }

            // Encode the index value
            int index;
            if (!rmOpndM.index)
                index = 4;
            else
                index = rmOpndM.index.regNo & 7;

            // Encode the base register
            int base;
            if (!rmOpndM.base)
                base = 5;
            else
                base = rmOpndM.base.regNo & 7;

            // Encode and write the SIB byte
            auto sibByte = (scale << 6) + (index << 3) + (base);
            codeBlock.writeByte(cast(uint8_t)sibByte);
        }

        // Add the displacement size
        if (dispSize != 0)
            codeBlock.writeInt(dispVal, dispSize);

        // If there is an immediate operand
        if (immSize != 0)
            codeBlock.writeInt(immVal, immSize);

        // Get the index in the code block after the encoding
        auto endIndex = codeBlock.getWritePos();

        // Compute the length of the data written
        auto wrtLength = endIndex - startIndex;

        assert (
            wrtLength == this.encLength,
            format(
                "encoding length:\n" ~
                "%s\n" ~
                "does not match expected length:\n" ~
                "%s\n" ~
                "for:\n" ~
                "%s",
                wrtLength,
                encLength,
                toString()
            )
        );
    }

    /**
    Find the best encoding for this instruction
    */
    X86EncPtr findEncoding()
    {
        //writefln("findEncoding");

        // Best encoding found
        X86EncPtr bestEnc = null;
        size_t bestLen = size_t.max;

        // TODO: stop at first match? sort by shortest first?

        // For each possible encoding
        ENC_LOOP:
        for (size_t i = 0; i < opcode.encs.length; ++i)
        {
            auto enc = &opcode.encs[i];

            // If the number of operands does not match, skip this encoding
            auto numOpnds = enc.opndTypes.length;
            if ((numOpnds > 0 && this.opnds[numOpnds - 1] is null) ||
                (numOpnds < MAX_OPNDS && this.opnds[numOpnds] !is null))
                continue ENC_LOOP;

            // For each operand
            for (size_t j = 0; j < numOpnds; ++j)
            {
                auto opnd = this.opnds[j];

                auto opndType = enc.opndTypes[j];
                auto opndSize = enc.opndSizes[j];

                // Switch on the operand type
                switch (opndType)
                {
                    case X86Enc.REGA:
                    auto reg = cast(X86Reg)opnd;
                    if (reg is null ||
                        reg.regNo != RAX.regNo ||
                        reg.size != opndSize)
                        continue ENC_LOOP;
                    break;

                    case X86Enc.REGC:
                    auto reg = cast(X86Reg)opnd;
                    if (reg is null ||
                        reg.regNo != RCX.regNo ||
                        reg.size != opndSize)
                        continue ENC_LOOP;
                    break;

                    case X86Enc.CST1:
                    auto imm = cast(X86Imm)opnd;
                    if (imm is null)
                        continue ENC_LOOP;
                    if (imm.imm != 1)
                        continue ENC_LOOP;
                    break;

                    case X86Enc.IMM:
                    auto imm = cast(X86Imm)opnd;
                    if (imm is null)
                        continue ENC_LOOP;
                    if (imm.immSize > opndSize)
                    {
                        if (!imm.unsgSize)
                            continue ENC_LOOP;

                        if (imm.unsgSize != opndSize || 
                            opndSize != enc.opndSize)
                            continue ENC_LOOP;
                    }
                    break;

                    case X86Enc.REL:
                    auto rel = cast(X86LabelRef)opnd;
                    if (rel is null)
                        continue ENC_LOOP;
                    if (rel.immSize > opndSize)
                        continue ENC_LOOP;
                    break;

                    case X86Enc.MOFFS:
                    auto moffs = cast(X86MOffs)opnd;
                    if (moffs is null)
                        continue ENC_LOOP;
                    if (moffs.unsgSize > opndSize)
                        continue ENC_LOOP;
                    break;

                    case X86Enc.R:
                    auto reg = cast(X86Reg)opnd;
                    if (!(reg && reg.type == X86Reg.GP))
                        continue ENC_LOOP;
                    if (reg.size != opndSize)
                        continue ENC_LOOP;
                    break;

                    case X86Enc.XMM:
                    auto reg = cast(X86Reg)opnd;
                    if (!(reg && reg.type == X86Reg.XMM))
                        continue ENC_LOOP;
                    break;

                    case X86Enc.M:
                    auto mem = cast(X86Mem)opnd;
                    if (mem is null)
                        continue ENC_LOOP;
                    // If the memory location has a size and it doesn't match
                    if (opndSize != 0 && mem.memSize != opndSize)
                        continue ENC_LOOP;
                    break;

                    case X86Enc.R_OR_M:
                    auto reg = cast(X86Reg)opnd;
                    auto mem = cast(X86Mem)opnd;
                    if (!(reg                       && 
                          reg.type == X86Reg.GP     && 
                          reg.size == opndSize)     && 
                        !(mem                       && 
                          mem.memSize == opndSize))
                        continue ENC_LOOP;
                    break;

                    case X86Enc.XMM_OR_M:
                    auto reg = cast(X86Reg)opnd;
                    auto mem = cast(X86Mem)opnd;
                    if (!(reg && reg.type == X86Reg.XMM) && 
                        !(mem && mem.memSize == opndSize))
                        continue ENC_LOOP;
                    break;

                    default:
                    assert (false, "invalid operand type");
                }
            }

            auto len = compEncLen(enc);

            if (len < bestLen)
            {
                bestEnc = enc;
                bestLen = len;
            }
        }

        // Store the best encoding found
        enc = bestEnc;

        // Store the encoding length
        encLength = cast(uint8_t)bestLen;

        //writefln("findEncoding done");

        return bestEnc;
    }

    /**
    Compute the length of an encoding of this instruction
    */
    size_t compEncLen(X86EncPtr enc)
    {
        assert (
            enc !is null,
            "compEncLen on null encoding"
        );

        // x86 instruction format:
        // prefix(es)  [REX] opcode  [XRM  [SIB]]  disp  imm

        // Flag to indicate the REX prefix is needed
        bool rexNeeded = (enc.rexW == 1);

        // Flags to indicate if the ModRM and SIB bytes needed
        bool rmNeeded = false;
        bool sibNeeded = false;

        // RM operand, if present
        X86Mem rmOpndM = null;
        X86Reg rmOpndR = null;

        // Displacement size required
        size_t dispSize = 0;

        // Immediate size required
        size_t immSize = 0;

        // For each operand
        for (size_t i = 0; i < enc.opndTypes.length; ++i)
        {
            auto opnd = this.opnds[i];

            auto opndType = enc.opndTypes[i];
            auto opndSize = enc.opndSizes[i];

            if (opnd.rexNeeded)
                rexNeeded = true;

            if (opndType == X86Enc.IMM ||
                opndType == X86Enc.MOFFS ||
                opndType == X86Enc.REL)
            {
                immSize = opndSize;
            }

            // If this operand can be a memory location
            else if (opndType == X86Enc.M ||
                     opndType == X86Enc.R_OR_M ||
                     opndType == X86Enc.XMM_OR_M)
            {
                rmNeeded = true;

                rmOpndM = cast(X86Mem)opnd;

                if (rmOpndM !is null)
                {
                    if (rmOpndM.sibNeeded)
                        sibNeeded = true;

                    if (rmOpndM.dispSize > 0)
                        dispSize = rmOpndM.dispSize;
                }
                else
                {
                    rmOpndR = cast(X86Reg)opnd;
                }
            }
        }

        // Total encoding size
        size_t size = 0;

        // Add the address-size prefix, if needed
        if (rmOpndM)
        {
            if ((rmOpndM.base && rmOpndM.base.size == 32) ||
                (rmOpndM.index && rmOpndM.index.size == 32))
                size += 1;
        }

        // Add the operand-size prefix, if needed
        if (enc.szPref == true)
            size += 1;

        // Add the prefix size
        size += enc.prefix.length;

        // Add the REX prefix, if needed
        if (rexNeeded == true)
            size += 1;

        // Add the opcode size
        size += enc.opcode.length;

        // Add the ModR/M byte, if needed
        if (rmNeeded)
            size += 1;

        // Add the SIB byte, if needed
        if (sibNeeded)
            size += 1;

        // Add the displacement size (in bytes)
        size += dispSize / 8;

        // Add the immediate size (in bytes)
        size += immSize / 8;

        // Return the encoding size
        return size;
    }
}

