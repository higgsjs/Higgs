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
import std.algorithm;
import jit.codeblock;

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
    Get an operand object for a register of the requested size
    */
    X86Opnd opnd(size_t numBits) const
    {
        return X86Opnd(ofSize(numBits));
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

    void genCst(ubyte type, string typeStr, ubyte regNo, ubyte numBits)
    {
        auto regName = (new X86Reg(type, regNo, numBits)).toString();
        auto upName = regName.toUpper();

        decls.put(
            "immutable X86Reg " ~ upName ~ " = X86Reg(" ~ typeStr ~ ", " ~ 
            to!string(regNo) ~ ", " ~ to!string(numBits) ~ ");\n"
        );
    }

    for (ubyte regNo = 0; regNo < 16; ++regNo)
    {
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 8);
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 16);
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 32);
        genCst(X86Reg.GP, "X86Reg.GP", regNo, 64);

        genCst(X86Reg.XMM, "X86Reg.XMM", regNo, 128);
    }

    // Instruction pointer (RIP)
    genCst(X86Reg.IP, "X86Reg.IP", 5, 64);

    // Floating-point registers (x87)
    genCst(X86Reg.FP, "X86Reg.FP", 0, 80);

    return decls.data;
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
Note: we assume that the base and index are both 64-bit registers
and that the memory operand always has a base register.
*/
struct X86Mem
{
    /// Base register number
    uint8_t baseRegNo; 

    /// Index register number
    uint8_t idxRegNo;

    /// Memory location size
    uint8_t size;

    /// Index scale value, zero if not using an index
    uint8_t scale;

    /// Constant displacement from the base, not scaled
    int32_t disp; 

    this(
        size_t size, 
        X86Reg base, 
        int32_t disp    = 0, 
        size_t scale    = 0,
        X86Reg index    = RAX,
    )
    {
        assert (
            base.size is 64 &&
            index.size is 64,
            "base and index must be 64-bit registers"
        );

        this.size       = cast(uint8_t)size;
        this.baseRegNo  = base.regNo;
        this.disp       = disp;
        this.idxRegNo = index.regNo;
        this.scale      = cast(uint8_t)scale;
    }

    /**
    Equality comparison operator
    */
    bool opEquals(X86Mem that) const
    {
        return (
            this.baseRegNo is that.baseRegNo &&
            this.idxRegNo is that.idxRegNo &&
            this.disp is that.disp &&
            this.size is that.size &&
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

        switch (this.size)
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
        str ~= X86Reg(X86Reg.GP, this.baseRegNo, 64).toString();

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
            str ~= X86Reg(X86Reg.GP, this.idxRegNo, 64).toString();
        }

        return '[' ~ str ~ ']';
    }

    /**
    Test if there is an index register
    */
    bool hasIndex() const
    {
        return (scale != 0);
    }

    /**
    Test if the REX prefix is needed to encode this operand
    */
    bool rexNeeded() const
    {
        return (baseRegNo > 7) || (hasIndex && idxRegNo > 7);
    }

    /**
    Test if an SIB byte is needed to encode this operand
    */
    bool sibNeeded() const
    {
        return (
            this.scale != 0 ||
            this.baseRegNo == ESP.regNo ||
            this.baseRegNo == RSP.regNo ||
            this.baseRegNo == R12.regNo
        );
    }

    /**
    Compute the size of the displacement field needed
    */
    size_t dispSize() const
    {
        // FIXME
        // If using RIP as the base, use disp32
        //if (baseRegNo == RIP.regNo)
        //    return 32;

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
        if (baseRegNo == EBP.regNo || baseRegNo == RBP.regNo || baseRegNo == R13.regNo)
            return 8;

        return 0;
    }
}

/**
IP-relative memory location
*/
// TODO: reimplement without inheritance, when needed
// just store an X86Mem inside
// or modify X86Mem to support IP-relative mode
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

/**
Polymorphic X86 operand wrapper
*/
struct X86Opnd
{
    union
    {
        X86Reg reg;
        X86Imm imm;
        X86Mem mem;
    }

    enum Kind : uint8_t
    {
        NONE,
        REG,
        IMM,
        MEM,
        IPREL  
    }

    Kind kind;

    static immutable X86Opnd NONE = X86Opnd(Kind.NONE);

    this(Kind k) { assert (k is Kind.NONE); kind = k; }
    this(X86Reg r) { reg = r; kind = Kind.REG; }
    this(X86Imm i) { imm = i; kind = Kind.IMM; }
    this(X86Mem m) { mem = m; kind = Kind.MEM; }

    /// Memory operand constructor
    this(
        size_t size, 
        X86Reg base, 
        int32_t disp    = 0, 
        size_t scale    = 0,
        X86Reg index    = RAX,
    )
    {
        this(X86Mem(size, base, disp, scale, index));
    }

    /// Immediate constructor
    this(uint64_t i) { imm = X86Imm(i); kind = Kind.IMM; }

