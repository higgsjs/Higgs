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

    // Instruction pointer (RIP)
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
        assert (base.size is 64 && index.size is 64);

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
void writeRMInstr(char rmOpnd, ubyte opExt, opcode...)(CodeBlock cb, bool szPref, bool rexW, X86Opnd opnd0, X86Opnd opnd1)
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










// TODO: add
/*
Enc(opnds=['al', 'imm8'], opcode=[0x04]),
Enc(opnds=['ax', 'imm16'], opcode=[0x05]),
Enc(opnds=['eax', 'imm32'], opcode=[0x05]),
Enc(opnds=['rax', 'imm32'], opcode=[0x05]),
Enc(opnds=['r/m8', 'imm8'], opcode=[0x80], opExt=0),
Enc(opnds=['r/m16', 'imm16'], opcode=[0x81], opExt=0),
Enc(opnds=['r/m32', 'imm32'], opcode=[0x81], opExt=0),
Enc(opnds=['r/m64', 'imm32'], opcode=[0x81], opExt=0),
Enc(opnds=['r/m16', 'imm8'], opcode=[0x83], opExt=0),
Enc(opnds=['r/m32', 'imm8'], opcode=[0x83], opExt=0),
Enc(opnds=['r/m64', 'imm8'], opcode=[0x83], opExt=0),
Enc(opnds=['r/m8', 'r8'], opcode=[0x00]),
Enc(opnds=['r/m16', 'r16'], opcode=[0x01]),
Enc(opnds=['r/m32', 'r32'], opcode=[0x01]),
Enc(opnds=['r/m64', 'r64'], opcode=[0x01]),
Enc(opnds=['r8', 'r/m8'], opcode=[0x02]),
Enc(opnds=['r16', 'r/m16'], opcode=[0x03]),
Enc(opnds=['r32', 'r/m32'], opcode=[0x03]),
Enc(opnds=['r64', 'r/m64'], opcode=[0x03])
*/

/**
Integer add
*/
void add(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1)
{
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

    if ((opnd0.isReg && opnd1.isReg) || 
        (opnd0.isMem && opnd1.isReg))
    {
        if (opndSize is 8)
            cb.writeRMInstr!('l', 0xFF, 0x00)(false, false, opnd0, opnd1);
        else
            cb.writeRMInstr!('l', 0xFF, 0x01)(szPref, rexW, opnd0, opnd1);
    }

    else if (opnd0.isReg && opnd1.isMem)
    {
        if (opndSize is 8)
            cb.writeRMInstr!('r', 0xFF, 0x02)(false, false, opnd0, opnd1);
        else
            cb.writeRMInstr!('r', 0xFF, 0x03)(szPref, rexW, opnd0, opnd1);
    }

    else if (opnd1.isImm)
    {
        if (opnd1.imm.immSize <= 8)
        {
            if (opndSize is 8)
                cb.writeRMInstr!('l', 0, 0x80)(false, false, opnd0, X86Opnd.NONE);
            else
                cb.writeRMInstr!('l', 0, 0x83)(szPref, rexW, opnd0, X86Opnd.NONE);
            cb.writeInt(opnd1.imm.imm, 8);
        }
        else if (opnd1.imm.immSize <= 32)
        {
            cb.writeRMInstr!('l', 0, 0x81)(szPref, rexW, opnd0, X86Opnd.NONE);
            cb.writeInt(opnd1.imm.imm, 32);
        }
        else
        {
            assert (false, "immediate value too large");
        }
    }

    else
    {
        assert (false);
    }
}

