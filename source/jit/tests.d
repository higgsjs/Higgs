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
import jit.assembler;

/// Code generation function for testing
alias void delegate(ASMBlock) CodeGenFn;

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
        auto encBlock = new CodeBlock(numBytes);

        // Write the encoding bytes into the code block
        for (size_t i = 0; i < numBytes; ++i)
        {
            int num;
            auto slice = enc64[(2*i)..(2*i)+2];
            formattedRead(slice, "%x", &num);
            encBlock.writeByte(cast(ubyte)num);
        }

        // Generate the code to a machine code block
        auto codeBlock = new ASMBlock(numBytes, true);
        codeFunc(codeBlock);
        codeBlock.link();

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
                    encBlock.length
                )
           );
        }

        // Compare all bytes in the block
        for (size_t i = 0; i < codeBlock.length; ++i)
        {
            if (codeBlock.readByte(i) != encBlock.readByte(i))
                encError();
        }
    }

    // add  
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(CL), X86Opnd(3)); },
        "80C103"
    );   
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(CL), X86Opnd(BL)); },
        "00D9"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(CL), X86Opnd(SPL)); },
        "4000E1"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(CX), X86Opnd(BX)); },
        "6601D9"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(RAX), X86Opnd(RBX)); },
        "4801D8"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(ECX), X86Opnd(EDX)); },
        "01D1"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(R14)); },
        "4C01F2"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(64, RAX), X86Opnd(RDX)); },
        "480110"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(64, RAX)); },
        "480310"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(64, RAX, 8)); },
        "48035008"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(RDX), X86Opnd(64, RAX, 255)); },
        "480390FF000000"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(64, RAX, 127), X86Opnd(255)); },
        "4881407FFF000000"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(32, RAX), X86Opnd(EDX)); },
        "0110"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(RSP), X86Opnd(8)); },
        "4883C408"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(ECX), X86Opnd(8)); },
        "83C108"
    );
    test(
        delegate void (ASMBlock cb) { cb.add(X86Opnd(ECX), X86Opnd(255)); },
        "81C1FF000000"
    );

    /*
    // addsd
    test(
        delegate void (ASMBlock cb) { cb.instr(ADDSD, XMM3, XMM5); },
        "F20F58DD"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(ADDSD, XMM15, new X86Mem(64, R13, 5)); },
        "",
        "F2450F587D05"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(ADDSD, XMM15, new X86Mem(64, R11)); },
        "",
        "F2450F583B"
    );
    */

    // and
    test(
        delegate void (ASMBlock cb) { cb.and(X86Opnd(EBP), X86Opnd(R12D)); },
        "4421E5"
    );

    // call
    /*
    test(
        delegate void (ASMBlock cb) { auto l = cb.label("foo"); cb.instr(CALL, l); },
        "E8FBFFFFFF"
    );
    */
    test(
        delegate void (ASMBlock cb) { cb.call(X86Opnd(RAX)); },
        "FFD0"
    );

    test(
        delegate void (ASMBlock cb) { cb.call(X86Opnd(64, RSP, 8)); },
        "FF542408"
    );

    // cmovcc
    test(
        delegate void (ASMBlock cb) { cb.cmovg(ESI, X86Opnd(EDI)); }, 
        "0F4FF7"
    );
    test(
        delegate void (ASMBlock cb) { cb.cmovg(ESI, X86Opnd(32, RBP, 12)); }, 
        "0F4F750C"
    );
    test(
        delegate void (ASMBlock cb) { cb.cmovl(EAX, X86Opnd(ECX)); }, 
        "0F4CC1"
    );
    test(
        delegate void (ASMBlock cb) { cb.cmovl(RBX, X86Opnd(RBP)); }, 
        "480F4CDD"
    );
    test(
        delegate void (ASMBlock cb) { cb.cmovle(ESI, X86Opnd(32, RSP, 4)); }, 
        "0F4E742404"
    );

    // cmp
    test(
        delegate void (ASMBlock cb) { cb.cmp(X86Opnd(CL), X86Opnd(DL)); },
        "38D1"
    );   
    test(
        delegate void (ASMBlock cb) { cb.cmp(X86Opnd(ECX), X86Opnd(EDI)); },
        "39F9"
    );   
    test(
        delegate void (ASMBlock cb) { cb.cmp(X86Opnd(RDX), X86Opnd(64, R12)); },
        "493B1424"
    );
    test(
        delegate void (ASMBlock cb) { cb.cmp(X86Opnd(RAX), X86Opnd(2)); },
        "4883F802"
    );   

    // cqo
    test(
        delegate void (ASMBlock cb) { cb.cqo(); },
        "4899"
    );

    /*
    // cvtsd2si
    test(
        delegate void (ASMBlock cb) { cb.instr(CVTSD2SI, ECX, XMM6); }, 
        "F20F2DCE"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(CVTSD2SI, RDX, XMM4); },
        "",
        "F2480F2DD4"
    );

    // cvtsi2sd
    test(
        delegate void (ASMBlock cb) { cb.instr(CVTSI2SD, XMM7, EDI); }, 
        "F20F2AFF"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(CVTSI2SD, XMM7, new X86Mem(64, RCX)); },
        "",
        "F2480F2A39"
    );

    // dec
    test(
        delegate void (ASMBlock cb) { cb.instr(DEC, CX); }, 
        "6649",
        "66FFC9"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(DEC, EDX); }, 
        "4A",
        "FFCA"
    );

    // div
    test(
        delegate void (ASMBlock cb) { cb.instr(DIV, EDX); }, 
        "F7F2"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(DIV, new X86Mem(32, ESP, -12)); }, 
        "F77424F4",
        "67F77424F4"
    );

    // fst
    test(
        delegate void (ASMBlock cb) { cb.instr(FSTP, new X86Mem(64, RSP, -16)); },
        "",
        "DD5C24F0"
    );

    // imul
    test(
        delegate void (ASMBlock cb) { cb.instr(IMUL, EDX, ECX); },
        "0FAFD1"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(IMUL, RSI, RDI); },
        "",
        "480FAFF7"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(IMUL, R14, R9); }, 
        "", 
        "4D0FAFF1"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(IMUL, EAX, new X86Mem(32, ESP, 8)); },
        "0FAF442408",
        "670FAF442408"
    );

    // inc
    test(
        delegate void (ASMBlock cb) { cb.instr(INC, BL); },
        "FEC3", 
        "FEC3"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(INC, ESP); },
        "44",
        "FFC4"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(INC, new X86Mem(32, ESP, 0)); },
        "FF0424",
        "67FF0424"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(INC, new X86Mem(64, RSP, 4)); },
        "",
        "48FF442404"
    );
    */

    // jcc
    test(
        delegate void (ASMBlock cb) { auto l = cb.label(Label.LOOP); cb.jge(l); },
        "0F8DFAFFFFFF"
    );
    test(
        delegate void (ASMBlock cb) { cb.label(Label.LOOP); cb.jo(Label.LOOP); },
        "0F80FAFFFFFF"
    );

    // jmp
    test(
        delegate void (ASMBlock cb) { cb.jmp(X86Opnd(R12)); },
        "41FFE4"
    );

    /*
    // lea
    test(
        delegate void (ASMBlock cb) {cb.instr(LEA, EBX, new X86Mem(32, RSP, 4)); },
        "8D5C2404"
    );
    */

    // mov
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(7)); },
        "B807000000"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(-3)); }, 
        "B8FDFFFFFF"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(EBX)); }, 
        "89D8"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(EAX), X86Opnd(ECX)); }, 
        "89C8"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(EDX), X86Opnd(32, RBX, 128)); }, 
        "8B9380000000"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(AL), X86Opnd(8, RCX, 0, 1, RDX)); },
        "8A0411"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(CL), X86Opnd(R9L)); }, 
        "4488C9"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(RBX), X86Opnd(RAX)); }, 
        "4889C3"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(RDI), X86Opnd(RBX)); },
        "4889DF"
    );
    test(
        delegate void (ASMBlock cb) { cb.mov(X86Opnd(SIL), X86Opnd(11)); },
        "40B60B"
    );

    /*
    // movapd
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVAPD, XMM5, new X86Mem(128, ESP)); },
        "660F282C24",
        "67660F282C24"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVAPD, new X86Mem(128, ESP, -8), XMM6); },
        "660F297424F8",
        "67660F297424F8"
    );

    // movsd
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSD, XMM3, XMM5); },
        "F20F10DD"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSD, XMM3, new X86Mem(64, ESP)); },
        "F20F101C24",
        "67F20F101C24"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSD, new X86Mem(64, RSP), XMM14); },
        "",
        "F2440F113424"
    );

    // movq
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVQ, XMM1, RCX); },
        ""
        "66480F6EC9"
    );

    // movsx
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSX, AX, AL); },
        "660FBEC0"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSX, EDX, AL); },
        "0FBED0"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSX, RAX, BL); },
        "",
        "480FBEC3"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSX, ECX, AX); },
        "0FBFC8"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSX, R11, CL); },
        "",
        "4C0FBED9"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVSXD, R10, new X86Mem(32, ESP, 12)); },
        "",
        "674C6354240C"
    );

    // movupd
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVUPD, XMM7, new X86Mem(128, RSP)); },
        "",
        "660F103C24"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVUPD, new X86Mem(128, RCX, -8), XMM9); },
        "",
        "66440F1149F8"
    );

    // movzx
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVZX, SI, BL); },
        "660FB6F3"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVZX, ECX, AL); },
        "0FB6C8"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVZX, EDI, AL); },
        "0FB6F8"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVZX, EBP, AL); },
        "0FB6E8"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVZX, RCX, BL); },
        "",
        "480FB6CB"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVZX, ECX, AX); },
        "0FB7C8"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MOVZX, R11, CL); },
        "",
        "4C0FB6D9"
    );

    // mul
    test(
        delegate void (ASMBlock cb) { cb.instr(MUL, EDX); }, 
        "F7E2"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MUL, R15); },
        "",
        "49F7E7"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(MUL, R10D); },
        "",
        "41F7E2"
    );

    // nop
    test(
        delegate void (ASMBlock cb) { cb.instr(NOP); }, 
        "90"
    );

    // not
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, AX); }, 
        "66F7D0"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, EAX); }, 
        "F7D0"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, RAX); }, 
        "", 
        "48F7D0"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, R11); }, 
        "", 
        "49F7D3"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EAX)); }, 
        "F710", 
        "67F710"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, ESI)); },
        "F716", 
        "67F716"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EDI)); }, 
        "F717", 
        "67F717"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EDX, 55)); },
        "F75237", 
        "67F75237"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EDX, 1337)); },
        "F79239050000", 
        "67F79239050000"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EDX, -55)); },
        "F752C9", 
        "67F752C9"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EDX, -555)); },
        "F792D5FDFFFF", 
        "67F792D5FDFFFF"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EAX, 0, EBX)); }, 
        "F71418", 
        "67F71418"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RAX, 0, RBX)); }, 
        "", 
        "F71418"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RAX, 0, R12)); }, 
        "", 
        "42F71420"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, R15, 0, R12)); }, 
        "", 
        "43F71427"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, R15, 5, R12)); }, 
        "", 
        "43F7542705"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, R15, 5, R12, 8)); }, 
        "", 
        "43F754E705"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, R15, 5, R13, 8)); }, 
        "", 
        "43F754EF05"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(64, R12)); }, 
        "",
        "49F71424"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, R12, 5, R9, 4)); }, 
        "", 
        "43F7548C05"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, R12, 301, R9, 4)); }, 
        "", 
        "43F7948C2D010000"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EAX, 5, EDX, 4)); }, 
        "F7549005",
        "67F7549005"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(64, EAX, 0, EDX, 2)); },
        "",
        "6748F71450"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, ESP)); },
        "F71424",
        "67F71424"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, ESP, 301)); }, 
        "F794242D010000",
        "67F794242D010000"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RSP)); },
        "",
        "F71424"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RSP, 0, RBX)); },
        "",
        "F7141C"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RSP, 3, RBX)); },
        "",
        "F7541C03"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RSP, 3)); },
        "",
        "F7542403"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EBP)); },
        "F75500",
        "67F75500"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EBP, 13)); },
        "F7550D",
        "67F7550D"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, EBP, 13, EDX)); },
        "F754150D",
        "67F754150D"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RIP)); },
        "",
        "F71500000000"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, RIP, 13)); },
        "",
        "F7150D000000"
    );
    test(delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, null, 0, R8, 8)); }, 
        "", 
        "42F714C500000000"
    );
    test(delegate void (ASMBlock cb) { cb.instr(NOT, new X86Mem(32, null, 5)); }, 
        "F71505000000", 
        "F7142505000000"
    );
    */

    // or
    test(
        delegate void (ASMBlock cb) { cb.or(X86Opnd(EDX), X86Opnd(ESI)); },
        "09F2"
    );

    // pop
    test(
        delegate void (ASMBlock cb) { cb.pop(RAX); }, 
        "58"
    );
    test(
        delegate void (ASMBlock cb) { cb.pop(RBX); },
        "5B"
    );
    test(
        delegate void (ASMBlock cb) { cb.pop(RSP); },
        "5C"
    );
    test(
        delegate void (ASMBlock cb) { cb.pop(RBP); },
        "5D"
    );

    // push
    test(
        delegate void (ASMBlock cb) { cb.push(RAX); },
        "50"
    );
    test(
        delegate void (ASMBlock cb) { cb.push(RBX); },
        "53"
    );
    /*
    test(
        delegate void (ASMBlock cb) { cb.push(1); },
        "6A01"
    );
    */

    // ret
    test(
        delegate void (ASMBlock cb) { cb.ret(); },
        "C3"
    );
    /*
    test(
        delegate void (ASMBlock cb) { cb.instr(RET, 5); },
        "C20500"
    );
    */

    /*
    // roundsd
    test(
        delegate void (ASMBlock cb) { cb.instr(ROUNDSD, XMM2, XMM5, 0); },
        "660F3A0BD500"
    );

    // sal
    test(
        delegate void (ASMBlock cb) { cb.instr(SAL, CX, 1); },
        "66D1E1"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(SAL, ECX, 1); },
        "D1E1"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(SAL, AL, CL); },
        "D2E0"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(SAL, EBP, 5); },
        "C1E505"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(SAL, new X86Mem(32, ESP, 68), 1); },
        "D1642444",
        "67D1642444"  
    );

    // sar
    test(
        delegate void (ASMBlock cb) { cb.instr(SAR, EDX, 1); },
        "D1FA"
    );

    // shr
    test(
        delegate void (ASMBlock cb) { cb.instr(SHR, R14, 7); },
        "",
        "49C1EE07"
    );

    // sqrtsd
    test(
        delegate void (ASMBlock cb) { cb.instr(SQRTSD, XMM2, XMM6); },
        "F20F51D6"
    );
    */

    // sub
    test(
        delegate void (ASMBlock cb) { cb.sub(X86Opnd(EAX), X86Opnd(1)); },
        "83E801"
    );
    test(
        delegate void (ASMBlock cb) { cb.sub(X86Opnd(RAX), X86Opnd(2)); },
        "4883E802"
    );

    /*
    // test
    test(
        delegate void (ASMBlock cb) { cb.instr(TEST, AL, 4); },
        "A804"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(TEST, CL, 255); },
        "F6C1FF"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(TEST, DL, 7); },
        "F6C207"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(TEST, DIL, 9); },
        "",
        "40F6C709"
    );

    // ucomisd
    test(
        delegate void (ASMBlock cb) { cb.instr(UCOMISD, XMM3, XMM5); },
        "660F2EDD"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(UCOMISD, XMM11, XMM13); },
        "",
        "66450F2EDD"
    );

    // xchg
    test(
        delegate void (ASMBlock cb) { cb.instr(XCHG, AX, DX); }, 
        "6692"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(XCHG, EAX, EDX); }, 
        "92"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(XCHG, RAX, R15); },
        "",
        "4997"
    );
    test(
        delegate void (ASMBlock cb) { cb.instr(XCHG, R14, R15); }, 
        "", 
        "4D87FE"
    );
    */

    // xor
    test(
        delegate void (ASMBlock cb) { cb.xor(X86Opnd(EAX), X86Opnd(EAX)); },
        "31C0"
    );

    /*
    // Simple loop from 0 to 10 (64-bit)
    test(
        delegate void (ASMBlock cb) 
        {
            cb.mov(RAX, 0);
            auto LOOP = cb.label("LOOP");
            cb.instr(ADD, RAX, 1);
            cb.instr(CMP, RAX, 10);
            cb.instr(JB, LOOP);
            cb.instr(RET);
        },
        "48C7C0000000004883C0014883F80A72F6C3"
    );
    */
}