    string toString() const
    {
        switch (kind)
        {
            case Kind.REG: return reg.toString();
            case Kind.IMM: return imm.toString();
            case Kind.MEM: return mem.toString();

            default:
            assert (false);
        }
    }

    bool isNone() const { return kind is Kind.NONE; }
    bool isReg() const { return kind is Kind.REG; }
    bool isImm() const { return kind is Kind.IMM; }
    bool isMem() const { return kind is Kind.MEM; }

    bool isXMM() const { return kind is Kind.REG && reg.type is X86Reg.XMM; }
    bool isGPR() const { return kind is Kind.REG && reg.type is X86Reg.GP; }
    bool isGPR32() const { return isGPR && reg.size is 32; }
    bool isGPR64() const { return isGPR && reg.size is 64; }
    bool isMem32() const { return isMem && mem.size is 32; }
    bool isMem64() const { return isMem && mem.size is 64; }

    bool rexNeeded()
    {
        return (kind is Kind.REG && reg.rexNeeded) || (kind is Kind.MEM && mem.rexNeeded);
    }

    bool sibNeeded()
    {
        return (kind is Kind.MEM && mem.sibNeeded);
    }
}

/**
Write the REX byte
*/
void writeREX(
    ASMBlock cb, 
    bool wFlag,
    uint8_t regNo, 
    uint8_t idxRegNo = 0,
    uint8_t rmRegNo = 0
)
{
    // 0 1 0 0 w r x b
    // w - 64-bit operand size flag
    // r - MODRM.reg extension
    // x - SIB.index extension
    // b - MODRM.rm or SIB.base extension

    auto w = wFlag? 1:0;
    auto r = (regNo & 8)? 1:0;
    auto x = (idxRegNo & 8)? 1:0;
    auto b = (rmRegNo & 8)? 1:0;

    // Encode and write the REX byte
    auto rexByte = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
    cb.writeByte(cast(byte)rexByte);
}

/**
Write an opcode byte with an embedded register operand
*/
void writeOpcode(ASMBlock cb, ubyte opcode, X86Reg rOpnd)
{
    // Write the reg field into the opcode byte
    uint8_t opByte = opcode | (rOpnd.regNo & 7);
    cb.writeByte(opByte);
}

/**
Encode a single operand RM instruction
*/
void writeRMInstr(
    char rmOpnd, 
    ubyte opExt, 
    opcode...)
(ASMBlock cb, bool szPref, bool rexW, X86Opnd opnd0, X86Opnd opnd1)
{
    static assert (opcode.length > 0 && opcode.length <= 3);

    // Flag to indicate the REX prefix is needed
    bool rexNeeded = rexW || opnd0.rexNeeded || opnd1.rexNeeded;

    // Flag to indicate SIB byte is needed
    bool sibNeeded = opnd0.sibNeeded || opnd1.sibNeeded;

    // r and r/m operands
    X86Reg* rOpnd = null;
    X86Mem* rmOpndM = null;
    X86Reg* rmOpndR = null;

    switch (opnd0.kind)
    {
        case X86Opnd.Kind.REG:
        if (rmOpnd is 'l')
            rmOpndR = &opnd0.reg;
        else
            rOpnd = &opnd0.reg;
        break;

        case X86Opnd.Kind.MEM:
        if (rmOpnd is 'l')
            rmOpndM = &opnd0.mem;
        else
            assert (false);
        break;

        default:
        assert (false);
    }

    switch (opnd1.kind)
    {
        case X86Opnd.Kind.REG:
        if (rmOpnd is 'r')
            rmOpndR = &opnd1.reg;
        else
            rOpnd = &opnd1.reg;
        break;

        case X86Opnd.Kind.MEM:
        if (rmOpnd is 'r')
            rmOpndM = &opnd1.mem;
        else
            assert (false);
        break;

        case X86Opnd.Kind.NONE:
        break;

        default:
        assert (false, "invalid second operand");
    }

    // Add the operand-size prefix, if needed
    if (szPref == true)
        cb.writeByte(0x66);

    /*
    // Write the prefix bytes to the code block
    codeBlock.writeBytes(enc.prefix);
    */

    // Add the REX prefix, if needed
    if (rexNeeded)
    {
        // 0 1 0 0 w r x b
        // w - 64-bit operand size flag
        // r - MODRM.reg extension
        // x - SIB.index extension
        // b - MODRM.rm or SIB.base extension

        uint w = rexW? 1:0;

        uint r;
        if (rOpnd)
            r = (rOpnd.regNo & 8)? 1:0;
        else
            r = 0;

        uint x;
        if (sibNeeded && rmOpndM.hasIndex)
            x = (rmOpndM.idxRegNo & 8)? 1:0;
        else
            x = 0;

        uint b;
        if (rmOpndR)
            b = (rmOpndR.regNo & 8)? 1:0;
        else if (rmOpndM)
            b = (rmOpndM.baseRegNo & 8)? 1:0;
        else
            b = 0;

        // Encode and write the REX byte
        auto rexByte = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
        cb.writeByte(cast(byte)rexByte);
    }

    // Write the opcode bytes to the code block
    cb.writeBytes(opcode);

    // MODRM.mod (2 bits)
    // MODRM.reg (3 bits)
    // MODRM.rm  (3 bits)

    assert (
        !(opExt != 0xFF && rOpnd),
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
        // FIXME
        if (rmOpndM.dispSize == 0/* || rmOpndM.baseRegNo == RIP.regNo*/)
            mod = 0;
        else if (rmOpndM.dispSize == 8)
            mod = 1;
        else if (rmOpndM.dispSize == 32)
            mod = 2;
    }

    // Encode the reg field
    int reg;
    if (opExt != 0xFF)
        reg = opExt;
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
        // FIXME
        /*else if (rmOpndM.baseRegNo == RIP.regNo)
            rm = 5;*/
        else
            rm = rmOpndM.baseRegNo & 7;
    }

    // Encode and write the ModR/M byte
    auto rmByte = (mod << 6) + (reg << 3) + (rm);
    cb.writeByte(cast(ubyte)rmByte);

    //writefln("rmByte: %s", rmByte);

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
            case 0: assert (!rmOpndM.hasIndex); scale = 0; break;
            case 1: scale = 0; break;
            case 2: scale = 1; break;
            case 4: scale = 2; break;
            case 8: scale = 3; break;
            default: assert (false, "invalid SIB scale");
        }

        // Encode the index value
        int index;
        if (rmOpndM.hasIndex is false)
            index = 4;
        else
            index = rmOpndM.idxRegNo & 7;

        // Encode the base register
        auto base = rmOpndM.baseRegNo & 7;

        // Encode and write the SIB byte
        auto sibByte = (scale << 6) + (index << 3) + (base);
        cb.writeByte(cast(uint8_t)sibByte);
    }

    // Add the displacement size
    if (rmOpndM && rmOpndM.dispSize != 0)
        cb.writeInt(rmOpndM.disp, rmOpndM.dispSize);
}