// TODO
/*
# Bitwise AND
Op(
    'and',
    Enc(opnds=['al', 'imm8'], opcode=[0x24]),
    Enc(opnds=['ax', 'imm16'], opcode=[0x25]),
    Enc(opnds=['eax', 'imm32'], opcode=[0x25]),
    Enc(opnds=['rax', 'imm32'], opcode=[0x25]),
    Enc(opnds=['r/m8', 'imm8'], opcode=[0x80], opExt=4),
    Enc(opnds=['r/m16', 'imm16'], opcode=[0x81], opExt=4),
    Enc(opnds=['r/m32', 'imm32'], opcode=[0x81], opExt=4),
    Enc(opnds=['r/m64', 'imm32'], opcode=[0x81], opExt=4),
    Enc(opnds=['r/m16', 'imm8'], opcode=[0x83], opExt=4),
    Enc(opnds=['r/m32', 'imm8'], opcode=[0x83], opExt=4),
    Enc(opnds=['r/m64', 'imm8'], opcode=[0x83], opExt=4),
    Enc(opnds=['r/m8', 'r8'], opcode=[0x20]),
    Enc(opnds=['r/m16', 'r16'], opcode=[0x21]),
    Enc(opnds=['r/m32', 'r32'], opcode=[0x21]),
    Enc(opnds=['r/m64', 'r64'], opcode=[0x21]),
    Enc(opnds=['r8', 'r/m8'], opcode=[0x22]),
    Enc(opnds=['r16', 'r/m16'], opcode=[0x23]),
    Enc(opnds=['r32', 'r/m32'], opcode=[0x23]),
    Enc(opnds=['r64', 'r/m64'], opcode=[0x23]),
),
*/


// TODO: call
// For this, we will need a patchable 32-bit offset
//Enc(opnds=['rel32'], opcode=[0xE8]),
//void call(Assembler as, BlockVersion???);

// TODO: test this
//Enc(opnds=['r/m64'], opcode=[0xFF], opExt=2, rexW=False)
void call(CodeBlock cb, X86Opnd opnd)
{
    cb.writeRMInstr!('l', 2, 0xFF)(false, false, opnd, X86Opnd.NONE);
}




// TODO: cmp
/*
Enc(opnds=['al', 'imm8'], opcode=[0x3C]),
Enc(opnds=['ax', 'imm16'], opcode=[0x3D]),
Enc(opnds=['eax', 'imm32'], opcode=[0x3D]),
Enc(opnds=['rax', 'imm32'], opcode=[0x3D]),
Enc(opnds=['r/m8', 'imm8'], opcode=[0x80], opExt=7),
Enc(opnds=['r/m16', 'imm16'], opcode=[0x81], opExt=7),
Enc(opnds=['r/m32', 'imm32'], opcode=[0x81], opExt=7),
Enc(opnds=['r/m64', 'imm32'], opcode=[0x81], opExt=7),
Enc(opnds=['r/m16', 'imm8'], opcode=[0x83], opExt=7),
Enc(opnds=['r/m32', 'imm8'], opcode=[0x83], opExt=7),
Enc(opnds=['r/m64', 'imm8'], opcode=[0x83], opExt=7),
Enc(opnds=['r/m8', 'r8'], opcode=[0x38]),
Enc(opnds=['r/m16', 'r16'], opcode=[0x39]),
Enc(opnds=['r/m32', 'r32'], opcode=[0x39]),
Enc(opnds=['r/m64', 'r64'], opcode=[0x39]),
Enc(opnds=['r8', 'r/m8'], opcode=[0x3A]),
Enc(opnds=['r16', 'r/m16'], opcode=[0x3B]),
Enc(opnds=['r32', 'r/m32'], opcode=[0x3B]),
Enc(opnds=['r64', 'r/m64'], opcode=[0x3B]),
*/





// TODO: imul, 
// Signed integer multiply
/*
Enc(opnds=['r/m8'], opcode=[0xF6], opExt=5),
Enc(opnds=['r/m16'], opcode=[0xF7], opExt=5),
Enc(opnds=['r/m32'], opcode=[0xF7], opExt=5),
Enc(opnds=['r/m64'], opcode=[0xF7], opExt=5),
Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0xAF]),
Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0xAF]),
Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0xAF]),
Enc(opnds=['r16', 'r/m16', 'imm8'], opcode=[0x6B]),
Enc(opnds=['r32', 'r/m32', 'imm8'], opcode=[0x6B]),
Enc(opnds=['r64', 'r/m64', 'imm8'], opcode=[0x6B]),
Enc(opnds=['r16', 'r/m16', 'imm16'], opcode=[0x69]),
Enc(opnds=['r32', 'r/m32', 'imm32'], opcode=[0x69]),
Enc(opnds=['r64', 'r/m64', 'imm32'], opcode=[0x69]),
*/




