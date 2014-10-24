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
import std.bitmanip;
import std.algorithm;
import jit.codeblock;

// Number of x86 registers
const NUM_REGS = 16;

/**
Representation of an x86 register
*/
struct X86Reg
{
    alias Type = uint8_t;
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
            regNo < NUM_REGS,
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
    X86Reg reg(size_t numBits = 0) const
    {
        if (numBits is 0 || numBits is this.size)
            return this;

        return X86Reg(this.type, this.regNo, numBits);
    }

    /**
    Get an operand object for a register of the requested size
    */
    X86Opnd opnd(size_t numBits = 0) const
    {
        return X86Opnd(reg(numBits));
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

    for (ubyte regNo = 0; regNo < NUM_REGS; ++regNo)
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
    // Bit field for compact encoding
    mixin(bitfields!(
        /// Memory location size
        uint, "size"     , 10,

        /// Base register number
        uint, "baseRegNo", 4,

        /// Index register number
        uint, "idxRegNo" , 4,

        /// SIB scale exponent value (power of two)
        uint, "scaleExp" , 2,

        /// Has index register flag
        bool, "hasIdx"   , 1,

        /// IP-relative addressing flag
        bool, "isIPRel"  , 1,

        /// Padding bits
        uint, "", 10
    ));

    /// Constant displacement from the base, not scaled
    int32_t disp; 

    this(
        size_t size,
        X86Reg base,
        int64_t disp    = 0,
        size_t scale    = 0,
        X86Reg index    = RAX,
    )
    {
        assert (
            base.size is 64 &&
            index.size is 64,
            "base and index must be 64-bit registers"
        );

        assert (
            disp >= int32_t.min && disp <= int32_t.max,
            "disp value out of bounds"
        );

        this.size       = cast(uint8_t)size;
        this.baseRegNo  = base.regNo;
        this.disp       = cast(int32_t)disp;
        this.idxRegNo   = index.regNo;
        this.hasIdx     = scale !is 0;
        this.isIPRel    = base.type is X86Reg.IP;

        switch (scale)
        {
            case 0: break;
            case 1: this.scaleExp = 0; break;
            case 2: this.scaleExp = 1; break;
            case 4: this.scaleExp = 2; break;
            case 8: this.scaleExp = 3; break;
            default: assert (false);
        }
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
        str ~= X86Reg(isIPRel? X86Reg.IP:X86Reg.GP, this.baseRegNo, 64).toString();

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

        if (this.hasIdx)
        {
            if (str != "")
                str ~= " + ";
            if (this.scaleExp !is 0)
                str ~= to!string(1 << this.scaleExp) ~ " * ";
            str ~= X86Reg(X86Reg.GP, this.idxRegNo, 64).toString();
        }

        return '[' ~ str ~ ']';
    }

    /**
    Test if the REX prefix is needed to encode this operand
    */
    bool rexNeeded() const
    {
        return (baseRegNo > 7) || (hasIdx && idxRegNo > 7);
    }

    /**
    Test if an SIB byte is needed to encode this operand
    */
    bool sibNeeded() const
    {
        return (
            this.hasIdx ||
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
        // If using RIP as the base, use disp32
        if (isIPRel)
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
        int64_t disp    = 0,
        size_t scale    = 0,
        X86Reg index    = RAX,
    )
    {
        this(X86Mem(size, base, disp, scale, index));
    }

    /// Immediate constructor
    this(int64_t i) { imm = X86Imm(i); kind = Kind.IMM; }

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
    CodeBlock cb, 
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
void writeOpcode(CodeBlock cb, ubyte opcode, X86Reg rOpnd)
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
(CodeBlock cb, bool szPref, bool rexW, X86Opnd opnd0, X86Opnd opnd1)
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
            assert (false, "mem opnd but right-opnd is not r/m");
        break;

        case X86Opnd.Kind.NONE:
        break;

        default:
        assert (false, "invalid second operand: " ~ opnd1.toString());
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
        if (sibNeeded && rmOpndM.hasIdx)
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
        if (rmOpndM.dispSize == 0 || rmOpndM.isIPRel)
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
        int scale = rmOpndM.scaleExp;

        // Encode the index value
        int index;
        if (rmOpndM.hasIdx is false)
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
(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1)
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
        assert (false, "invalid first operand for " ~ mnem ~ ": " ~ opnd0.toString());

    // Check the size of opnd1
    if (opnd1.isReg)
        assert (opnd1.reg.size is opndSize, "operand size mismatch");
    else if (opnd1.isMem)
        assert (opnd1.mem.size is opndSize, "operand size mismatch for " ~ mnem);
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
(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1)
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

    static if (prefix != 0xFF)
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
(CodeBlock cb, X86Opnd opnd)
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
alias add = writeRMMulti!(
    "add",
    0x00, // opMemReg8
    0x01, // opMemRegPref
    0x02, // opRegMem8
    0x03, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x00  // opExtImm
);

/// add - Add with register and immediate operand
void add(CodeBlock as, X86Reg dst, int64_t imm)
{
    assert (imm >= int32_t.min && imm <= int32_t.max);

    // TODO: optimize encoding
    return add(as, X86Opnd(dst), X86Opnd(imm));
}

/// addsd - Add scalar double
alias addsd = writeXMM64!(
    "addsd",
    0xF2, // prefix
    0x0F, // opRegMem0
    0x58  // opRegMem1
);

/// and - Bitwise AND
alias and = writeRMMulti!(
    "and",
    0x20, // opMemReg8
    0x21, // opMemRegPref
    0x22, // opRegMem8
    0x23, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x04  // opExtImm
);

// TODO: relative call encoding
// For this, we will need a patchable 32-bit offset
//Enc(opnds=['rel32'], opcode=[0xE8]),
//void call(Assembler as, BlockVersion???);

/// call - Call to label with 32-bit offset
void call(CodeBlock cb, Label label)
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
void call(CodeBlock cb, X86Opnd opnd)
{
    cb.writeASM("call", opnd);
    cb.writeRMInstr!('l', 2, 0xFF)(false, false, opnd, X86Opnd.NONE);
}

/// call - Indirect call with a register operand
void call(CodeBlock cb, X86Reg reg)
{
    cb.writeASM("call", reg);
    cb.writeRMInstr!('l', 2, 0xFF)(false, false, X86Opnd(reg), X86Opnd.NONE);
}

/**
Encode a conditional move instruction
*/
void writeCmov(
    wstring mnem,
    ubyte opcode1)
(CodeBlock cb, X86Reg dst, X86Opnd src)
{
    cb.writeASM(mnem, dst, src);

    assert (src.isReg || src.isMem);
    auto szPref = dst.size is 16;
    auto rexW = dst.size is 64;

    cb.writeRMInstr!('r', 0xFF, 0x0F, opcode1)(szPref, rexW, X86Opnd(dst), src);
}

/// cmovcc - Conditional move
alias cmova = writeCmov!("cmova"  , 0x47);
alias cmovae = writeCmov!("cmovae" , 0x43);
alias cmovb = writeCmov!("cmovb"  , 0x42);
alias cmovbe = writeCmov!("cmovbe" , 0x46);
alias cmovc = writeCmov!("cmovc"  , 0x42);
alias cmove = writeCmov!("cmove"  , 0x44);
alias cmovg = writeCmov!("cmovg"  , 0x4F);
alias cmovge = writeCmov!("cmovge" , 0x4D);
alias cmovl = writeCmov!("cmovl"  , 0x4C);
alias cmovle = writeCmov!("cmovle" , 0x4E);
alias cmovna = writeCmov!("cmovna" , 0x46);
alias cmovnae = writeCmov!("cmovnae", 0x42);
alias cmovnb = writeCmov!("cmovnb" , 0x43);
alias cmovnbe = writeCmov!("cmovnbe", 0x47);
alias cmovnc = writeCmov!("cmovnc" , 0x43);
alias cmovne = writeCmov!("cmovne" , 0x45);
alias cmovnge = writeCmov!("cmovng" , 0x4E);
alias cmovnge = writeCmov!("cmovnge", 0x4C);
alias cmovnl = writeCmov!("cmovnl" , 0x4D);
alias cmovnle = writeCmov!("cmovnle", 0x4F);
alias cmovno = writeCmov!("cmovno" , 0x41);
alias cmovnp = writeCmov!("cmovnp" , 0x4B);
alias cmovns = writeCmov!("cmovns" , 0x49);
alias cmovnz = writeCmov!("cmovnz" , 0x45);
alias cmovo = writeCmov!("cmovno" , 0x40);
alias cmovp = writeCmov!("cmovp"  , 0x4A);
alias cmovpe = writeCmov!("cmovpe" , 0x4A);
alias cmovpo = writeCmov!("cmovpo" , 0x4B);
alias cmovs = writeCmov!("cmovs"  , 0x48);
alias cmovz = writeCmov!("cmovz"  , 0x44);

/// cmp - Compare and set flags
alias cmp = writeRMMulti!(
    "cmp",
    0x38, // opMemReg8
    0x39, // opMemRegPref
    0x3A, // opRegMem8
    0x3B, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x07  // opExtImm
);

/// cdq - Convert doubleword to quadword
void cdq(CodeBlock cb)
{
    cb.writeASM("cdq");
    cb.writeBytes(0x99);
}

/// cqo - Convert quadword to octaword
void cqo(CodeBlock cb)
{
    cb.writeASM("cqo");
    cb.writeBytes(0x48, 0x99);
}

//// cvtsd2si - Convert scalar double to integer with rounding
void cvtsd2si(CodeBlock cb, X86Opnd dst, X86Opnd src)
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
void cvtsi2sd(CodeBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("cvtsi2sd", dst, src);

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

//// cvttsd2si - Convert scalar double to integer with truncation
void cvttsd2si(CodeBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("cvttsd2si", dst, src);

    assert (dst.isGPR);
    assert (dst.reg.size is 32 || dst.reg.size is 64);
    assert (src.isXMM || src.isMem64);

    auto rexW = dst.reg.size is 64;

    cb.writeByte(0xF2);
    cb.writeRMInstr!('r', 0xFF, 0x0F, 0x2C)(false, rexW, dst, src);
}

// dec - Decrement integer by 1
alias dec = writeRMUnary!(
    "dec", 
    0xFE, // opMemReg8 
    0xFF, // opMemRegPref
    0x01  // opExt
);

// div - Unsigned integer division
alias div = writeRMUnary!(
    "div", 
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x06  // opExt
);

/// divsd - Divide scalar double
alias divsd = writeXMM64!(
    "divsd",
    0xF2, // prefix
    0x0F, // opRegMem0
    0x5E  // opRegMem1
);

// idiv - Signed integer division
alias idiv = writeRMUnary!(
    "idiv", 
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x07  // opExt
);

/// imul - Signed integer multiplication with two operands
void imul(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1)
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
void imul(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1, X86Opnd opnd2)
{
    cb.writeASM("imul", opnd0, opnd1, opnd2);

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
alias inc = writeRMUnary!(
    "inc", 
    0xFE, // opMemReg8 
    0xFF, // opMemRegPref
    0x00  // opExt
);

/**
Encode a relative jump to a label (direct or conditional)
Note: this always encodes a 32-bit offset
*/
void writeJcc(string mnem, opcode...)(CodeBlock cb, Label label)
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
alias ja = writeJcc!("ja" , 0x0F, 0x87);
alias jae = writeJcc!("jae", 0x0F, 0x83);
alias jb = writeJcc!("jb" , 0x0F, 0x82);
alias jbe = writeJcc!("jbe", 0x0F, 0x86);
alias jc = writeJcc!("jc" , 0x0F, 0x82);
alias je = writeJcc!("je" , 0x0F, 0x84);
alias jg = writeJcc!("jg" , 0x0F, 0x8F);
alias jge = writeJcc!("jge", 0x0F, 0x8D);
alias jl = writeJcc!("jl" , 0x0F, 0x8C);
alias jle = writeJcc!("jle", 0x0F, 0x8E);
alias jna = writeJcc!("jna" , 0x0F, 0x86);
alias jnae = writeJcc!("jnae", 0x0F, 0x82);
alias jnb = writeJcc!("jnb" , 0x0F, 0x83);
alias jnbe = writeJcc!("jnbe", 0x0F, 0x87);
alias jnc = writeJcc!("jnc" , 0x0F, 0x83);
alias jne = writeJcc!("jne" , 0x0F, 0x85);
alias jng = writeJcc!("jng" , 0x0F, 0x8E);
alias jnge = writeJcc!("jnge", 0x0F, 0x8C);
alias jnl = writeJcc!("jnl" , 0x0F, 0x8D);
alias jnle = writeJcc!("jnle", 0x0F, 0x8F);
alias jno = writeJcc!("jno", 0x0F, 0x81);
alias jnp = writeJcc!("jnp", 0x0F, 0x8b);
alias jns = writeJcc!("jns", 0x0F, 0x89);
alias jnz = writeJcc!("jnz", 0x0F, 0x85);
alias jo = writeJcc!("jo" , 0x0F, 0x80);
alias jp = writeJcc!("jp" , 0x0F, 0x8A);
alias jpe = writeJcc!("jpe", 0x0F, 0x8A);
alias jpo = writeJcc!("jpo", 0x0F, 0x8B);
alias js = writeJcc!("js" , 0x0F, 0x88);
alias jz = writeJcc!("jz" , 0x0F, 0x84);

/// Opcode for direct jump with relative 8-bit offset
const ubyte JMP_REL8_OPCODE = 0xEB;

/// Opcode for direct jump with relative 32-bit offset
const ubyte JMP_REL32_OPCODE = 0xE9;

/// Opcode for jump on equal with relative 32-bit offset
const ubyte[] JE_REL32_OPCODE = [0x0F, 0x84];

/// jmp - Direct relative jump to label
alias jmp = writeJcc!("jmp", JMP_REL32_OPCODE);

/// jmp - Indirect jump near to an R/M operand
void jmp(CodeBlock cb, X86Opnd opnd)
{
    cb.writeASM("jmp", opnd);
    cb.writeRMInstr!('l', 4, 0xFF)(false, false, opnd, X86Opnd.NONE);
}

/// jmp - Jump with relative 8-bit offset
void jmp8(CodeBlock cb, int8_t offset)
{
    cb.writeASM("jmp", ((offset > 0)? "+":"-") ~ to!string(offset));
    cb.writeByte(JMP_REL8_OPCODE);
    cb.writeByte(offset);
}

/// jmp - Jump with relative 32-bit offset
void jmp32(CodeBlock cb, int32_t offset)
{
    cb.writeASM("jmp", ((offset > 0)? "+":"-") ~ to!string(offset));
    cb.writeByte(JMP_REL32_OPCODE);
    cb.writeInt(offset, 32);
}

/// lea - Load Effective Address
void lea(CodeBlock cb, X86Reg dst, X86Mem src)
{
    cb.writeASM("lea", dst, src);

    assert (dst.size is 64);
    cb.writeRMInstr!('r', 0xFF, 0x8D)(false, true, X86Opnd(dst), X86Opnd(src));
}

/// mov - Data move operation
void mov(CodeBlock cb, X86Opnd dst, X86Opnd src)
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

            assert (
                imm.immSize <= dstSize || imm.unsgSize <= dstSize,
                format("immediate too large for dst reg: %s = %s", imm, dst)
            );

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
            auto dstSize = dst.mem.size;
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
void mov(CodeBlock cb, X86Reg reg, X86Imm imm)
{
    // TODO: more optimized code for this case
    cb.mov(X86Opnd(reg), X86Opnd(imm));
}

/// mov - Move an immediate into a register
void mov(CodeBlock cb, X86Reg reg, int64_t imm)
{
    // TODO: more optimized code for this case
    cb.mov(X86Opnd(reg), X86Opnd(imm));
}

/// mov - Register to register move
void mov(CodeBlock cb, X86Reg dst, X86Reg src)
{
    // TODO: more optimized code for this case
    cb.mov(X86Opnd(dst), X86Opnd(src));
}

/// movq - Move quadword
void movq(CodeBlock cb, X86Opnd dst, X86Opnd src)
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
        assert (src.isXMM, "src should be XMM");
        cb.writeByte(0x66);
        cb.writeRMInstr!('l', 0xFF, 0x0F, 0x7E)(false, true, dst, src);
    }
    else
    {
        assert (false, "invalid dst operand");
    }
}

/// movsd - Move scalar double to/from XMM
void movsd(CodeBlock cb, X86Opnd dst, X86Opnd src)
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
void movsx(CodeBlock cb, X86Opnd dst, X86Opnd src)
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
void movzx(CodeBlock cb, X86Opnd dst, X86Opnd src)
{
    cb.writeASM("movzx", dst, src);

    size_t dstSize;
    if (dst.isReg)
        dstSize = dst.reg.size;
    else
        assert (false, "movzx dst must be a register");

    size_t srcSize;
    if (src.isReg)
        srcSize = src.reg.size;
    else if (src.isMem)
        srcSize = src.mem.size;
    else
        assert (false);

    assert (
        srcSize < dstSize,
        "movzx: srcSize >= dstSize"
    );

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
        assert (false, "invalid src operand size for movxz");
    }
}

// mul - Unsigned integer multiply
alias mul = writeRMUnary!(
    "mul", 
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x04  // opExt
);

// mulsd - Multiply scalar double
alias mulsd = writeXMM64!(
    "mulsd",
    0xF2, // prefix
    0x0F, // opRegMem0
    0x59  // opRegMem1
);

// neg - Integer negation (multiplication by -1)
alias neg = writeRMUnary!(
    "neg",
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x03  // opExt
);

/// nop - Noop, one or multiple bytes long
void nop(CodeBlock cb, size_t length = 1)
{
    switch (length)
    {
        case 0:
        break;

        case 1:
        cb.writeASM("nop1");
        cb.writeByte(0x90);
        break;

        case 2:
        cb.writeASM("nop2");
        cb.writeBytes(0x66,0x90);
        break;

        case 3:
        cb.writeASM("nop3");
        cb.writeBytes(0x0F,0x1F,0x00);
        break;

        case 4:
        cb.writeASM("nop4");
        cb.writeBytes(0x0F,0x1F,0x40,0x00);
        break;

        case 5:
        cb.writeASM("nop5");
        cb.writeBytes(0x0F,0x1F,0x44,0x00,0x00);
        break;

        case 6:
        cb.writeASM("nop6");
        cb.writeBytes(0x66,0x0F,0x1F,0x44,0x00,0x00);
        break;

        case 7:
        cb.writeASM("nop7");
        cb.writeBytes(0x0F,0x1F,0x80,0x00,0x00,0x00,0x00);
        break;

        case 8:
        cb.writeASM("nop8");
        cb.writeBytes(0x0F,0x1F,0x84,0x00,0x00,0x00,0x00,0x00);
        break;

        case 9:
        cb.writeASM("nop9");
        cb.writeBytes(0x66,0x0F,0x1F,0x84,0x00,0x00,0x00,0x00,0x00);
        break;

        default:
        size_t written = 0;
        while (written + 9 <= length)
        {
            cb.nop(9);
            written += 9;
        }
        cb.nop(length - written);
        break;
    }
}

// not - Bitwise NOT
alias not = writeRMUnary!(
    "not",
    0xF6, // opMemReg8 
    0xF7, // opMemRegPref
    0x02  // opExt
);

/// or - Bitwise OR
alias or = writeRMMulti!(
    "or",
    0x08, // opMemReg8
    0x09, // opMemRegPref
    0x0A, // opRegMem8
    0x0B, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x01  // opExtImm
);

/// push - Push a register on the stack
void push(CodeBlock cb, immutable X86Reg reg)
{
    assert (reg.size is 64, "can only push 64-bit registers");

    cb.writeASM("push", reg); 

    if (reg.rexNeeded)
        cb.writeREX(false, 0, 0, reg.regNo);
    cb.writeOpcode(0x50, reg);
}

/// pushfq - Push the flags register (64-bit)
void pushfq(CodeBlock cb)
{
    cb.writeASM("pushfq");
    cb.writeByte(0x9C);
}

/// pop - Pop a register off the stack
void pop(CodeBlock cb, immutable X86Reg reg)
{
    assert (reg.size is 64);

    cb.writeASM("pop", reg);

    if (reg.rexNeeded)
        cb.writeREX(false, 0, 0, reg.regNo);
    cb.writeOpcode(0x58, reg);
}

/// popfq - Pop the flags register (64-bit)
void popfq(CodeBlock cb)
{
    cb.writeASM("popfq");

    // REX.W + 0x9D
    cb.writeBytes(0x48, 0x9D);
}

// pxor - Logical Exclusive OR of XMM registers
alias pxor = writeXMM64!(
    "pxor",
    0x66, // prefix
    0x0F, // opRegMem0
    0xEF  // opRegMem1
);

/// ret - Return from call, popping only the return address
void ret(CodeBlock cb)
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
(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1)
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
        assert (false, "shift: invalid first operand: " ~ opnd0.toString);

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
        cb.writeRMInstr!('l', opExt, opMemClPref)(szPref, rexW, opnd0, X86Opnd.NONE);
    }
    else
    {
        assert (false);
    }
}