/**
Encode an add-like RM instruction with multiple possible encodings
*/
void writeRMMulti(
    string mnem, 
    ubyte opMemReg8, 
    ubyte opMemRegPref, 
    ubyte opRegMem8, 
    ubyte opRegMemPref,
    ubyte opMemImm8, 
    ubyte opMemImmSml,
    ubyte opMemImmLrg,
    ubyte opExtImm
)
(ASMBlock cb, X86Opnd opnd0, X86Opnd opnd1)
{
    // Write a disassembly string
    if (!opnd1.isNone)
        cb.writeASM(mnem, opnd0, opnd1);
    else
        cb.writeASM(mnem, opnd0);

    // Check the size of opnd0
    size_t opndSize;
    if (opnd0.isReg)
        opndSize = opnd0.reg.size;
    else if (opnd0.isMem)
        opndSize = opnd0.mem.size;
    else
        assert (false, "invalid first operand");    

    // Check the size of opnd1
    if (opnd1.isReg)
        assert (opnd1.reg.size is opndSize, "operand size mismatch");
    else if (opnd1.isMem)
        assert (opnd1.mem.size is opndSize, "operand size mismatch");
    else if (opnd1.isImm)
        assert (opnd1.imm.immSize <= opndSize, "immediate too large for dst");

    assert (opndSize is 8 || opndSize is 16 || opndSize is 32 || opndSize is 64);
    auto szPref = opndSize is 16;
    auto rexW = opndSize is 64;

    // R/M + Reg
    if ((opnd0.isMem && opnd1.isReg) ||
        (opnd0.isReg && opnd1.isReg))
    {
        if (opndSize is 8)
            cb.writeRMInstr!('l', 0xFF, opMemReg8)(false, false, opnd0, opnd1);
        else
            cb.writeRMInstr!('l', 0xFF, opMemRegPref)(szPref, rexW, opnd0, opnd1);
    }

    // Reg + R/M
    else if (opnd0.isReg && opnd1.isMem)
    {
        if (opndSize is 8)
            cb.writeRMInstr!('r', 0xFF, opRegMem8)(false, false, opnd0, opnd1);
        else
            cb.writeRMInstr!('r', 0xFF, opRegMemPref)(szPref, rexW, opnd0, opnd1);
    }

    // R/M + Imm
    else if (opnd1.isImm)
    {
        auto imm = opnd1.imm;

        // 8-bit immediate
        if (imm.immSize <= 8)
        {
            if (opndSize is 8)
                cb.writeRMInstr!('l', opExtImm, opMemImm8)(false, false, opnd0, X86Opnd.NONE);
            else
                cb.writeRMInstr!('l', opExtImm, opMemImmSml)(szPref, rexW, opnd0, X86Opnd.NONE);
            cb.writeInt(imm.imm, 8);
        }

        // 32-bit immediate
        else if (imm.immSize <= 32)
        {
            assert (imm.immSize <= opndSize, "immediate too large for dst");

            cb.writeRMInstr!('l', opExtImm, opMemImmLrg)(szPref, rexW, opnd0, X86Opnd.NONE);
            cb.writeInt(imm.imm, min(opndSize, 32));
        }

        // Immediate too large
        else
        {
            assert (false, "immediate value too large");
        }
    }

    // Invalid operands
    else
    {
        assert (
            false, 
            "invalid operand combination for " ~ mnem ~ ":\n" ~
            opnd0.toString() ~ "\n" ~
            opnd1.toString()
        );
    }
}

