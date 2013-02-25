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
import std.stdint;
import jit.codeblock;

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

    uint8_t type;

    // Register index number
    uint8_t regNo;

    // Size in bits
    uint8_t size;
};

alias immutable(X86Reg)* X86RegPtr;

/// General-purpose registers
immutable al = X86Reg(X86Reg.GP, 0, 8);
immutable cl = X86Reg(X86Reg.GP, 0, 8);
immutable dl = X86Reg(X86Reg.GP, 0, 8);
immutable bl = X86Reg(X86Reg.GP, 0, 8);
immutable r8l = X86Reg(X86Reg.GP, 8, 8);
immutable r9l = X86Reg(X86Reg.GP, 8, 8);
immutable r10l = X86Reg(X86Reg.GP, 8, 8);
immutable r11l = X86Reg(X86Reg.GP, 8, 8);
immutable r12l = X86Reg(X86Reg.GP, 8, 8);
immutable r13l = X86Reg(X86Reg.GP, 8, 8);
immutable r14l = X86Reg(X86Reg.GP, 8, 8);
immutable r15l = X86Reg(X86Reg.GP, 8, 8);
immutable ax = X86Reg(X86Reg.GP, 0, 16);
immutable cx = X86Reg(X86Reg.GP, 1, 16);
immutable dx = X86Reg(X86Reg.GP, 2, 16);
immutable bx = X86Reg(X86Reg.GP, 3, 16);
immutable sp = X86Reg(X86Reg.GP, 4, 16);
immutable bp = X86Reg(X86Reg.GP, 5, 16);
immutable si = X86Reg(X86Reg.GP, 6, 16);
immutable di = X86Reg(X86Reg.GP, 7, 16);
immutable r8w = X86Reg(X86Reg.GP, 8, 16);
immutable r9w = X86Reg(X86Reg.GP, 9, 16);
immutable r10w = X86Reg(X86Reg.GP, 10, 16);
immutable r11w = X86Reg(X86Reg.GP, 11, 16);
immutable r12w = X86Reg(X86Reg.GP, 12, 16);
immutable r13w = X86Reg(X86Reg.GP, 13, 16);
immutable r14w = X86Reg(X86Reg.GP, 14, 16);
immutable r15w = X86Reg(X86Reg.GP, 15, 16);
immutable eax = X86Reg(X86Reg.GP, 0, 32);
immutable ecx = X86Reg(X86Reg.GP, 1, 32);
immutable edx = X86Reg(X86Reg.GP, 2, 32);
immutable ebx = X86Reg(X86Reg.GP, 3, 32);
immutable esp = X86Reg(X86Reg.GP, 4, 32);
immutable ebp = X86Reg(X86Reg.GP, 5, 32);
immutable esi = X86Reg(X86Reg.GP, 6, 32);
immutable edi = X86Reg(X86Reg.GP, 7, 32);
immutable r8d = X86Reg(X86Reg.GP, 8, 32);
immutable r9d = X86Reg(X86Reg.GP, 9, 32);
immutable r10d = X86Reg(X86Reg.GP, 10, 32);
immutable r11d = X86Reg(X86Reg.GP, 11, 32);
immutable r12d = X86Reg(X86Reg.GP, 12, 32);
immutable r13d = X86Reg(X86Reg.GP, 13, 32);
immutable r14d = X86Reg(X86Reg.GP, 14, 32);
immutable r15d = X86Reg(X86Reg.GP, 15, 32);
immutable rax = X86Reg(X86Reg.GP, 0, 64);
immutable rcx = X86Reg(X86Reg.GP, 1, 64);
immutable rdx = X86Reg(X86Reg.GP, 2, 64);
immutable rbx = X86Reg(X86Reg.GP, 3, 64);
immutable rsp = X86Reg(X86Reg.GP, 4, 64);
immutable rbp = X86Reg(X86Reg.GP, 5, 64);
immutable rsi = X86Reg(X86Reg.GP, 6, 64);
immutable rdi = X86Reg(X86Reg.GP, 7, 64);
immutable r8 = X86Reg(X86Reg.GP, 8, 64);
immutable r9 = X86Reg(X86Reg.GP, 9, 64);
immutable r10 = X86Reg(X86Reg.GP, 10, 64);
immutable r11 = X86Reg(X86Reg.GP, 11, 64);
immutable r12 = X86Reg(X86Reg.GP, 12, 64);
immutable r13 = X86Reg(X86Reg.GP, 13, 64);
immutable r14 = X86Reg(X86Reg.GP, 14, 64);
immutable r15 = X86Reg(X86Reg.GP, 15, 64);