/// sal - Shift arithmetic left
alias sal = writeShift!(
    "sal",
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x04
);

/// shl - Shift logical left
alias shl = writeShift!(
    "shl",
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x04
);

/// sar - Shift arithmetic right (signed)
alias sar = writeShift!(
    "sar",
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x07
);

/// shr - Shift logical right (unsigned)
alias shr = writeShift!(
    "shr", 
    0xD1, // opMemOnePref,
    0xD3, // opMemClPref,
    0xC1, // opMemImmPref,
    0x05
);

// sqrtsd - Square root of scalar double (SSE2)
alias sqrtsd = writeXMM64!(
    "sqrtsd",
    0xF2, // prefix
    0x0F, // opRegMem0
    0x51  // opRegMem1
);

/// sub - Integer subtraction
alias sub = writeRMMulti!(
    "sub",
    0x28, // opMemReg8
    0x29, // opMemRegPref
    0x2A, // opRegMem8
    0x2B, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x05  // opExtImm
);

/// sub - Subtract with register and immediate operand
void sub(CodeBlock as, X86Reg dst, int64_t imm)
{
    assert (imm >= int32_t.min && imm <= int32_t.max);

    // TODO: optimize encoding
    return sub(as, X86Opnd(dst), X86Opnd(imm));
}

// subsd - Subtract scalar double
alias subsd = writeXMM64!(
    "subsd",
    0xF2, // prefix
    0x0F, // opRegMem0
    0x5C  // opRegMem1
);

// ucomisd - Unordered compare scalar double
alias ucomisd = writeXMM64!(
    "ucomisd",
    0x66, // prefix
    0x0F, // opRegMem0
    0x2E  // opRegMem1
);

/// xor - Exclusive bitwise OR
alias xor = writeRMMulti!(
    "xor",
    0x30, // opMemReg8
    0x31, // opMemRegPref
    0x32, // opRegMem8
    0x33, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x06  // opExtImm
);

// xorps - Exclusive bitwise OR for single-precision floats
alias xorps = writeXMM64!(
    "xorps",
    0xFF, // prefix
    0x0F, // opRegMem0
    0x57  // opRegMem1
);