/**
Encode an XMM instruction on 64-bit XMM/M operands
*/
void writeXMM64(
    wstring mnem, 
    ubyte prefix, 
    ubyte opRegMem0, 
    ubyte opRegMem1
)
(ASMBlock cb, X86Opnd opnd0, X86Opnd opnd1)
{
    // Write a disassembly string
    cb.writeASM(mnem, opnd0, opnd1);

    assert (
        opnd0.isXMM,
        "invalid first operand"
    );

    assert (
        opnd1.isXMM || (opnd1.isMem && opnd1.mem.size is 64),
        "invalid second operand"
    );

    cb.writeByte(prefix);
    cb.writeRMInstr!('r', 0xFF, opRegMem0, opRegMem1)(false, false, opnd0, opnd1);
}

/**
Encode a mul-like single-operand RM instruction
*/
void writeRMUnary(
    wstring mnem, 
    ubyte opMemReg8, 
    ubyte opMemRegPref,
    ubyte opExt
)
(ASMBlock cb, X86Opnd opnd)
{
    // Write a disassembly string
    cb.writeASM(mnem, opnd);

    // Check the size of opnd0
    size_t opndSize;
    if (opnd.isReg)
        opndSize = opnd.reg.size;
    else if (opnd.isMem)
        opndSize = opnd.mem.size;
    else
        assert (false, "invalid first operand");    

    assert (opndSize is 8 || opndSize is 16 || opndSize is 32 || opndSize is 64);
    auto szPref = opndSize is 16;
    auto rexW = opndSize is 64;

    if (opndSize is 8)
        cb.writeRMInstr!('l', opExt, opMemReg8)(false, false, opnd, X86Opnd.NONE);
    else
        cb.writeRMInstr!('l', opExt, opMemRegPref)(szPref, rexW, opnd, X86Opnd.NONE);
}

/// add - Integer addition
alias writeRMMulti!(
    "add",
    0x00, // opMemReg8
    0x01, // opMemRegPref
    0x02, // opRegMem8
    0x03, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x00  // opExtImm
) add;

/// add - Add with register and immediate operand
void add(ASMBlock as, X86Reg dst, int64_t imm)
{
    assert (imm >= int32_t.min && imm <= int32_t.max);

    // TODO: optimize encoding
    return add(as, X86Opnd(dst), X86Opnd(imm));
}

// addsd - Add scalar double
alias writeXMM64!(
    "addsd", 
    0xF2, // prefix
    0x0F, // opRegMem0
    0x58  // opRegMem1
) addsd;

/// and - Bitwise AND
alias writeRMMulti!(
    "and",
    0x20, // opMemReg8
    0x21, // opMemRegPref
    0x22, // opRegMem8
    0x23, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x04  // opExtImm
) and;

// TODO: relative call encoding
// For this, we will need a patchable 32-bit offset
//Enc(opnds=['rel32'], opcode=[0xE8]),
//void call(Assembler as, BlockVersion???);

/// call - Call to label with 32-bit offset
void call(ASMBlock cb, Label label)
{
    cb.writeASM("call", label);

    // Write the opcode
    cb.writeByte(0xE8);

    // Add a reference to the label
    cb.addLabelRef(label);

    // Relative 32-bit offset to be patched
    cb.writeInt(0, 32);
}

/// call - Indirect call with an R/M operand
void call(ASMBlock cb, X86Opnd opnd)
{
    cb.writeASM("call", opnd);
    cb.writeRMInstr!('l', 2, 0xFF)(false, false, opnd, X86Opnd.NONE);
}

/**
Encode a conditional move instruction
*/
void writeCmov(
    wstring mnem,
    ubyte opcode1)
(ASMBlock cb, X86Reg dst, X86Opnd src)
{
    cb.writeASM(mnem, dst, src);

    assert (src.isReg || src.isMem);
    auto szPref = dst.size is 16;
    auto rexW = dst.size is 64;

    cb.writeRMInstr!('r', 0xFF, 0x0F, opcode1)(szPref, rexW, X86Opnd(dst), src);
}