// Instruction pointer, for ip-relative addressing
immutable rip = X86Reg(X86Reg.IP, 5, 64);

// XMM SIMD registers
immutable xmm0   = X86Reg(X86Reg.XMM, 0, 128);
immutable xmm1   = X86Reg(X86Reg.XMM, 1, 128);
immutable xmm2   = X86Reg(X86Reg.XMM, 2, 128);
immutable xmm3   = X86Reg(X86Reg.XMM, 3, 128);
immutable xmm4   = X86Reg(X86Reg.XMM, 4, 128);
immutable xmm5   = X86Reg(X86Reg.XMM, 5, 128);
immutable xmm6   = X86Reg(X86Reg.XMM, 6, 128);
immutable xmm7   = X86Reg(X86Reg.XMM, 7, 128);
immutable xmm8   = X86Reg(X86Reg.XMM, 8, 128);
immutable xmm9   = X86Reg(X86Reg.XMM, 9, 128);
immutable xmm10  = X86Reg(X86Reg.XMM,10, 128);
immutable xmm11  = X86Reg(X86Reg.XMM,11, 128);
immutable xmm12  = X86Reg(X86Reg.XMM,12, 128);
immutable xmm13  = X86Reg(X86Reg.XMM,13, 128);
immutable xmm14  = X86Reg(X86Reg.XMM,14, 128);
immutable xmm15  = X86Reg(X86Reg.XMM,15, 128);

/**
Instruction operand value
*/
struct X86Opnd
{
    /// Operand type enumeration
    alias uint Type;
    enum : Type
    {
        REG,
        MEM,
        IMM,
        LINK
    };

    // Operand type
    Type type;
    
    union
    {
        // Register
        X86RegPtr reg;

        // Memory location
        struct { uint memSize; X86RegPtr base; uint disp; X86RegPtr index; uint scale; }

        // Immediate value
        uint64_t imm;

        // TODO: link-time value
    };

    string toString()
    {
        // TODO
        return "";
    }

    bool rexNeeded()
    {
        // TODO:
        return false;
    }

    bool sibNeeded()
    {
        // TODO:
        return false;
    }

    bool rexAvail()
    {
        // TODO:
        return true;
    }

