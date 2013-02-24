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

/// General-purpose registers
auto al = X86Reg(X86Reg.GP, 0, 8);
auto cl = X86Reg(X86Reg.GP, 0, 8);
auto dl = X86Reg(X86Reg.GP, 0, 8);
auto bl = X86Reg(X86Reg.GP, 0, 8);
auto r8l = X86Reg(X86Reg.GP, 8, 8);
auto r9l = X86Reg(X86Reg.GP, 8, 8);
auto r10l = X86Reg(X86Reg.GP, 8, 8);
auto r11l = X86Reg(X86Reg.GP, 8, 8);
auto r12l = X86Reg(X86Reg.GP, 8, 8);
auto r13l = X86Reg(X86Reg.GP, 8, 8);
auto r14l = X86Reg(X86Reg.GP, 8, 8);
auto r15l = X86Reg(X86Reg.GP, 8, 8);
auto ax = X86Reg(X86Reg.GP, 0, 16);
auto cx = X86Reg(X86Reg.GP, 1, 16);
auto dx = X86Reg(X86Reg.GP, 2, 16);
auto bx = X86Reg(X86Reg.GP, 3, 16);
auto sp = X86Reg(X86Reg.GP, 4, 16);
auto bp = X86Reg(X86Reg.GP, 5, 16);
auto si = X86Reg(X86Reg.GP, 6, 16);
auto di = X86Reg(X86Reg.GP, 7, 16);
auto r8w = X86Reg(X86Reg.GP, 8, 16);
auto r9w = X86Reg(X86Reg.GP, 9, 16);
auto r10w = X86Reg(X86Reg.GP, 10, 16);
auto r11w = X86Reg(X86Reg.GP, 11, 16);
auto r12w = X86Reg(X86Reg.GP, 12, 16);
auto r13w = X86Reg(X86Reg.GP, 13, 16);
auto r14w = X86Reg(X86Reg.GP, 14, 16);
auto r15w = X86Reg(X86Reg.GP, 15, 16);
auto eax = X86Reg(X86Reg.GP, 0, 32);
auto ecx = X86Reg(X86Reg.GP, 1, 32);
auto edx = X86Reg(X86Reg.GP, 2, 32);
auto ebx = X86Reg(X86Reg.GP, 3, 32);
auto esp = X86Reg(X86Reg.GP, 4, 32);
auto ebp = X86Reg(X86Reg.GP, 5, 32);
auto esi = X86Reg(X86Reg.GP, 6, 32);
auto edi = X86Reg(X86Reg.GP, 7, 32);
auto r8d = X86Reg(X86Reg.GP, 8, 32);
auto r9d = X86Reg(X86Reg.GP, 9, 32);
auto r10d = X86Reg(X86Reg.GP, 10, 32);
auto r11d = X86Reg(X86Reg.GP, 11, 32);
auto r12d = X86Reg(X86Reg.GP, 12, 32);
auto r13d = X86Reg(X86Reg.GP, 13, 32);
auto r14d = X86Reg(X86Reg.GP, 14, 32);
auto r15d = X86Reg(X86Reg.GP, 15, 32);
auto rax = X86Reg(X86Reg.GP, 0, 64);
auto rcx = X86Reg(X86Reg.GP, 1, 64);
auto rdx = X86Reg(X86Reg.GP, 2, 64);
auto rbx = X86Reg(X86Reg.GP, 3, 64);
auto rsp = X86Reg(X86Reg.GP, 4, 64);
auto rbp = X86Reg(X86Reg.GP, 5, 64);
auto rsi = X86Reg(X86Reg.GP, 6, 64);
auto rdi = X86Reg(X86Reg.GP, 7, 64);
auto r8 = X86Reg(X86Reg.GP, 8, 64);
auto r9 = X86Reg(X86Reg.GP, 9, 64);
auto r10 = X86Reg(X86Reg.GP, 10, 64);
auto r11 = X86Reg(X86Reg.GP, 11, 64);
auto r12 = X86Reg(X86Reg.GP, 12, 64);
auto r13 = X86Reg(X86Reg.GP, 13, 64);
auto r14 = X86Reg(X86Reg.GP, 14, 64);
auto r15 = X86Reg(X86Reg.GP, 15, 64);

// Instruction pointer, for ip-relative addressing
auto rip = X86Reg(X86Reg.IP, 5, 64);