/// cmovcc - Conditional move
alias writeCmov!("cmova"  , 0x47) cmova;
alias writeCmov!("cmovae" , 0x43) cmovae;
alias writeCmov!("cmovb"  , 0x42) cmovb;
alias writeCmov!("cmovbe" , 0x46) cmovbe;
alias writeCmov!("cmovc"  , 0x42) cmovc;
alias writeCmov!("cmove"  , 0x44) cmove;
alias writeCmov!("cmovg"  , 0x4F) cmovg;
alias writeCmov!("cmovge" , 0x4D) cmovge;
alias writeCmov!("cmovl"  , 0x4C) cmovl;
alias writeCmov!("cmovle" , 0x4E) cmovle;
alias writeCmov!("cmovna" , 0x46) cmovna;
alias writeCmov!("cmovnae", 0x42) cmovnae;
alias writeCmov!("cmovnb" , 0x43) cmovnb;
alias writeCmov!("cmovnbe", 0x47) cmovnbe;
alias writeCmov!("cmovnc" , 0x43) cmovnc;
alias writeCmov!("cmovne" , 0x45) cmovne;
alias writeCmov!("cmovng" , 0x4E) cmovnge;
alias writeCmov!("cmovnge", 0x4C) cmovnge;
alias writeCmov!("cmovnl" , 0x4D) cmovnl;
alias writeCmov!("cmovnle", 0x4F) cmovnle;
alias writeCmov!("cmovno" , 0x41) cmovno;
alias writeCmov!("cmovnp" , 0x4B) cmovnp;
alias writeCmov!("cmovns" , 0x49) cmovns;
alias writeCmov!("cmovnz" , 0x45) cmovnz;
alias writeCmov!("cmovno" , 0x40) cmovo;
alias writeCmov!("cmovp"  , 0x4A) cmovp;
alias writeCmov!("cmovpe" , 0x4A) cmovpe;
alias writeCmov!("cmovpo" , 0x4B) cmovpo;
alias writeCmov!("cmovs"  , 0x48) cmovs;
alias writeCmov!("cmovz"  , 0x44) cmovz;

/// cmp - Compare and set flags
alias writeRMMulti!(
    "cmp",
    0x38, // opMemReg8
    0x39, // opMemRegPref
    0x3A, // opRegMem8
    0x3B, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x07  // opExtImm
) cmp;

/// cqo - Convert quadword to octaword
void cqo(ASMBlock cb)
{
    cb.writeBytes(0x48, 0x99);
}

//// cvtsd2si - Convert integer to scalar double
void cvtsd2si(ASMBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("cvtsd2si", dst, src);

    assert (dst.isGPR);
    assert (dst.reg.size is 32 || dst.reg.size is 64);
    assert (src.isXMM || src.isMem64);

    auto rexW = dst.reg.size is 64;

    cb.writeByte(0xF2);
    cb.writeRMInstr!('r', 0xFF, 0x0F, 0x2D)(false, rexW, dst, src);
}

//// cvtsi2sd - Convert integer to scalar double
void cvtsi2sd(ASMBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("cvtsi2sd", dst, src);

    //Enc(opnds=['xmm', 'r/m32'], prefix=[0xF2], opcode=[0x0F, 0x2A]),
    //Enc(opnds=['xmm', 'r/m64'], prefix=[0xF2], opcode=[0x0F, 0x2A]),

    assert (dst.isXMM);

    size_t opndSize;
    if (src.isReg)
        opndSize = src.reg.size;
    else if (src.isMem)
        opndSize = src.mem.size;
    else
        assert (false);
    assert (opndSize is 32 || opndSize is 64);
    auto rexW = opndSize is 64;

    cb.writeByte(0xF2);
    cb.writeRMInstr!('r', 0xFF, 0x0F, 0x2A)(false, rexW, dst, src);
}

// dec - Decrement integer by 1
alias writeRMUnary!(
    "dec", 
    0xFE, // opMemReg8 
    0xFF, // opMemRegPref
    0x01  // opExt
) dec;

// div - Unsigned integer division
alias writeRMUnary!(
    "div", 
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x06  // opExt
) div;

// div - Signed integer division
alias writeRMUnary!(
    "idiv", 
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x07  // opExt
) idiv;

/// imul - Signed integer multiplication with two operands
void imul(ASMBlock cb, X86Opnd opnd0, X86Opnd opnd1)
{
    cb.writeASM("imul", opnd0, opnd1);

    assert (opnd0.isReg, "invalid first operand");
    auto opndSize = opnd0.reg.size;

    // Check the size of opnd1
    if (opnd1.isReg)
        assert (opnd1.reg.size is opndSize, "operand size mismatch");
    else if (opnd1.isMem)
        assert (opnd1.mem.size is opndSize, "operand size mismatch");

    assert (opndSize is 16 || opndSize is 32 || opndSize is 64);
    auto szPref = opndSize is 16;
    auto rexW = opndSize is 64;

    cb.writeRMInstr!('r', 0xFF, 0x0F, 0xAF)(szPref, rexW, opnd0, opnd1);
}