    /**
    Compute the size of the displacement field needed (memory operands only)
    */
    size_t dispSize()
    {
        assert (
            type == MEM,
            "dispSize only available for memory operands"
        );

        /*
        // If EBP or RBP or R13 is used as the base, displacement must be encoded
        if (base === x86.regs.ebp ||
            base === x86.regs.rbp || 
            base === x86.regs.r13)
            this.dispSize = 8;

        // If using displacement only or if using an index only or if using
        // RIP as the base, use disp32
        if ((!base && !index) || 
            (!base && index) ||
            (base === x86.regs.rip))
        {
            this.dispSize = 32;
        }

        // Compute the required displacement size
        else if (num_ne(disp, 0))
        {
            if (num_ge(disp, getIntMin(8)) && num_le(disp, getIntMax(8)))
                this.dispSize = 8;
            else if (num_ge(disp, getIntMin(32)) && num_le(disp, getIntMax(32)))
                this.dispSize = 32;
            else
                error('displacement does not fit within 32 bits');
        }
        */

        // TODO
        return 0;
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
        XMM,
        IMM,
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
class X86Instr : JITInstr
{
    /// Opcode (instruction type)
    X86OpPtr opcode = null;

    /// Operands
    X86Opnd[] opnds = [];

    /// Encoding found
    X86EncPtr enc = null;

    /// Encoding length
    uint8_t encLength = 0;

    this(X86OpPtr opcode)
    {
        this.opcode = opcode;
    }

    this(X86OpPtr opcode, X86Opnd opnd0, X86Opnd opnd1)
    {
        this.opcode = opcode;
        this.opnds = [opnd0, opnd1];
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
    Get the length of the best encoding of this instruction
    */
    override size_t length()
    {
        // If no encoding is yet found, find one
        if (enc is null)
            findEncoding();

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

        // Flag to indicate the REX prefix is needed
        bool rexNeeded = (enc.rexW == 1);

        // Flags to indicate if the ModRM and SIB bytes needed
        bool rmNeeded = false;
        bool sibNeeded = false;

        // r and r/m operands
        X86Opnd* rOpnd = null;
        X86Opnd* rmOpnd = null;

        // Immediate operand size and value
        size_t immSize = 0;
        size_t immVal = 0;

        // Displacement size and value
        size_t dispSize = 0;
        size_t dispVal = 0;

        // For each operand
        for (size_t i = 0; i < this.opnds.length; ++i)
        {
            auto opnd = &this.opnds[i];

            auto opndType = enc.opndTypes[i];
            auto opndSize = enc.opndSizes[i];

            if (opnd.rexNeeded == true)
                rexNeeded = true;

            /*
            if (opndType === 'imm' || 
                opndType === 'moffs' ||
                opndType === 'rel')
            {
                immSize = opndSize;
                immOpnd = opnd;
            }

            else if (opndType === 'r' ||
                     opndType === 'xmm')
            {
                rOpnd = opnd;
            }

            else if (opndType === 'm' ||
                     opndType === 'r/m' ||
                     opndType === 'xmm/m')
            {
                rmNeeded = true;
                rmOpnd = opnd;

                if (opnd instanceof x86.MemLoc)
                {
                    if (opnd.sibNeeded(x86_64))
                    {
                        sibNeeded = true;
                    }

                    if (opnd.dispSize > 0)
                    {
                        dispSize = opnd.dispSize;
                        dispVal = opnd.disp;
                    }
                }
            }
            */
        }

        // Get the index in the code block before the encoding
        auto startIndex = codeBlock.getWritePos();

        // Add the address-size prefix, if needed
        if (rmOpnd &&
            ((rmOpnd.base && rmOpnd.base.size == 32) ||
             (rmOpnd.index && rmOpnd.index.size == 32)))
            codeBlock.writeByte(0x67);

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
            if (rOpnd && rmOpnd)
                r = (rOpnd.reg.regNo & 8)? 1:0;
            else
                r = 0;

            uint x;
            if (sibNeeded && rmOpnd.index)
                x = (rmOpnd.index.regNo & 8)? 1:0;
            else
                x = 0;

            uint b;
            if (rmOpnd)
                b = (rmOpnd.reg.regNo & 8)? 1:0;
            else if (rOpnd && !rmOpnd)
                b = (rOpnd.reg.regNo & 8)? 1:0;
            else if (rmOpnd && rmOpnd.base)
                b = (rmOpnd.base.regNo & 8)? 1:0;
            else
                b = 0;

            // Encode and write the REX byte
            auto rexByte = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
            codeBlock.writeByte(cast(byte)rexByte);
        }

        // If an opcode reg field is to be used
        if (rOpnd && !rmOpnd)
        {
            // Write the reg field into the opcode byte
            uint8_t opByte = enc.opcode[0] | (rOpnd.reg.regNo & 7);
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
                !(enc.opExt != byte.max && rOpnd),
                "opcode extension and register operand present"
            );

            /*
            // Encode the mod field
            var mod;
            if (rmOpnd instanceof x86.Register)
            {
                mod = 3;
            }
            else
            {
                if (dispSize === 0 || !rmOpnd.base)
                    mod = 0;
                else if (dispSize === 8)
                    mod = 1
                else if (dispSize === 32)
                    mod = 2;
            }

            // Encode the reg field
            var reg;
            if (enc.opExt)
                reg = enc.opExt;
            else if (rOpnd)
                reg = rOpnd.regNo & 7;
            else
                reg = 0;

            // Encode the rm field
            var rm;
            if (rmOpnd instanceof x86.Register)
            {
                rm = rmOpnd.regNo & 7;
            }
            else
            {
                if (sibNeeded)
                    rm = 4;
                else if (!x86_64 && !rmOpnd.base && !rmOpnd.index)
                    rm = 5;
                else if (rmOpnd.base === x86.regs.rip)
                    rm = 5;
                else if (rmOpnd.base)
                    rm = rmOpnd.base.regNo & 7;
                else
                    rm = 0;
            }

            // Encode and write the ModR/M byte
            var rmByte = (mod << 6) + (reg << 3) + (rm);
            codeBlock.writeByte(rmByte);
            */
        }

        // Add the SIB byte, if needed
        if (sibNeeded)
        {
            // SIB.scale (2 bits)
            // SIB.index (3 bits)
            // SIB.base  (3 bits)

            /*
            assert (
                rmOpnd instanceof x86.MemLoc,
                'expected r/m opnd to be mem loc'
            );

            // Encode the scale value
            var scale;
            switch (rmOpnd.scale)
            {
                case 1: scale = 0; break;
                case 2: scale = 1; break
                case 4: scale = 2; break
                case 8: scale = 3; break
                default: error('invalid SIB scale: ' + rmOpnd.scale);
            }

            // Encode the index value
            var index;
            if (!rmOpnd.index)
                index = 4;
            else
                index = rmOpnd.index.regNo & 7;

            // Encode the base register
            var base;
            if (!rmOpnd.base)
                base = 5;
            else
                base = rmOpnd.base.regNo & 7;

            // Encode and write the SIB byte
            var sibByte = (scale << 6) + (index << 3) + (base);
            codeBlock.writeByte(sibByte);
            */
        }

        /*
        // Add the displacement size
        if (dispSize !== 0)
            codeBlock.writeInt(dispVal, dispSize);

        // If there is an immediate operand
        if (immSize !== 0)
        {
            if (immOpnd instanceof x86.Immediate)
                immOpnd.writeImm(codeBlock, immSize);
            else if (immOpnd instanceof x86.LabelRef)
                codeBlock.writeInt(immOpnd.relOffset, immSize);
            else
                error('invalid immediate operand');
        }
        */

        // Get the index in the code block after the encoding
        auto endIndex = codeBlock.getWritePos();

        // Compute the length of the data written
        auto wrtLength = endIndex - startIndex;

        assert (
            wrtLength == this.encLength,
            xformat(
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
    void findEncoding()
    {
        // Best encoding found
        X86EncPtr bestEnc = null;
        size_t bestLen = size_t.max;

        // TODO: look at opndSize first
        // Get current opnd size, if applicable

        // TODO: stop when opndSize is too small

        // For each possible encoding
        ENC_LOOP:
        for (size_t i = 0; i < opcode.encs.length; ++i)
        {
            auto enc = &opcode.encs[i];

            // If the number of operands does not match, skip this encoding
            if (enc.opndTypes.length != this.opnds.length)
                continue ENC_LOOP;

            // For each operand
            for (size_t j = 0; j < this.opnds.length; ++j)
            {
                auto opnd = &this.opnds[j];

                auto opndType = enc.opndTypes[j];
                auto opndSize = enc.opndSizes[j];

                // If this encoding requires REX but the operand is not
                // available under REX, skip this encoding
                if (enc.rexW && !opnd.rexAvail)
                    continue ENC_LOOP;




                /*
                // Switch on the operand type
                switch (opndType)
                {
                    case 'fixed_reg':
                    if (opnd !== encOpnd)
                        continue ENC_LOOP;
                    break;

                    case 'cst':
                    if (!(opnd instanceof x86.Immediate))
                        continue ENC_LOOP;
                    if (opnd.value !== encOpnd)
                        continue ENC_LOOP;
                    break;

                    case 'imm':
                    //print('imm opnd');
                    //print('imm opnd size: ' + opnd.size);
                    if (!(opnd instanceof x86.Immediate))
                        continue ENC_LOOP;
                    if (opnd.type !== 'imm')
                        continue ENC_LOOP;
                    if (opnd.size > opndSize)
                    {
                        if (!opnd.unsgSize)
                            continue ENC_LOOP;

                        if (opnd.unsgSize !== opndSize || 
                            opndSize !== enc.opndSize)
                            continue ENC_LOOP;
                    }
                    break;

                    case 'r':
                    if (!(opnd instanceof x86.Register && opnd.type === 'gp'))
                        continue ENC_LOOP;
                    if (opnd.size !== opndSize)
                        continue ENC_LOOP;
                    break;

                    case 'xmm':
                    if (!(opnd instanceof x86.Register && opnd.type === 'xmm'))
                        continue ENC_LOOP;
                    break;

                    case 'm':
                    if (!(opnd instanceof x86.MemLoc))
                        continue ENC_LOOP;
                    if (opnd.size !== opndSize && opndSize !== undefined)
                        continue ENC_LOOP;
                    break;

                    case 'r/m':
                    if (!(opnd instanceof x86.Register && opnd.type === 'gp') && 
                        !(opnd instanceof x86.MemLoc))
                        continue ENC_LOOP;
                    if (opnd.size !== opndSize)
                        continue ENC_LOOP;
                    break;

                    case 'xmm/m':
                    if (!(opnd instanceof x86.Register && opnd.type === 'xmm') && 
                        !(opnd instanceof x86.MemLoc && opnd.size === opndSize))
                        continue ENC_LOOP;
                    break;

                    case 'rel':
                    if (!(opnd instanceof x86.LabelRef))
                        continue ENC_LOOP;
                    if (opnd.size > opndSize)
                        continue ENC_LOOP;
                    break;

                    case 'moffs':
                    if (!(opnd instanceof x86.Immediate))
                        continue ENC_LOOP;
                    if (opnd.type !== 'moffs')
                        continue ENC_LOOP;
                    if (opnd.unsgSize > opndSize)
                        continue ENC_LOOP;
                    break;

                    default:
                    error('invalid operand type "' + opndType + '"');
                }
                */
            }

            auto len = compEncLen(enc);

            if (len < bestLen)
            {
                bestEnc = enc;
                bestLen = len;
            }
        }

        assert (
            bestEnc !is null,
            "no valid encoding found for " ~ this.toString()
        );

        // Store the best encoding found
        enc = bestEnc;

        // Store the encoding length
        encLength = cast(uint8_t)bestLen;
    }

    /**
    Compute the length of an encoding of this instruction
    */
    size_t compEncLen(X86EncPtr enc)
    {
        // x86 instruction format:
        // prefix(es)  [REX] opcode  [XRM  [SIB]]  disp  imm

        // Flag to indicate the REX prefix is needed
        bool rexNeeded = (enc.rexW == 1);

        // Flags to indicate if the ModRM and SIB bytes needed
        bool rmNeeded = false;
        bool sibNeeded = false;

        // RM operand, if present
        X86Opnd* rmOpnd = null;

        // Displacement size required
        size_t dispSize = 0;

        // Immediate size required
        size_t immSize = 0;

        // For each operand
        for (size_t i = 0; i < this.opnds.length; ++i)
        {
            auto opnd = &this.opnds[i];

            auto opndType = enc.opndTypes[i];
            auto opndSize = enc.opndSizes[i];

            if (opnd.rexNeeded)
                rexNeeded = true;

            if (opndType & X86Enc.IMM)
            {
                immSize = opndSize;
            }

            // If this operand can be a memory location
            else if (opndType & X86Enc.M)
            {
                rmNeeded = true;
                rmOpnd = opnd;

                if (opnd.type == X86Opnd.MEM)
                {
                    if (opnd.sibNeeded)
                        sibNeeded = true;

                    // TODO: dispSize??? is this the same as disp
                    //if (opnd.dispSize > 0)
                    //    dispSize = opnd.dispSize;
                }
            }
        }

        // Total encoding size
        size_t size = 0;

        // Add the address-size prefix, if needed
        if (rmOpnd && 
            ((rmOpnd.base && rmOpnd.base.size == 32) ||
             (rmOpnd.index && rmOpnd.index.size == 32)))
            size += 1;

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