// TODO: jmp
/*
# Jump relative near
Enc(opnds=['rel8'], opcode=[0xEB]),
Enc(opnds=['rel32'], opcode=[0xE9]),
# Jump absolute near
Enc(opnds=['r/m64'], opcode=[0xFF], opExt=4),
*/

// TODO: relative jumps, jmp, jcc







// TODO: mov
/*
Enc(opnds=['r/m8', 'r8'], opcode=[0x88]),
Enc(opnds=['r/m16', 'r16'], opcode=[0x89]),
Enc(opnds=['r/m32', 'r32'], opcode=[0x89]),
Enc(opnds=['r/m64', 'r64'], opcode=[0x89]),
Enc(opnds=['r8', 'r/m8'], opcode=[0x8A]),
Enc(opnds=['r16', 'r/m16'], opcode=[0x8B]),
Enc(opnds=['r32', 'r/m32'], opcode=[0x8B]),
Enc(opnds=['r64', 'r/m64'], opcode=[0x8B]),
Enc(opnds=['r8', 'imm8'], opcode=[0xB0]),
Enc(opnds=['r16', 'imm16'], opcode=[0xB8]),
Enc(opnds=['r32', 'imm32'], opcode=[0xB8]),
Enc(opnds=['r64', 'imm64'], opcode=[0xB8]),
Enc(opnds=['r/m8', 'imm8'], opcode=[0xC6]),
Enc(opnds=['r/m16', 'imm16'], opcode=[0xC7], opExt=0),
Enc(opnds=['r/m32', 'imm32'], opcode=[0xC7], opExt=0),
Enc(opnds=['r/m64', 'imm32'], opcode=[0xC7], opExt=0),
*/
// TODO:
/*
void mov(CodeBlock cb, X86Opnd dst, X86Opnd src)
{
}
*/