/// imul - Signed integer multiplication with three operands (one immediate)
void imul(ASMBlock cb, X86Opnd opnd0, X86Opnd opnd1, X86Opnd opnd2)
{
    cb.writeASM("imul", opnd0, opnd1);

    assert (opnd0.isReg, "invalid first operand");
    auto opndSize = opnd0.reg.size;

    // Check the size of opnd1
    if (opnd1.isReg)
        assert (opnd1.reg.size is opndSize, "operand size mismatch");
    else if (opnd1.isMem)
        assert (opnd1.mem.size is opndSize, "operand size mismatch");

    assert (opndSize is 16 || opndSize is 32 || opndSize is 64);
    auto szPref = opndSize is 16;
    auto rexW = opndSize is 64;

    assert (opnd2.isImm, "invalid third operand");
    auto imm = opnd2.imm;

    // 8-bit immediate
    if (imm.immSize <= 8)
    {
        cb.writeRMInstr!('r', 0xFF, 0x6B)(szPref, rexW, opnd0, opnd1);
        cb.writeInt(imm.imm, 8);
    }

    // 32-bit immediate
    else if (imm.immSize <= 32)
    {
        assert (imm.immSize <= opndSize, "immediate too large for dst");
        cb.writeRMInstr!('r', 0xFF, 0x69)(szPref, rexW, opnd0, opnd1);
        cb.writeInt(imm.imm, min(opndSize, 32));
    }

    // Immediate too large
    else
    {
        assert (false, "immediate value too large");
    }
}

// inc - Increment integer by 1
alias writeRMUnary!(
    "inc", 
    0xFE, // opMemReg8 
    0xFF, // opMemRegPref
    0x00  // opExt
) inc;

/**
Encode a relative jump to a label (direct or conditional)
Note: this always encodes a 32-bit offset
*/
void writeJcc(string mnem, opcode...)(ASMBlock cb, Label label)
{
    cb.writeASM(mnem, label);

    // Write the opcode
    cb.writeBytes(opcode);

    // Add a reference to the label
    cb.addLabelRef(label);

    // Relative 32-bit offset to be patched
    cb.writeInt(0, 32);
}

/// jcc - Conditional relative jump to a label
alias writeJcc!("ja" , 0x0F, 0x87) ja;
alias writeJcc!("jae", 0x0F, 0x83) jae;
alias writeJcc!("jb" , 0x0F, 0x82) jb;
alias writeJcc!("jbe", 0x0F, 0x86) jbe;
alias writeJcc!("jc" , 0x0F, 0x82) jc;
alias writeJcc!("je" , 0x0F, 0x84) je;
alias writeJcc!("jg" , 0x0F, 0x8F) jg;
alias writeJcc!("jge", 0x0F, 0x8D) jge;
alias writeJcc!("jl" , 0x0F, 0x8C) jl;
alias writeJcc!("jle", 0x0F, 0x8E) jle;
alias writeJcc!("jna" , 0x0F, 0x86) jna;
alias writeJcc!("jnae", 0x0F, 0x82) jnae;
alias writeJcc!("jnb" , 0x0F, 0x83) jnb;
alias writeJcc!("jnbe", 0x0F, 0x87) jnbe;
alias writeJcc!("jnc" , 0x0F, 0x83) jnc;
alias writeJcc!("jne" , 0x0F, 0x85) jne;
alias writeJcc!("jng" , 0x0F, 0x8E) jng;
alias writeJcc!("jnge", 0x0F, 0x8C) jnge;
alias writeJcc!("jnl" , 0x0F, 0x8D) jnl;
alias writeJcc!("jnle", 0x0F, 0x8F) jnle;
alias writeJcc!("jno", 0x0F, 0x81) jno;
alias writeJcc!("jnp", 0x0F, 0x8b) jnp;
alias writeJcc!("jns", 0x0F, 0x89) jns;
alias writeJcc!("jnz", 0x0F, 0x85) jnz;
alias writeJcc!("jo" , 0x0F, 0x80) jo;
alias writeJcc!("jp" , 0x0F, 0x8A) jp;
alias writeJcc!("jpe", 0x0F, 0x8A) jpe;
alias writeJcc!("jpo", 0x0F, 0x8B) jpo;
alias writeJcc!("js" , 0x0F, 0x88) js;
alias writeJcc!("jz" , 0x0F, 0x84) jz;

/// jmp - Direct relative jump to label
alias writeJcc!("jmp", 0xE9) jmp;

/// jmp - Indirect jump near to an R/M operand
void jmp(ASMBlock cb, X86Opnd opnd)
{
    cb.writeASM("jmp", opnd);
    cb.writeRMInstr!('l', 4, 0xFF)(false, false, opnd, X86Opnd.NONE);
}

