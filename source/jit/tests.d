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

module jit.tests;

import std.stdio;
import std.string;
import std.format;
import std.stdint;
import jit.x86;
import jit.codeblock;

/// Code generation function for testing
alias CodeGenFn = void delegate(CodeBlock);

/**
Test x86 instruction encodings
*/
unittest
{
    writefln("machine code generation");

    // Test encodings for 32-bit and 64-bit
    void test(CodeGenFn codeFunc, string enc64)
    {
        assert (
            enc64.length > 0 && enc64.length % 2 == 0,
            "encoding string should have multiple of 2 length"
        );

        // Compute the number of bytes in the encoding
        auto numBytes = enc64.length / 2;

        // Create a code block to write the encoding into
        auto encBlock = new CodeBlock(1 << 16, false);

        // Write the encoding bytes into the code block
        for (size_t i = 0; i < numBytes; ++i)
        {
            int num;
            auto slice = enc64[(2*i)..(2*i)+2];
            formattedRead(slice, "%x", &num);
            encBlock.writeByte(cast(ubyte)num);
        }

        // Generate the code to a machine code block
        auto codeBlock = new CodeBlock(1 << 16, true);
        codeFunc(codeBlock);
        codeBlock.linkLabels();

        // Report an encoding error
        void encError()
        {
            throw new Error(
                format(
                    "invalid encoding, produced:\n" ~
                    "%s (%s bytes)\n" ~
                    "expected:\n" ~
                    "%s (%s bytes)\n",
                    codeBlock.toString(),
                    codeBlock.getWritePos(),
                    encBlock.toString(),
                    encBlock.getWritePos()
                )
           );
        }

        // Compare the encoding sizes
        if (codeBlock.getWritePos() != encBlock.getWritePos())
            encError();

        // Compare all bytes in the encoding
        for (size_t i = 0; i < encBlock.getWritePos(); ++i)
        {
            if (codeBlock.readByte(i) != encBlock.readByte(i))
                encError();
        }
    }

    // add
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CL), X86Opnd(3)); },
        "80C103"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CL), X86Opnd(BL)); },
        "00D9"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CL), X86Opnd(SPL)); },
        "4000E1"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CX), X86Opnd(BX)); },
        "6601D9"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(RAX), X86Opnd(RBX)); },
        "4801D8"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(ECX), X86Opnd(EDX)); },
        "01D1"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(R14)); },
        "4C01F2"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(64, RAX), X86Opnd(RDX)); },
        "480110"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(64, RAX)); },
        "480310"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(64, RAX, 8)); },
        "48035008"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(64, RAX, 255)); },
        "480390FF000000"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(64, RAX, 127), X86Opnd(255)); },
        "4881407FFF000000"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(32, RAX), X86Opnd(EDX)); },
        "0110"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(RSP), X86Opnd(8)); },
        "4883C408"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(ECX), X86Opnd(8)); },
        "83C108"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(ECX), X86Opnd(255)); },
        "81C1FF000000"
    );

    // addsd
    test(
        delegate void (CodeBlock cb) { cb.addsd(X86Opnd(XMM3), X86Opnd(XMM5)); },
        "F20F58DD"
    );
    test(
        delegate void (CodeBlock cb) { cb.addsd(X86Opnd(XMM15), X86Opnd(64, R13, 5)); },
        "F2450F587D05"
    );
    test(
        delegate void (CodeBlock cb) { cb.addsd(X86Opnd(XMM15), X86Opnd(64, R11)); },
        "F2450F583B"
    );

    // and
    test(
        delegate void (CodeBlock cb) { cb.and(X86Opnd(EBP), X86Opnd(R12D)); },
        "4421E5"
    );

    // call
    /*
    test(
        delegate void (CodeBlock cb) { auto l = cb.label("foo"); cb.instr(CALL, l); },
        "E8FBFFFFFF"
    );
    */
    test(
        delegate void (CodeBlock cb) { cb.call(X86Opnd(RAX)); },
        "FFD0"
    );

    test(
        delegate void (CodeBlock cb) { cb.call(X86Opnd(64, RSP, 8)); },
        "FF542408"
    );

    // cmovcc
    test(
        delegate void (CodeBlock cb) { cb.cmovg(ESI, X86Opnd(EDI)); }, 
        "0F4FF7"
    );
    test(
        delegate void (CodeBlock cb) { cb.cmovg(ESI, X86Opnd(32, RBP, 12)); }, 
        "0F4F750C"
    );
    test(
        delegate void (CodeBlock cb) { cb.cmovl(EAX, X86Opnd(ECX)); }, 
        "0F4CC1"
    );
    test(
        delegate void (CodeBlock cb) { cb.cmovl(RBX, X86Opnd(RBP)); }, 
        "480F4CDD"
    );
    test(
        delegate void (CodeBlock cb) { cb.cmovle(ESI, X86Opnd(32, RSP, 4)); }, 
        "0F4E742404"
    );

    // cmp
    test(
        delegate void (CodeBlock cb) { cb.cmp(X86Opnd(CL), X86Opnd(DL)); },
        "38D1"
    );   
    test(
        delegate void (CodeBlock cb) { cb.cmp(X86Opnd(ECX), X86Opnd(EDI)); },
        "39F9"
    );   
    test(
        delegate void (CodeBlock cb) { cb.cmp(X86Opnd(RDX), X86Opnd(64, R12)); },
        "493B1424"
    );
    test(
        delegate void (CodeBlock cb) { cb.cmp(X86Opnd(RAX), X86Opnd(2)); },
        "4883F802"
    );   

    // cqo
    test(
        delegate void (CodeBlock cb) { cb.cqo(); },
        "4899"
    );

    // cvtsd2si
    test(
        delegate void (CodeBlock cb) { cb.cvtsd2si(X86Opnd(ECX), X86Opnd(XMM6)); }, 
        "F20F2DCE"
    );
    test(
        delegate void (CodeBlock cb) { cb.cvtsd2si(X86Opnd(RDX), X86Opnd(XMM4)); },
        "F2480F2DD4"
    );

    // cvtsi2sd
    test(
        delegate void (CodeBlock cb) { cb.cvtsi2sd(X86Opnd(XMM7), X86Opnd(EDI)); }, 
        "F20F2AFF"
    );
    test(
        delegate void (CodeBlock cb) { cb.cvtsi2sd(X86Opnd(XMM7), X86Opnd(64, RCX)); },
        "F2480F2A39"
    );

    // dec
    test(
        delegate void (CodeBlock cb) { cb.dec(X86Opnd(CX)); }, 
        "66FFC9"
    );
    test(
        delegate void (CodeBlock cb) { cb.dec(X86Opnd(EDX)); }, 
        "FFCA"
    );

    // div
    test(
        delegate void (CodeBlock cb) { cb.div(X86Opnd(EDX)); }, 
        "F7F2"
    );
    test(
        delegate void (CodeBlock cb) { cb.div(X86Opnd(32, RSP, -12)); }, 
        "F77424F4"
    );

    // divsd
    test(
        delegate void (CodeBlock cb) { cb.divsd(X86Opnd(XMM0), X86Opnd(XMM1)); },
        "F20F5EC1"
    );

    /*
    // fst
    test(
        delegate void (CodeBlock cb) { cb.instr(FSTP, new X86Mem(64, RSP, -16)); },
        "",
        "DD5C24F0"
    );
    */

    // imul
    test(
        delegate void (CodeBlock cb) { cb.imul(X86Opnd(EDX), X86Opnd(ECX)); },
        "0FAFD1"
    );
    test(
        delegate void (CodeBlock cb) { cb.imul(X86Opnd(RSI), X86Opnd(RDI)); },
        "480FAFF7"
    );
    test(
        delegate void (CodeBlock cb) { cb.imul(X86Opnd(R14), X86Opnd(R9)); }, 
        "4D0FAFF1"
    );
    test(
        delegate void (CodeBlock cb) { cb.imul(X86Opnd(EAX), X86Opnd(32, RSP, 8)); },
        "0FAF442408"
    );
    test(
        delegate void (CodeBlock cb) { cb.imul(X86Opnd(RCX), X86Opnd(RAX), X86Opnd(3)); },
        "486BC803"
    );
    test(
        delegate void (CodeBlock cb) { cb.imul(X86Opnd(RCX), X86Opnd(RAX), X86Opnd(255)); },
        "4869C8FF000000"
    );

    // inc
    test(
        delegate void (CodeBlock cb) { cb.inc(X86Opnd(BL)); },
        "FEC3"
    );
    test(
        delegate void (CodeBlock cb) { cb.inc(X86Opnd(ESP)); },
        "FFC4"
    );
    test(
        delegate void (CodeBlock cb) { cb.inc(X86Opnd(32, RSP, 0)); },
        "FF0424"
    );
    test(
        delegate void (CodeBlock cb) { cb.inc(X86Opnd(64, RSP, 4)); },
        "48FF442404"
    );

    // jcc
    test(
        delegate void (CodeBlock cb) { auto l = cb.label(Label.LOOP); cb.jge(l); },
        "0F8DFAFFFFFF"
    );
    test(
        delegate void (CodeBlock cb) { cb.label(Label.LOOP); cb.jo(Label.LOOP); },
        "0F80FAFFFFFF"
    );

    // jmp
    test(
        delegate void (CodeBlock cb) { cb.jmp(X86Opnd(R12)); },
        "41FFE4"
    );

    /*
    // lea
    test(
        delegate void (CodeBlock cb) {cb.instr(LEA, EBX, new X86Mem(32, RSP, 4)); },
        "8D5C2404"
    );
    */

    // mov
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(7)); },
        "B807000000"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(-3)); }, 
        "B8FDFFFFFF"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(R15), X86Opnd(3)); }, 
        "49BF0300000000000000"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(EBX)); }, 
        "89D8"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(ECX)); }, 
        "89C8"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(EDX), X86Opnd(32, RBX, 128)); }, 
        "8B9380000000"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(AL), X86Opnd(8, RCX, 0, 1, RDX)); },
        "8A0411"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(CL), X86Opnd(R9L)); }, 
        "4488C9"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(RBX), X86Opnd(RAX)); }, 
        "4889C3"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(RDI), X86Opnd(RBX)); },
        "4889DF"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(SIL), X86Opnd(11)); },
        "40B60B"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(8, RSP), X86Opnd(-3)); },
        "C60424FD"
    );

    /*
    // movapd
    test(
        delegate void (CodeBlock cb) { cb.instr(MOVAPD, XMM5, new X86Mem(128, ESP)); },
        "660F282C24",
        "67660F282C24"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(MOVAPD, new X86Mem(128, ESP, -8), XMM6); },
        "660F297424F8",
        "67660F297424F8"
    );
    */

    // movsd
    test(
        delegate void (CodeBlock cb) { cb.movsd(X86Opnd(XMM3), X86Opnd(XMM5)); },
        "F20F10DD"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsd(X86Opnd(XMM3), X86Opnd(64, RSP)); },
        "F20F101C24"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsd(X86Opnd(64, RSP), X86Opnd(XMM14)); },
        "F2440F113424"
    );

    // movq
    test(
        delegate void (CodeBlock cb) { cb.movq(X86Opnd(XMM1), X86Opnd(RCX)); },
        "66480F6EC9"
    );
    test(
        delegate void (CodeBlock cb) { cb.movq(X86Opnd(R12), X86Opnd(XMM8)); },
        "664D0F7EC4"
    );

    // movsx
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(AX), X86Opnd(AL)); },
        "660FBEC0"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(EDX), X86Opnd(AL)); },
        "0FBED0"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(RAX), X86Opnd(BL)); },
        "480FBEC3"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(ECX), X86Opnd(AX)); },
        "0FBFC8"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(R11), X86Opnd(CL)); },
        "4C0FBED9"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(R10), X86Opnd(32, RSP, 12)); },
        "4C6354240C"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(RAX), X86Opnd(8, RSP, 0)); },
        "480FBE0424"
    );

    /*
    // movupd
    test(
        delegate void (CodeBlock cb) { cb.instr(MOVUPD, XMM7, new X86Mem(128, RSP)); },
        "660F103C24"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(MOVUPD, new X86Mem(128, RCX, -8), XMM9); },
        "66440F1149F8"
    );
    */

    // movzx
    test(
        delegate void (CodeBlock cb) { cb.movzx(X86Opnd(SI), X86Opnd(BL)); },
        "660FB6F3"
    );
    test(
        delegate void (CodeBlock cb) { cb.movzx(X86Opnd(ECX), X86Opnd(AL)); },
        "0FB6C8"
    );
    test(
        delegate void (CodeBlock cb) { cb.movzx(X86Opnd(EDI), X86Opnd(AL)); },
        "0FB6F8"
    );
    test(
        delegate void (CodeBlock cb) { cb.movzx(X86Opnd(EBP), X86Opnd(AL)); },
        "0FB6E8"
    );
    test(
        delegate void (CodeBlock cb) { cb.movzx(X86Opnd(RCX), X86Opnd(BL)); },
        "480FB6CB"
    );
    test(
        delegate void (CodeBlock cb) { cb.movzx(X86Opnd(ECX), X86Opnd(AX)); },
        "0FB7C8"
    );
    test(
        delegate void (CodeBlock cb) { cb.movzx(X86Opnd(R11), X86Opnd(CL)); },
        "4C0FB6D9"
    );

    // mul
    test(
        delegate void (CodeBlock cb) { cb.mul(X86Opnd(EDX)); }, 
        "F7E2"
    );
    test(
        delegate void (CodeBlock cb) { cb.mul(X86Opnd(R15)); },
        "49F7E7"
    );
    test(
        delegate void (CodeBlock cb) { cb.mul(X86Opnd(R10D)); },
        "41F7E2"
    );

    // nop
    test(
        delegate void (CodeBlock cb) { cb.nop(); }, 
        "90"
    );

    // not
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(AX)); }, 
        "66F7D0"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(EAX)); }, 
        "F7D0"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(RAX)); }, 
        "48F7D0"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(R11)); }, 
        "49F7D3"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RAX)); }, 
        "F710"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSI)); },
        "F716"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RDI)); }, 
        "F717"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RDX, 55)); },
        "F75237"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RDX, 1337)); },
        "F79239050000"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RDX, -55)); },
        "F752C9"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RDX, -555)); },
        "F792D5FDFFFF"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RAX, 0, 1, RBX)); }, 
        "F71418"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RAX, 0, 1, R12)); }, 
        "42F71420"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 0, 1, R12)); }, 
        "43F71427"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 5, 1, R12)); }, 
        "43F7542705"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 5, 8, R12)); }, 
        "43F754E705"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 5, 8, R13)); }, 
        "43F754EF05"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(64, R12)); }, 
        "49F71424"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R12, 5, 4, R9)); }, 
        "43F7548C05"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R12, 301, 4, R9)); }, 
        "43F7948C2D010000"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RAX, 5, 4, RDX)); }, 
        "F7549005"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(64, RAX, 0, 2, RDX)); },
        "48F71450"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSP, 301)); },
        "F794242D010000"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSP)); },
        "F71424"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSP, 0, 1, RBX)); },
        "F7141C"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSP, 3, 1, RBX)); },
        "F7541C03"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSP, 3)); },
        "F7542403"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RBP)); },
        "F75500"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RBP, 13)); },
        "F7550D"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RBP, 13, 1, RDX)); },
        "F754150D"
    );
    /*
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RIP)); },
        "F71500000000"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RIP, 13)); },
        "F7150D000000"
    );
    */

    // or
    test(
        delegate void (CodeBlock cb) { cb.or(X86Opnd(EDX), X86Opnd(ESI)); },
        "09F2"
    );

    // pop
    test(
        delegate void (CodeBlock cb) { cb.pop(RAX); }, 
        "58"
    );
    test(
        delegate void (CodeBlock cb) { cb.pop(RBX); },
        "5B"
    );
    test(
        delegate void (CodeBlock cb) { cb.pop(RSP); },
        "5C"
    );
    test(
        delegate void (CodeBlock cb) { cb.pop(RBP); },
        "5D"
    );
    test(
        delegate void (CodeBlock cb) { cb.pop(R12); },
        "415C"
    );

    // push
    test(
        delegate void (CodeBlock cb) { cb.push(RAX); },
        "50"
    );
    test(
        delegate void (CodeBlock cb) { cb.push(RBX); },
        "53"
    );
    test(
        delegate void (CodeBlock cb) { cb.push(R12); },
        "4154"
    );

    // pxor
    test(
        delegate void (CodeBlock cb) { cb.pxor(XMM0.opnd, XMM1.opnd); },
        "660FEFC1"
    );

    // ret
    test(
        delegate void (CodeBlock cb) { cb.ret(); },
        "C3"
    );
    /*
    test(
        delegate void (CodeBlock cb) { cb.instr(RET, 5); },
        "C20500"
    );
    */

    /*
    // roundsd
    test(
        delegate void (CodeBlock cb) { cb.instr(ROUNDSD, XMM2, XMM5, 0); },
        "660F3A0BD500"
    );
    */

    // sal
    test(
        delegate void (CodeBlock cb) { cb.sal(X86Opnd(CX), X86Opnd(1)); },
        "66D1E1"
    );
    test(
        delegate void (CodeBlock cb) { cb.sal(X86Opnd(ECX), X86Opnd(1)); },
        "D1E1"
    );
    test(
        delegate void (CodeBlock cb) { cb.sal(X86Opnd(EBP), X86Opnd(5)); },
        "C1E505"
    );
    test(
        delegate void (CodeBlock cb) { cb.sal(X86Opnd(32, RSP, 68), X86Opnd(1)); },
        "D1642444"  
    );

    // sar
    test(
        delegate void (CodeBlock cb) { cb.sar(X86Opnd(EDX), X86Opnd(1)); },
        "D1FA"
    );

    // shr
    test(
        delegate void (CodeBlock cb) { cb.shr(X86Opnd(R14), X86Opnd(7)); },
        "49C1EE07"
    );

    // sqrtsd
    test(
        delegate void (CodeBlock cb) { cb.sqrtsd(X86Opnd(XMM2), X86Opnd(XMM6)); },
        "F20F51D6"
    );

    // sub
    test(
        delegate void (CodeBlock cb) { cb.sub(X86Opnd(EAX), X86Opnd(1)); },
        "83E801"
    );
    test(
        delegate void (CodeBlock cb) { cb.sub(X86Opnd(RAX), X86Opnd(2)); },
        "4883E802"
    );

    /*
    // test
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, AL, 4); },
        "A804"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, CL, 255); },
        "F6C1FF"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, DL, 7); },
        "F6C207"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, DIL, 9); },
        "",
        "40F6C709"
    );
    */

    // ucomisd
    test(
        delegate void (CodeBlock cb) { cb.ucomisd(X86Opnd(XMM3), X86Opnd(XMM5)); },
        "660F2EDD"
    );
    test(
        delegate void (CodeBlock cb) { cb.ucomisd(X86Opnd(XMM11), X86Opnd(XMM13)); },
        "66450F2EDD"
    );

    /*
    // xchg
    test(
        delegate void (CodeBlock cb) { cb.instr(XCHG, AX, DX); }, 
        "6692"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(XCHG, EAX, EDX); }, 
        "92"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(XCHG, RAX, R15); },
        "4997"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(XCHG, R14, R15); }, 
        "4D87FE"
    );
    */

    // xor
    test(
        delegate void (CodeBlock cb) { cb.xor(X86Opnd(EAX), X86Opnd(EAX)); },
        "31C0"
    );
}