// XMM SIMD registers
auto xmm0   = X86Reg(X86Reg.XMM, 0, 128);
auto xmm1   = X86Reg(X86Reg.XMM, 1, 128);
auto xmm2   = X86Reg(X86Reg.XMM, 2, 128);
auto xmm3   = X86Reg(X86Reg.XMM, 3, 128);
auto xmm4   = X86Reg(X86Reg.XMM, 4, 128);
auto xmm5   = X86Reg(X86Reg.XMM, 5, 128);
auto xmm6   = X86Reg(X86Reg.XMM, 6, 128);
auto xmm7   = X86Reg(X86Reg.XMM, 7, 128);
auto xmm8   = X86Reg(X86Reg.XMM, 8, 128);
auto xmm9   = X86Reg(X86Reg.XMM, 9, 128);
auto xmm10  = X86Reg(X86Reg.XMM,10, 128);
auto xmm11  = X86Reg(X86Reg.XMM,11, 128);
auto xmm12  = X86Reg(X86Reg.XMM,12, 128);
auto xmm13  = X86Reg(X86Reg.XMM,13, 128);
auto xmm14  = X86Reg(X86Reg.XMM,14, 128);
auto xmm15  = X86Reg(X86Reg.XMM,15, 128);

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
        X86Reg reg;

        // Memory location
        struct { uint memSize; X86Reg base; uint disp; X86Reg index; uint scale; }

        // Immediate value
        ulong imm;

        // TODO: link-time value
    };
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

class X86Instr : JITInstr
{
    immutable size_t MAX_OPNDS = 4;

    override size_t length()
    {
        // TODO
        return 0;
    }

    override void encode()
    {
        // TODO
    }

    override string toString()
    {
        // TODO
        return "";
    }

    X86OpPtr opcode;

    X86Opnd[MAX_OPNDS] opnds;
}

/**
Produce a string representation of this instruction
*/
/*
x86.Instruction.prototype.toString = function ()
{
    var str = '';

    str += this.mnem;

    for (var i = 0; i < this.opnds.length; ++i)
    {
        if (i === 0)
            str += ' ';
        else
            str += ', ';

        str += this.opnds[i].toString();
    }

    str += ';';

    return str;
}
*/

/**
Compute the length of an encoding of this instruction
*/
/*
x86.Instruction.prototype.compEncLen = function (enc, x86_64)
{
    // x86 instruction format:
    // prefix(es)  [REX] opcode  [XRM  [SIB]]  disp  imm

    // Flag to indicate the REX prefix is needed
    var rexNeeded = (enc.REX_W === 1);

    // Flags to indicate if the ModRM and SIB bytes needed
    var rmNeeded = false;
    var sibNeeded = false;

    // RM operand, if present
    var rmOpnd = null;

    // Displacement size required
    var dispSize = 0;

    // Immediate size required
    var immSize = 0;

    // For each operand
    for (var i = 0; i < this.opnds.length; ++i)
    {
        var opnd = this.opnds[i];

        var opndType = x86.opndType(enc.opnds[i]);
        var opndSize = x86.opndSize(enc.opnds[i]);

        if (opnd.rexNeeded)
            rexNeeded = true;

        if (opndType === 'imm' ||
            opndType === 'moffs' ||
            opndType === 'rel')
        {
            immSize = opndSize;
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
                    sibNeeded = true;

                if (opnd.dispSize > 0)
                    dispSize = opnd.dispSize;
            }
        }
    }

    // Total encoding size
    var size = 0;

    // Add the address-size prefix, if needed
    if (rmOpnd && x86_64 &&
        ((rmOpnd.base && rmOpnd.base.size === 32) ||
         (rmOpnd.index && rmOpnd.index.size === 32)))
        size += 1;

    // Add the operand-size prefix, if needed
    if (enc.szPref === true)
        size += 1;

    // Add the prefix size
    size += enc.prefix.length;

    // Add the REX prefix, if needed
    if (rexNeeded === true)
        size += 1;

    // Add the opcode size
    size += enc.opCode.length;

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
*/

/**
Find the shortest possible encoding for this instruction.
Returns null if no valid encoding is found
*/
/*
x86.Instruction.prototype.findEncoding = function (x86_64)
{
    // Best encoding found
    var bestEnc = null;
    var bestLen = 0xFFFF;

    // For each possible encoding
    ENC_LOOP:
    for (var i = 0; i < this.encodings.length; ++i)
    {
        //print('encoding #' + (i+1));

        var enc = this.encodings[i];

        // If we are in x86-64 and this encoding is not valid in that mode
        if (x86_64 === true && enc.x86_64 === false)
            continue ENC_LOOP;

        // If the number of operands does not match, skip this encoding
        if (enc.opnds.length !== this.opnds.length)
            continue ENC_LOOP;

        // For each operand
        for (var j = 0; j < this.opnds.length; ++j)
        {
            var opnd = this.opnds[j];

            var encOpnd = enc.opnds[j];

            var opndType = x86.opndType(encOpnd);
            var opndSize = x86.opndSize(encOpnd);

            // If this encoding requires REX but the operand is not
            // available under REX, skip this encoding
            if (enc.REX_W && !opnd.rexAvail)
                continue ENC_LOOP;

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
        }

        var len = this.compEncLen(enc, x86_64);

        //print('encoding length: ' + len);

        if (len < bestLen)
        {
            bestEnc = enc;
            bestLen = len;
        }
    }

    if (DEBUG === true && bestEnc === null)
        error('no valid ' + (x86_64? 64:32) + '-bit encoding for "' + this + '"');

    // Store the best encoding found
    this.encDesc = bestEnc;

    // Store the encoding length
    this.encLength = bestLen;
}
*/