/// mov - Data move operation
void mov(ASMBlock cb, X86Opnd dst, X86Opnd src)
{
    // R/M + Imm
    if (src.isImm)
    {
        cb.writeASM("mov", dst, src);

        auto imm = src.imm;

        // R + Imm
        if (dst.isReg)
        {
            auto reg = dst.reg;
            auto dstSize = reg.size;
            assert (imm.immSize <= dstSize);

            if (dstSize is 16)
                cb.writeByte(0x66);
            if (reg.rexNeeded || dstSize is 64)
                cb.writeREX(dstSize is 64, 0, 0, reg.regNo);

            cb.writeOpcode((dstSize is 8)? 0xB0:0xB8, reg);

            cb.writeInt(imm.imm, dstSize);
        }  

        // M + Imm
        else if (dst.isMem)
        {
            auto dstSize = dst.reg.size;
            assert (imm.immSize <= dstSize);

            if (dstSize is 8)
                cb.writeRMInstr!('l', 0xFF, 0xC6)(false, false, dst, X86Opnd.NONE);
            else
                cb.writeRMInstr!('l', 0, 0xC7)(dstSize is 16, dstSize is 64, dst, X86Opnd.NONE);

            cb.writeInt(imm.imm, min(dstSize, 32));
        }

        else
        {
            assert (false);
        }
    }
    else
    {
        writeRMMulti!(
            "mov",
            0x88, // opMemReg8
            0x89, // opMemRegPref
            0x8A, // opRegMem8
            0x8B, // opRegMemPref
            0xC6, // opMemImm8
            0xFF, // opMemImmSml (not available)
            0xFF, // opMemImmLrg
            0xFF  // opExtImm
        )(cb, dst, src);
    }
}

/// mov - Move an immediate into a register
void mov(ASMBlock cb, X86Reg reg, X86Imm imm)
{
    // TODO: more optimized code for this case
    cb.mov(X86Opnd(reg), X86Opnd(imm));
}

/// mov - Move an immediate into a register
void mov(ASMBlock cb, X86Reg reg, int64_t imm)
{
    // TODO: more optimized code for this case
    cb.mov(X86Opnd(reg), X86Opnd(imm));
}

/// mov - Register to register move
void mov(ASMBlock cb, X86Reg dst, X86Reg src)
{
    // TODO: more optimized code for this case
    cb.mov(X86Opnd(dst), X86Opnd(src));
}

/// movq - Move quadword
void movq(ASMBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("movq", dst, src);

    if (dst.isXMM)
    {
        assert (src.isGPR64 || src.isMem64);
        cb.writeByte(0x66);
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0x6E)(false, true, dst, src);
    }
    else if (dst.isGPR64 || dst.isMem64)
    {
        assert (src.isXMM);
        cb.writeByte(0x66);
        cb.writeRMInstr!('l', 0xFF, 0x0F, 0x7E)(false, true, dst, src);
    }
    else
    {
        assert (false, "invalid dst operand");
    }
}

/// movsd - Move scalar double to/from XMM
void movsd(ASMBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("movsd", dst, src);

    if (dst.isXMM)
    {
        assert (src.isXMM || src.isMem64);
        cb.writeByte(0xF2);
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0x10)(false, false, dst, src);
    }
    else if (dst.isMem64)
    {
        assert (src.isXMM);
        cb.writeByte(0xF2);
        cb.writeRMInstr!('l', 0xFF, 0x0F, 0x11)(false, false, dst, src);
    }
    else
    {
        assert (false, "invalid dst operand");
    }
}

/// movsx - Move with sign extension
void movsx(ASMBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("movsx", dst, src);

    size_t dstSize;
    if (dst.isReg)
        dstSize = dst.reg.size;
    else
        assert (false);

    size_t srcSize;
    if (src.isReg)
        srcSize = src.reg.size;
    else if (src.isMem)
        srcSize = src.mem.size;
    else
        assert (false);

    assert (srcSize < dstSize);

    if (srcSize is 8)
    {
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0xBE)(dstSize is 16, dstSize is 64, dst, src);
    }
    else if (srcSize is 16)
    {
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0xBF)(dstSize is 16, dstSize is 64, dst, src);
    }
    else if (srcSize is 32)
    {
        cb.writeRMInstr!('r', 0xFF, 0x063)(false, true, dst, src);
    }
    else
    {
        assert (false);
    }
}

/// movzx - Move with zero extension (unsigned)
void movzx(ASMBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("movzx", dst, src);

    size_t dstSize;
    if (dst.isReg)
        dstSize = dst.reg.size;
    else
        assert (false);

    size_t srcSize;
    if (src.isReg)
        srcSize = src.reg.size;
    else if (src.isMem)
        srcSize = src.mem.size;
    else
        assert (false);

    assert (srcSize < dstSize);

    if (srcSize is 8)
    {
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0xB6)(dstSize is 16, dstSize is 64, dst, src);
    }
    else if (srcSize is 16)
    {
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0xB7)(dstSize is 16, dstSize is 64, dst, src);
    }
    else
    {
        assert (false);
    }
}

// mul - Unsigned integer multiply
alias writeRMUnary!(
    "mul", 
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x04  // opExt
) mul;

// mulsd - Multiply scalar double
alias writeXMM64!(
    "mulsd", 
    0xF2, // prefix
    0x0F, // opRegMem0
    0x59  // opRegMem1
) mulsd;

// neg - Integer negation (multiplication by -1)
alias writeRMUnary!(
    "neg",
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x03  // opExt
) neg;