/// Noop, one or multiple bytes long
void nop(CodeBlock cb, size_t length = 1)
{
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

// TODO
/*
# Bitwise OR
Op(
    'or',
    Enc(opnds=['al', 'imm8'], opcode=[0x0C]),
    Enc(opnds=['ax', 'imm16'], opcode=[0x0D]),
    Enc(opnds=['eax', 'imm32'], opcode=[0x0D]),           
    Enc(opnds=['rax', 'imm32'], opcode=[0x0D]),
    Enc(opnds=['r/m8', 'imm8'], opcode=[0x80], opExt=1),
    Enc(opnds=['r/m16', 'imm16'], opcode=[0x81], opExt=1),
    Enc(opnds=['r/m32', 'imm32'], opcode=[0x81], opExt=1),
    Enc(opnds=['r/m64', 'imm32'], opcode=[0x81], opExt=1),
    Enc(opnds=['r/m16', 'imm8'], opcode=[0x83], opExt=1),
    Enc(opnds=['r/m32', 'imm8'], opcode=[0x83], opExt=1),
    Enc(opnds=['r/m64', 'imm8'], opcode=[0x83], opExt=1),
    Enc(opnds=['r/m8', 'r8'], opcode=[0x08]),
    Enc(opnds=['r/m16', 'r16'], opcode=[0x09]),
    Enc(opnds=['r/m32', 'r32'], opcode=[0x09]),
    Enc(opnds=['r/m64', 'r64'], opcode=[0x09]),
    Enc(opnds=['r8', 'r/m8'], opcode=[0x0A]),
    Enc(opnds=['r16', 'r/m16'], opcode=[0x0B]),
    Enc(opnds=['r32', 'r/m32'], opcode=[0x0B]),
    Enc(opnds=['r64', 'r/m64'], opcode=[0x0B]),
),
*/

/// Push a register on the stack
void push(CodeBlock cb, X86Reg reg)
{
    assert (reg.size is 64);
    if (reg.rexNeeded)
        cb.writeREX(false, reg.regNo);
    cb.writeOpcode(0x50, reg);
}

/// Pop a register off the stack
void pop(CodeBlock cb, X86Reg reg)
{
    assert (reg.size is 64);
    if (reg.rexNeeded)
        cb.writeREX(false, reg.regNo);
    cb.writeOpcode(0x58, reg);
}

/// Return from call, popping only the return address
void ret(CodeBlock cb)
{
    cb.writeByte(0xC3);
}




// TODO: sub
/*
Enc(opnds=['al', 'imm8'], opcode=[0x2C]),
Enc(opnds=['ax', 'imm16'], opcode=[0x2D]),
Enc(opnds=['eax', 'imm32'], opcode=[0x2D]),
Enc(opnds=['rax', 'imm32'], opcode=[0x2D]),
Enc(opnds=['r/m8', 'imm8'], opcode=[0x80], opExt=5),
Enc(opnds=['r/m16', 'imm16'], opcode=[0x81], opExt=5),
Enc(opnds=['r/m32', 'imm32'], opcode=[0x81], opExt=5),
Enc(opnds=['r/m64', 'imm32'], opcode=[0x81], opExt=5),
Enc(opnds=['r/m16', 'imm8'], opcode=[0x83], opExt=5),
Enc(opnds=['r/m32', 'imm8'], opcode=[0x83], opExt=5),
Enc(opnds=['r/m64', 'imm8'], opcode=[0x83], opExt=5),
Enc(opnds=['r/m8', 'r8'], opcode=[0x28]),
Enc(opnds=['r/m16', 'r16'], opcode=[0x29]),
Enc(opnds=['r/m32', 'r32'], opcode=[0x29]),
Enc(opnds=['r/m64', 'r64'], opcode=[0x29]),
Enc(opnds=['r8', 'r/m8'], opcode=[0x2A]),
Enc(opnds=['r16', 'r/m16'], opcode=[0x2B]),
Enc(opnds=['r32', 'r/m32'], opcode=[0x2B]),
Enc(opnds=['r64', 'r/m64'], opcode=[0x2B]),
*/




// TODO
/*
# Exclusive bitwise OR
Op(
    'xor',
    Enc(opnds=['al', 'imm8'], opcode=[0x34]),
    Enc(opnds=['ax', 'imm16'], opcode=[0x35]),
    Enc(opnds=['eax', 'imm32'], opcode=[0x35]),
    Enc(opnds=['rax', 'imm32'], opcode=[0x35]),
    Enc(opnds=['r/m8', 'imm8'], opcode=[0x80], opExt=6),
    Enc(opnds=['r/m16', 'imm16'], opcode=[0x81], opExt=6),
    Enc(opnds=['r/m32', 'imm32'], opcode=[0x81], opExt=6),
    Enc(opnds=['r/m64', 'imm32'], opcode=[0x81], opExt=6),
    Enc(opnds=['r/m16', 'imm8'], opcode=[0x83], opExt=6),
    Enc(opnds=['r/m32', 'imm8'], opcode=[0x83], opExt=6),
    Enc(opnds=['r/m64', 'imm8'], opcode=[0x83], opExt=6),
    Enc(opnds=['r/m8', 'r8'], opcode=[0x30]),
    Enc(opnds=['r/m16', 'r16'], opcode=[0x31]),
    Enc(opnds=['r/m32', 'r32'], opcode=[0x31]),
    Enc(opnds=['r/m64', 'r64'], opcode=[0x31]),
    Enc(opnds=['r8', 'r/m8'], opcode=[0x32]),
    Enc(opnds=['r16', 'r/m16'], opcode=[0x33]),
    Enc(opnds=['r32', 'r/m32'], opcode=[0x33]),
    Enc(opnds=['r64', 'r/m64'], opcode=[0x33]),
),
*/