/// Test function pointer type
alias TestFn = int64_t function();

/**
Test the execution of x86 code snippets
*/
unittest
{
    writefln("machine code execution");

    // Test the execution of a piece of code
    void test(CodeGenFn genFunc, int64_t retVal)
    {
        // Generate the code to a machine code block
        auto codeBlock = new CodeBlock(1 << 16, true);
        genFunc(codeBlock);
        codeBlock.linkLabels();

        //writeln("\n", execBlock, "\n");

        // Execute the generated code
        auto testFun = cast(TestFn)codeBlock.getAddress();
        //writefln("calling %s", testFun);
        auto ret = testFun();
        //writefln("returned");

        //writefln("ret: %s", ret);

        if (ret != retVal)
        {
            throw new Error(
                format(
                    "invalid return value for:\n" ~
                    "\n" ~
                    "%s\n" ~
                    "\n" ~
                    "got:\n" ~
                    "%s\n" ~
                    "expected:\n" ~
                    "%s",
                    codeBlock.toString(),
                    ret,
                    retVal
                )
            );
        }
    }

    // Trivial return 3
    test(
        delegate void (CodeBlock cb) 
        {
            cb.mov(X86Opnd(RAX), X86Opnd(3));
            cb.ret();
        },
        3
    );

    // Loop until 10
    test(
        delegate void (CodeBlock cb) 
        {
            cb.mov(X86Opnd(RAX), X86Opnd(0));
            cb.label(Label.LOOP);
            cb.add(X86Opnd(RAX), X86Opnd(1));
            cb.cmp(X86Opnd(RAX), X86Opnd(10));
            cb.jb(Label.LOOP);
            cb.ret();
        },
        10
    );

    /*
    // IP-relative addressing
    test(
        delegate void (CodeBlock cb) 
        {
            auto CODE = new Label("CODE");
            cb.instr(JMP, CODE);
            auto MEMLOC = cb.label("MEMLOC");
            cb.addInstr(new IntData(77, 32));
            cb.addInstr(new IntData(55, 32));
            cb.addInstr(new IntData(11, 32));
            cb.addInstr(CODE);
            cb.mov(EAX, new X86IPRel(32, MEMLOC, 4));
            cb.instr(RET);
        },
        55
    );
    */

    // Arithmetic
    test(
        delegate void (CodeBlock cb)
        {
            cb.push(RBX);
            cb.push(RCX);
            cb.push(RDX);

            cb.mov(RAX, 4);                     // a = 4
            cb.mov(RBX, 5);                     // b = 5
            cb.sub(X86Opnd(RAX), X86Opnd(RBX)); // a = -1

            cb.mov(RDX, -2);                    // d = -2
            cb.imul(X86Opnd(RDX), X86Opnd(RAX));// d = 2

            cb.mov(RAX, RDX);                   // a = 2

            cb.pop(RDX);
            cb.pop(RCX);
            cb.pop(RBX);

            cb.ret();
        },
        2
    );

    // Stack manipulation, sign extension
    test(
        delegate void (CodeBlock cb)
        {
            cb.sub(X86Opnd(RSP), X86Opnd(1));
            auto sloc = X86Opnd(8, RSP, 0);
            cb.mov(sloc, X86Opnd(-3));
            cb.movsx(X86Opnd(RAX), sloc);
            cb.add(X86Opnd(RSP), X86Opnd(1));
            cb.ret();
        },
        -3
    );
    
    // fib(20), function calls
    test(
        delegate void (CodeBlock cb)
        {
            auto COMP = Label.FUN1;
            auto FIB  = Label.FUN2;

            cb.push(RBX);
            cb.mov(X86Opnd(RAX), X86Opnd(20));
            cb.call(FIB);
            cb.pop(RBX);
            cb.ret();

            // FIB
            cb.label(FIB);
            cb.cmp(X86Opnd(RAX), X86Opnd(2));
            cb.jge(COMP);
            cb.ret();

            // COMP
            cb.label(COMP);
            cb.push(RAX);                       // store n
            cb.sub(X86Opnd(RAX), X86Opnd(1));   // RAX = n-1
            cb.call(FIB);                       // fib(n-1)
            cb.mov(X86Opnd(RBX), X86Opnd(RAX)); // RAX = fib(n-1)
            cb.pop(RAX);                        // RAX = n
            cb.push(RBX);                       // store fib(n-1)
            cb.sub(X86Opnd(RAX), X86Opnd(2));   // RAX = n-2
            cb.call(FIB);                       // fib(n-2)
            cb.pop(RBX);                        // RBX = fib(n-1)
            cb.add(X86Opnd(RAX), X86Opnd(RBX)); // RAX = fib(n-2) + fib(n-1)
            cb.ret();
        },
        6765
    );

    // SSE2 floating-point computation
    test(
        delegate void (CodeBlock cb)
        {
            cb.mov(X86Opnd(RAX), X86Opnd(2));
            cb.cvtsi2sd(X86Opnd(XMM0), X86Opnd(RAX));
            cb.mov(X86Opnd(RAX), X86Opnd(7));
            cb.cvtsi2sd(X86Opnd(XMM1), X86Opnd(RAX));
            cb.addsd(X86Opnd(XMM0), X86Opnd(XMM1));
            cb.cvtsd2si(X86Opnd(RAX), X86Opnd(XMM0));
            cb.ret();
        },
        9
    );

    // Floating-point comparison
    test(
        delegate void (CodeBlock cb) 
        {
            cb.mov(X86Opnd(RAX), X86Opnd(10));
            cb.cvtsi2sd(X86Opnd(XMM2), X86Opnd(RAX));   // XMM2 = 10
            cb.mov(X86Opnd(RAX), X86Opnd(1));
            cb.cvtsi2sd(X86Opnd(XMM1), X86Opnd(RAX));   // XMM1 = 1
            cb.mov(X86Opnd(RAX), X86Opnd(0));
            cb.cvtsi2sd(X86Opnd(XMM0), X86Opnd(RAX));   // XMM0 = 0
            cb.label(Label.LOOP);
            cb.addsd(X86Opnd(XMM0), X86Opnd(XMM1));
            cb.ucomisd(X86Opnd(XMM0), X86Opnd(XMM2));
            cb.jbe(Label.LOOP);
            cb.cvtsd2si(X86Opnd(RAX), X86Opnd(XMM0));
            cb.ret();
        },
        11
    );
}