/// nop - Noop, one or multiple bytes long
void nop(ASMBlock cb, size_t length = 1)
{
    if (length > 0)
        cb.writeASM("nop" ~ to!string(length));

    switch (length)
    {
        case 0:
        break;

        case 1:
        cb.writeByte(0x90);
        break;

        case 2:
        cb.writeBytes(0x89, 0xf6);
        break;

        case 3:
        cb.writeBytes(0x8d,0x76,0x00);
        break;

        case 4:
        cb.writeBytes(0x8d,0x74,0x26,0x00);
        break;

        case 5:
        cb.nop(1); cb.nop(4);
        break;

        case 6:
        cb.writeBytes(0x8d,0xb6,0x00,0x00,0x00,0x00);
        break;

        case 7:
        cb.writeBytes(0x8d,0xb4,0x26,0x00,0x00,0x00,0x00);
        break;

        case 8:
        cb.nop(8); cb.nop(1); cb.nop(7);
        break;

        default:
        assert (false);
    }
}

// not - Bitwise NOT
alias writeRMUnary!(
    "not",
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x02  // opExt
) not;

/// or - Bitwise OR
alias writeRMMulti!(
    "or",
    0x08, // opMemReg8
    0x09, // opMemRegPref
    0x0A, // opRegMem8
    0x0B, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x01  // opExtImm
) or;

/// push - Push a register on the stack
void push(ASMBlock cb, immutable X86Reg reg)
{
    assert (reg.size is 64);

    cb.writeASM("push", reg); 

    if (reg.rexNeeded)
        cb.writeREX(false, 0, 0, reg.regNo);
    cb.writeOpcode(0x50, reg);
}

/// pop - Pop a register off the stack
void pop(ASMBlock cb, immutable X86Reg reg)
{
    assert (reg.size is 64);

    cb.writeASM("pop", reg);

    if (reg.rexNeeded)
        cb.writeREX(false, 0, 0, reg.regNo);
    cb.writeOpcode(0x58, reg);
}

/// ret - Return from call, popping only the return address
void ret(ASMBlock cb)
{
    cb.writeASM("ret");
    cb.writeByte(0xC3);
}

/**
Encode a single-operand shift instruction
*/
void writeShift(
    wstring mnem, 
    ubyte opMemOnePref,
    ubyte opMemClPref,
    ubyte opMemImmPref,
    ubyte opExt
)
(ASMBlock cb, X86Opnd opnd0, X86Opnd opnd1)
{
    // Write a disassembly string
    cb.writeASM(mnem, opnd0, opnd1);

    // Check the size of opnd0
    size_t opndSize;
    if (opnd0.isReg)
        opndSize = opnd0.reg.size;
    else if (opnd0.isMem)
        opndSize = opnd0.mem.size;
    else
        assert (false, "invalid first operand");   
    
    assert (opndSize is 16 || opndSize is 32 || opndSize is 64);
    auto szPref = opndSize is 16;
    auto rexW = opndSize is 64;

    if (opnd1.isImm)
    {
        if (opnd1.imm.imm == 1)
        {
            cb.writeRMInstr!('l', opExt, opMemOnePref)(szPref, rexW, opnd0, X86Opnd.NONE);
        }
        else
        {
            assert (opnd1.imm.immSize <= 8);
            cb.writeRMInstr!('l', opExt, opMemImmPref)(szPref, rexW, opnd0, X86Opnd.NONE);
            cb.writeByte(cast(ubyte)opnd1.imm.imm);
        }
    }    
    else if (opnd1.isReg && opnd1.reg == CL)
    {
        cb.writeRMInstr!('l', opExt, opMemClPref)(szPref, rexW, opnd0, opnd1);
    }
    else
    {
        assert (false);
    }
}

/// sal - Shift arithmetic left
alias writeShift!(
    "sal", 
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x04
) sal;

/// shl - Shift logical left
alias writeShift!(
    "shl", 
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x04
) shl;

/// sar - Shift arithmetic right (signed)
alias writeShift!(
    "sar", 
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x07
) sar;

/// shr - Shift logical right (unsigned)
alias writeShift!(
    "shr", 
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x05
) shr;

// sqrtsd - Square root of scalar double (SSE2)
alias writeXMM64!(
    "sqrtsd", 
    0xF2, // prefix
    0x0F, // opRegMem0
    0x51  // opRegMem1
) sqrtsd;

/// sub - Integer subtraction
alias writeRMMulti!(
    "sub",
    0x28, // opMemReg8
    0x29, // opMemRegPref
    0x2A, // opRegMem8
    0x2B, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x05  // opExtImm
) sub;

// subsd - Subtract scalar double
alias writeXMM64!(
    "subsd", 
    0xF2, // prefix
    0x0F, // opRegMem0
    0x5C  // opRegMem1
) subsd;

// ucomisd - Unordered compare scalar double
alias writeXMM64!(
    "ucomisd", 
    0x66, // prefix
    0x0F, // opRegMem0
    0x2E  // opRegMem1
) ucomisd;

/// xor - Exclusive bitwise OR
alias writeRMMulti!(
    "xor",
    0x30, // opMemReg8
    0x31, // opMemRegPref
    0x32, // opRegMem8
    0x33, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x06  // opExtImm
) xor;