/// Test function pointer type
alias int64_t function() TestFn;

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
        auto codeBlock = new ASMBlock(4096, true);
        genFunc(codeBlock);
        codeBlock.link();

        auto testFun = cast(TestFn)codeBlock.getAddress();

        //writefln("calling %s", testFun);

        auto ret = testFun();
        
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
        delegate void (ASMBlock cb) 
        {
            cb.mov(X86Opnd(RAX), X86Opnd(3));
            cb.ret();
        },
        3
    );

    // Loop until 10
    test(
        delegate void (ASMBlock cb) 
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
        delegate void (ASMBlock cb) 
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
        delegate void (ASMBlock cb)
        {
            cb.push(RBX);
            cb.push(RCX);
            cb.push(RDX);

            cb.mov(RAX, 4);                     // a = 4
            cb.mov(RBX, 5);                     // b = 5
            cb.sub(X86Opnd(RAX), X86Opnd(RBX)); // a = -1

            cb.mov(RDX, -2);                    // d = -2
            // TODO: implement imul
            //cb.imul(X86Opnd(RDX), X86Opnd(RAX));// d = 2

            cb.mov(RAX, RDX);                   // a = 2

            cb.pop(RDX);
            cb.pop(RCX);
            cb.pop(RBX);

            cb.ret();
        },
        2
    );

    /*
    // Stack manipulation, sign extension
    test(
        delegate void (ASMBlock cb)
        {
            cb.instr(SUB, RSP, 1);
            auto sloc = new X86Mem(8, RSP, 0);
            cb.mov(sloc, -3);
            cb.instr(MOVSX, RAX, sloc);
            cb.instr(ADD, RSP, 1);
            cb.instr(RET);
        },
        -3
    );
    
    // fib(20), function calls
    test(
        delegate void (ASMBlock cb)
        {
            auto COMP = new Label("COMP");
            auto FIB  = new Label("FIB");

            cb.push(RBX);
            cb.mov(RAX, 20);
            cb.instr(CALL, FIB);
            cb.pop(RBX);
            cb.instr(RET);

            // FIB
            cb.addInstr(FIB);
            cb.instr(CMP, RAX, 2);
            cb.instr(JGE, COMP);
            cb.instr(RET);

            // COMP
            cb.addInstr(COMP);
            cb.push(RAX);     // store n
            cb.instr(SUB, RAX, 1);   // RAX = n-1
            cb.instr(CALL, FIB);     // fib(n-1)
            cb.mov(RBX, RAX); // RAX = fib(n-1)
            cb.pop(RAX);      // RAX = n
            cb.push(RBX);     // store fib(n-1)
            cb.instr(SUB, RAX, 2);   // RAX = n-2
            cb.instr(CALL, FIB);     // fib(n-2)
            cb.pop(RBX);            // RBX = fib(n-1)
            cb.instr(ADD, RAX, RBX); // RAX = fib(n-2) + fib(n-1)
            cb.instr(RET);
        },
        6765
    );

    // SSE2 floating-point computation
    test(
        delegate void (ASMBlock cb)
        {
            cb.mov(RAX, 2);
            cb.instr(CVTSI2SD, XMM0, RAX);
            cb.mov(RAX, 7);
            cb.instr(CVTSI2SD, XMM1, RAX);
            cb.instr(ADDSD, XMM0, XMM1);
            cb.instr(CVTSD2SI, RAX, XMM0);
            cb.instr(RET);
        },
        9
    );

    // Floating-point comparison
    test(
        delegate void (ASMBlock cb) 
        {
            cb.mov(RAX, 10);
            cb.instr(CVTSI2SD, XMM2, RAX);   // XMM2 = 10
            cb.mov(RAX, 1);
            cb.instr(CVTSI2SD, XMM1, RAX);   // XMM1 = 1
            cb.mov(RAX, 0);
            cb.instr(CVTSI2SD, XMM0, RAX);   // XMM0 = 0
            auto LOOP = cb.label("LOOP");
            cb.instr(ADDSD, XMM0, XMM1);
            cb.instr(UCOMISD, XMM0, XMM2);
            cb.instr(JBE, LOOP);
            cb.instr(CVTSD2SI, RAX, XMM0);
            cb.instr(RET);
        },
        11
    );
    */
}