/**
Get the length of this instruction
*/
/*
x86.Instruction.prototype.length = function (x86_64)
{
    // If no encoding is yet found, find one
    if (this.encDesc === null)
        this.findEncoding(x86_64);

    // Return the encoding length
    return this.encLength;
}
*/

/**
Encode the instruction into a byte array
*/
/*
x86.Instruction.prototype.encode = function (codeBlock, x86_64)
{
    // If no encoding is yet found, find one
    if (this.encDesc === null)
        this.findEncoding();

    // Get a reference to the encoding descriptor found
    var enc = this.encDesc;

    // Flag to indicate the REX prefix is needed
    var rexNeeded = (enc.REX_W === 1);

    // Flags to indicate if the ModRM and SIB bytes needed
    var rmNeeded = false;
    var sibNeeded = false;

    // r and r/m operands
    var rOpnd = null;
    var rmOpnd = null;

    // Immediate operand size and value
    var immSize = 0;
    var immVal = 0;

    // Displacement size and value
    var dispSize = 0;
    var dispVal = 0;

    // For each operand
    for (var i = 0; i < this.opnds.length; ++i)
    {
        var opnd = this.opnds[i];

        var opndType = x86.opndType(enc.opnds[i]);
        var opndSize = x86.opndSize(enc.opnds[i]);

        if (opnd.rexNeeded === true)
            rexNeeded = true;

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
    }

    // Get the index in the code block before the encoding
    var startIndex = codeBlock.writePos;

    // Add the address-size prefix, if needed
    if (rmOpnd && x86_64 &&
        ((rmOpnd.base && rmOpnd.base.size === 32) ||
         (rmOpnd.index && rmOpnd.index.size === 32)))
        codeBlock.writeByte(0x67);

    // Add the operand-size prefix, if needed
    if (enc.szPref === true)
        codeBlock.writeByte(0x66);

    // Write the prefix bytes to the code block
    for (var i = 0; i < enc.prefix.length; ++i)
        codeBlock.writeByte(enc.prefix[i]);

    // Add the REX prefix, if needed
    if (rexNeeded === true)
    {
        // 0 1 0 0 w r x b
        // w - 64-bit operand size flag
        // r - MODRM.reg extension
        // x - SIB.index extension
        // b - MODRM.rm or SIB.base extension

        var w = enc.REX_W;

        var r;
        if (rOpnd && rmOpnd)
            r = (rOpnd.regNo & 8)? 1:0;
        else
            r = 0;

        var x;
        if (sibNeeded && rmOpnd.index instanceof x86.Register)
            x = (rmOpnd.index.regNo & 8)? 1:0;
        else
            x = 0;

        var b;
        if (rmOpnd instanceof x86.Register)
            b = (rmOpnd.regNo & 8)? 1:0;
        else if (rOpnd && !rmOpnd)
            b = (rOpnd.regNo & 8)? 1:0;
        else if (rmOpnd && rmOpnd.base instanceof x86.Register)
            b = (rmOpnd.base.regNo & 8)? 1:0;
        else
            b = 0;

        // Encode and write the REX byte
        var rexByte = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
        codeBlock.writeByte(rexByte);
    }

    // If an opcode reg field is to be used
    if (rOpnd && !rmOpnd)
    {
        // Write the reg field into the opcode byte
        var opByte = enc.opCode[0] | (rOpnd.regNo & 7);
        codeBlock.writeByte(opByte);
    }
    else
    {
        // Write the opcode bytes to the code block
        for (var i = 0; i < enc.opCode.length; ++i)
            codeBlock.writeByte(enc.opCode[i]);
    }

    // Add the ModR/M byte, if needed
    if (rmNeeded)
    {
        // MODRM.mod (2 bits)
        // MODRM.reg (3 bits)
        // MODRM.rm  (3 bits)

        assert (
            !(enc.opExt && rOpnd),
            'opcode extension and register operand present'
        );

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
    }

    // Add the SIB byte, if needed
    if (sibNeeded)
    {
        // SIB.scale (2 bits)
        // SIB.index (3 bits)
        // SIB.base  (3 bits)

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
    }

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

    // Get the index in the code block after the encoding
    var endIndex = codeBlock.writePos;

    // Compute the length of the data written
    var wrtLength = endIndex - startIndex;

    if (DEBUG === true && wrtLength !== this.encLength)
    {
        error(
            'encoding length:\n' +
            wrtLength + '\n' +
            'does not match expected length:\n' +
            this.encLength + '\n' +
            'for:\n' +
            this
        );
    }
}
*/

