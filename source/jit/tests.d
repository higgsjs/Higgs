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
import jit.codeblock;
import jit.encodings;

/// Code generation function for testing
alias void delegate(Assembler) CodeGenFn;

/**
Test x86 instruction encodings
*/
unittest
{
    writefln("machine code generation");

    // Test encodings for 32-bit and 64-bit
    void test(CodeGenFn codeFunc, string enc32, string enc64 = "")
    {
        if (enc64.length == 0)
            enc64 = enc32;

        assert (
            enc64.length % 2 == 0,
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
            formattedRead(enc64[(2*i)..(2*i)+2], "%x", &num);
            encBlock.writeByte(cast(ubyte)num);
        }

        // Create an assembler to write code into
        auto assembler = new Assembler();

        // Produce the assembly
        codeFunc(assembler);

        // Assemble the code to a machine code block (code only, no header)
        auto codeBlock = assembler.assemble();

        // Report an encoding error
        void encError()
        {
            throw new Error(
                xformat(
                    "invalid encoding for:\n" ~
                    "%s\n" ~
                    "\n" ~
                    "produced:\n" ~
                    "%s (%s bytes)\n" ~
                    "expected:\n" ~
                    "%s (%s bytes)\n",
                    assembler.toString(false),
                    codeBlock.toString(),
                    codeBlock.length,
                    encBlock.toString(),
                    encBlock.length
                )
           );
        }

        // Check that the encoding length matches
        if (codeBlock.length != encBlock.length)
            encError();

        // Compare all bytes in the block
        for (size_t i = 0; i < codeBlock.length; ++i)
        {
            if (codeBlock.readByte(i) != encBlock.readByte(i))
                encError();
        }
    }

    // add
    test(
        delegate void (Assembler a) { a.instr(ADD, AL, 3); },
        "0403"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, CL, BL); },
        "00D9"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, CL, SPL); },
        "",
        "4000E1"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, CX, BX); },
        "6601D9"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, RAX, RBX); },
        "",
        "4801D8"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, RDX, R14); },
        "",
        "4C01F2"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, EDX, new X86Mem(32, EAX)); },
        "0310",
        "670310"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, new X86Mem(32, EAX), EDX); },
        "0110",
        "670110"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, new X86Mem(64, RAX), RDX); },
        "", 
        "480110"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, new X86Mem(32, RAX), EDX); },
        "", 
        "0110"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, EAX, new X86Mem(32, ESP, 8)); }, 
        "03442408",
        "6703442408"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, new X86Mem(32, ESP, 8), 7); },
        "8344240807",
        "678344240807"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, RSP, 8); },
        "",
        "4883C408"
    );

    // addsd
    test(
        delegate void (Assembler a) { a.instr(ADDSD, XMM3, XMM5); },
        "F20F58DD"
    );
    test(
        delegate void (Assembler a) { a.instr(ADDSD, XMM15, new X86Mem(64, R13, 5)); },
        "",
        "F2450F587D05"
    );
    test(
        delegate void (Assembler a) { a.instr(ADDSD, XMM15, new X86Mem(64, R11)); },
        "",
        "F2450F583B"
    );

    // and
    test(
        delegate void (Assembler a) { a.instr(AND, EBP, R12D); }, 
        "", 
        "4421E5"
    );

    // call
    test(
        delegate void (Assembler a) { auto l = a.label("foo"); a.instr(CALL, l); },
        "E8FBFFFFFF"
    );

    // cmovcc
    test(
        delegate void (Assembler a) { a.instr(CMOVG, ESI, EDI); }, 
        "0F4FF7"
    );
    test(
        delegate void (Assembler a) { a.instr(CMOVG, ESI, new X86Mem(32, EBP, 12)); }, 
        "0F4F750C", 
        "670F4F750C"
    );
    test(
        delegate void (Assembler a) { a.instr(CMOVL, EAX, ECX); }, 
        "0F4CC1"
    );
    test(
        delegate void (Assembler a) { a.instr(CMOVL, RBX, RBP); }, 
        "",
        "480F4CDD"
    );
    test(
        delegate void (Assembler a) { a.instr(CMOVLE, ESI, new X86Mem(32, ESP, 4)); }, 
        "0F4E742404", 
        "670F4E742404"
    );

    // cmp
    test(
        delegate void (Assembler a) { a.instr(CMP, CL, DL); },
        "38D1"
    );   
    test(
        delegate void (Assembler a) { a.instr(CMP, ECX, EDI); },
        "39F9"
    );   
    test(
        delegate void (Assembler a) { a.instr(CMP, RDX, new X86Mem(64, R12)); },
        "",
        "493B1424"
    );
    test(
        delegate void (Assembler a) { a.instr(CMP, RAX, 2); },
        "",
        "4883F802"
    );   

    // cqo
    test(
        delegate void (Assembler a) { a.instr(CQO); },
        "",
        "4899"
    );

    // cvtsd2si
    test(
        delegate void (Assembler a) { a.instr(CVTSD2SI, ECX, XMM6); }, 
        "F20F2DCE"
    );
    test(
        delegate void (Assembler a) { a.instr(CVTSD2SI, RDX, XMM4); },
        "",
        "F2480F2DD4"
    );

    // cvtsi2sd
    test(
        delegate void (Assembler a) { a.instr(CVTSI2SD, XMM7, EDI); }, 
        "F20F2AFF"
    );
    test(
        delegate void (Assembler a) { a.instr(CVTSI2SD, XMM7, new X86Mem(64, RCX)); },
        "",
        "F2480F2A39"
    );

    // dec
    test(
        delegate void (Assembler a) { a.instr(DEC, CX); }, 
        "6649",
        "66FFC9"
    );
    test(
        delegate void (Assembler a) { a.instr(DEC, EDX); }, 
        "4A",
        "FFCA"
    );

    // div
    test(
        delegate void (Assembler a) { a.instr(DIV, EDX); }, 
        "F7F2"
    );
    test(
        delegate void (Assembler a) { a.instr(DIV, new X86Mem(32, ESP, -12)); }, 
        "F77424F4",
        "67F77424F4"
    );

    // fst
    test(
        delegate void (Assembler a) { a.instr(FSTP, new X86Mem(64, RSP, -16)); },
        "",
        "DD5C24F0"
    );

    // imul
    test(
        delegate void (Assembler a) { a.instr(IMUL, EDX, ECX); },
        "0FAFD1"
    );
    test(
        delegate void (Assembler a) { a.instr(IMUL, RSI, RDI); },
        "",
        "480FAFF7"
    );
    test(
        delegate void (Assembler a) { a.instr(IMUL, R14, R9); }, 
        "", 
        "4D0FAFF1"
    );
    test(
        delegate void (Assembler a) { a.instr(IMUL, EAX, new X86Mem(32, ESP, 8)); },
        "0FAF442408",
        "670FAF442408"
    );

    // inc
    test(
        delegate void (Assembler a) { a.instr(INC, BL); },
        "FEC3", 
        "FEC3"
    );
    test(
        delegate void (Assembler a) { a.instr(INC, ESP); },
        "44",
        "FFC4"
    );
    test(
        delegate void (Assembler a) { a.instr(INC, new X86Mem(32, ESP, 0)); },
        "FF0424",
        "67FF0424"
    );
    test(
        delegate void (Assembler a) { a.instr(INC, new X86Mem(64, RSP, 4)); },
        "",
        "48FF442404"
    );

    // jcc
    test(
        delegate void (Assembler a) { auto l = a.label("foo"); a.instr(JGE, l); },
        "7DFE"
    );
    test(
        delegate void (Assembler a) { auto l = a.label("foo"); a.instr(JNO, l); },
        "71FE"
    );

    // lea
    test(
        delegate void (Assembler a) {a.instr(LEA, EBX, new X86Mem(32, ESP, 4)); },
        "8D5C2404",
        "678D5C2404"
    );

    // mov
    test(
        delegate void (Assembler a) { a.instr(MOV, EAX, 7); }, 
        "B807000000"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, EAX, -3); }, 
        "B8FDFFFFFF"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, EAX, EBX); }, 
        "89D8"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, EAX, ECX); }, 
        "89C8"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, ECX, new X86Mem(32, ESP, -4)); }, 
        "8B4C24FC",
        "678B4C24FC"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, EDX, new X86Mem(32, RBX, 128)); }, 
        "",
        "8B9380000000"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, CL, R9L); }, 
        "",
        "4488C9"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, RBX, RAX); }, 
        "",
        "4889C3"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, RDI, RBX); }, 
        "",
        "4889DF"
    );
    test(
        delegate void (Assembler a) { a.instr(MOV, SIL, 11); },
        "40B60B"
    );

    // movapd
    test(
        delegate void (Assembler a) { a.instr(MOVAPD, XMM5, new X86Mem(128, ESP)); },
        "660F282C24",
        "67660F282C24"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVAPD, new X86Mem(128, ESP, -8), XMM6); },
        "660F297424F8",
        "67660F297424F8"
    );

    // movsd
    test(
        delegate void (Assembler a) { a.instr(MOVSD, XMM3, XMM5); },
        "F20F10DD"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVSD, XMM3, new X86Mem(64, ESP)); },
        "F20F101C24",
        "67F20F101C24"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVSD, new X86Mem(64, RSP), XMM14); },
        "",
        "F2440F113424"
    );

    // movsx
    test(
        delegate void (Assembler a) { a.instr(MOVSX, AX, AL); },
        "660FBEC0"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVSX, EDX, AL); },
        "0FBED0"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVSX, RAX, BL); },
        "",
        "480FBEC3"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVSX, ECX, AX); },
        "0FBFC8"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVSX, R11, CL); },
        "",
        "4C0FBED9"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVSXD, R10, new X86Mem(32, ESP, 12)); },
        "",
        "674C6354240C"
    );

    // movupd
    test(
        delegate void (Assembler a) { a.instr(MOVUPD, XMM7, new X86Mem(128, RSP)); },
        "",
        "660F103C24"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVUPD, new X86Mem(128, RCX, -8), XMM9); },
        "",
        "66440F1149F8"
    );

    // movzx
    test(
        delegate void (Assembler a) { a.instr(MOVZX, SI, BL); },
        "660FB6F3"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVZX, ECX, AL); },
        "0FB6C8"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVZX, EDI, AL); },
        "0FB6F8"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVZX, EBP, AL); },
        "0FB6E8"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVZX, RCX, BL); },
        "",
        "480FB6CB"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVZX, ECX, AX); },
        "0FB7C8"
    );
    test(
        delegate void (Assembler a) { a.instr(MOVZX, R11, CL); },
        "",
        "4C0FB6D9"
    );

    // mul
    test(
        delegate void (Assembler a) { a.instr(MUL, EDX); }, 
        "F7E2"
    );
    test(
        delegate void (Assembler a) { a.instr(MUL, R15); },
        "",
        "49F7E7"
    );
    test(
        delegate void (Assembler a) { a.instr(MUL, R10D); },
        "",
        "41F7E2"
    );

    // nop
    test(
        delegate void (Assembler a) { a.instr(NOP); }, 
        "90"
    );

    // not
    test(
        delegate void (Assembler a) { a.instr(NOT, AX); }, 
        "66F7D0"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, EAX); }, 
        "F7D0"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, RAX); }, 
        "", 
        "48F7D0"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, R11); }, 
        "", 
        "49F7D3"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EAX)); }, 
        "F710", 
        "67F710"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, ESI)); },
        "F716", 
        "67F716"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EDI)); }, 
        "F717", 
        "67F717"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EDX, 55)); },
        "F75237", 
        "67F75237"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EDX, 1337)); },
        "F79239050000", 
        "67F79239050000"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EDX, -55)); },
        "F752C9", 
        "67F752C9"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EDX, -555)); },
        "F792D5FDFFFF", 
        "67F792D5FDFFFF"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EAX, 0, EBX)); }, 
        "F71418", 
        "67F71418"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RAX, 0, RBX)); }, 
        "", 
        "F71418"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RAX, 0, R12)); }, 
        "", 
        "42F71420"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, R15, 0, R12)); }, 
        "", 
        "43F71427"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, R15, 5, R12)); }, 
        "", 
        "43F7542705"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, R15, 5, R12, 8)); }, 
        "", 
        "43F754E705"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, R15, 5, R13, 8)); }, 
        "", 
        "43F754EF05"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(64, R12)); }, 
        "",
        "49F71424"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, R12, 5, R9, 4)); }, 
        "", 
        "43F7548C05"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, R12, 301, R9, 4)); }, 
        "", 
        "43F7948C2D010000"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EAX, 5, EDX, 4)); }, 
        "F7549005",
        "67F7549005"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(64, EAX, 0, EDX, 2)); },
        "",
        "6748F71450"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, ESP)); },
        "F71424",
        "67F71424"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, ESP, 301)); }, 
        "F794242D010000",
        "67F794242D010000"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RSP)); },
        "",
        "F71424"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RSP, 0, RBX)); },
        "",
        "F7141C"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RSP, 3, RBX)); },
        "",
        "F7541C03"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RSP, 3)); },
        "",
        "F7542403"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EBP)); },
        "F75500",
        "67F75500"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EBP, 13)); },
        "F7550D",
        "67F7550D"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, EBP, 13, EDX)); },
        "F754150D",
        "67F754150D"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RIP)); },
        "",
        "F79500000000"
    );
    test(
        delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, RIP, 13)); },
        "",
        "F7950D000000"
    );
    test(delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, null, 0, R8, 8)); }, 
        "", 
        "42F714C500000000"
    );
    test(delegate void (Assembler a) { a.instr(NOT, new X86Mem(32, null, 5)); }, 
        "F71505000000", 
        "F7142505000000"
    );

    // or
    test(
        delegate void (Assembler a) { a.instr(OR, EDX, ESI); },
        "09F2"
    );

    // pop
    test(
        delegate void (Assembler a) { a.instr(POP, RAX); }, 
        "",
        "58"
    );
    test(
        delegate void (Assembler a) { a.instr(POP, RBX); },
        "",
        "5B"
    );
    test(
        delegate void (Assembler a) { a.instr(POP, RSP); },
        "",
        "5C"
    );
    test(
        delegate void (Assembler a) { a.instr(POP, RBP); },
        "",
        "5D"
    );

    // push
    test(
        delegate void (Assembler a) { a.instr(PUSH, RAX); },
        "",
        "50"
    );
    test(
        delegate void (Assembler a) { a.instr(PUSH, BX); }, 
        "6653"
    );
    test(
        delegate void (Assembler a) { a.instr(PUSH, RBX); },
        "",
        "53"
    );
    test(
        delegate void (Assembler a) { a.instr(PUSH, 1); },
        "6A01"
    );

    // ret
    test(
        delegate void (Assembler a) { a.instr(RET); },
        "C3"
    );
    test(
        delegate void (Assembler a) { a.instr(RET, 5); },
        "C20500"
    );

    // roundsd
    test(
        delegate void (Assembler a) { a.instr(ROUNDSD, XMM2, XMM5, 0); },
        "660F3A0BD500"
    );

    // sal
    test(
        delegate void (Assembler a) { a.instr(SAL, CX, 1); },
        "66D1E1"
    );
    test(
        delegate void (Assembler a) { a.instr(SAL, ECX, 1); },
        "D1E1"
    );
    test(
        delegate void (Assembler a) { a.instr(SAL, AL, CL); },
        "D2E0"
    );
    test(
        delegate void (Assembler a) { a.instr(SAL, EBP, 5); },
        "C1E505"
    );
    test(
        delegate void (Assembler a) { a.instr(SAL, new X86Mem(32, ESP, 68), 1); },
        "D1642444",
        "67D1642444"  
    );

    // sar
    test(
        delegate void (Assembler a) { a.instr(SAR, EDX, 1); },
        "D1FA"
    );

    // shr
    test(
        delegate void (Assembler a) { a.instr(SHR, R14, 7); },
        "",
        "49C1EE07"
    );

    // sqrtsd
    test(
        delegate void (Assembler a) { a.instr(SQRTSD, XMM2, XMM6); },
        "F20F51D6"
    );

    // sub
    test(
        delegate void (Assembler a) { a.instr(SUB, EAX, 1); },
        "83E801",
        "83E801"
    );
    test(
        delegate void (Assembler a) { a.instr(SUB, RAX, 2); },
        "",
        "4883E802"
    );

    // test
    test(
        delegate void (Assembler a) { a.instr(TEST, AL, 4); },
        "A804"
    );
    test(
        delegate void (Assembler a) { a.instr(TEST, CL, 255); },
        "F6C1FF"
    );
    test(
        delegate void (Assembler a) { a.instr(TEST, DL, 7); },
        "F6C207"
    );
    test(
        delegate void (Assembler a) { a.instr(TEST, DIL, 9); },
        "",
        "40F6C709"
    );

    // ucomisd
    test(
        delegate void (Assembler a) { a.instr(UCOMISD, XMM3, XMM5); },
        "660F2EDD"
    );
    test(
        delegate void (Assembler a) { a.instr(UCOMISD, XMM11, XMM13); },
        "",
        "66450F2EDD"
    );

    // xchg
    test(
        delegate void (Assembler a) { a.instr(XCHG, AX, DX); }, 
        "6692"
    );
    test(
        delegate void (Assembler a) { a.instr(XCHG, EAX, EDX); }, 
        "92"
    );
    test(
        delegate void (Assembler a) { a.instr(XCHG, RAX, R15); },
        "",
        "4997"
    );
    test(
        delegate void (Assembler a) { a.instr(XCHG, R14, R15); }, 
        "", 
        "4D87FE"
    );

    // xor
    test(
        delegate void (Assembler a) { a.instr(XOR, EAX, EAX); },
        "", 
        "31C0"
    );

    // Simple loop from 0 to 10
    test(
        delegate void (Assembler a) 
        {
            a.instr(MOV, EAX, 0);
            auto LOOP = a.label("LOOP");
            a.instr(ADD, EAX, 1);
            a.instr(CMP, EAX, 10);
            a.instr(JB, LOOP);
            a.instr(RET);
        },
        "B80000000083C00183F80A72F8C3"
    );

    // Simple loop from 0 to 10 (64-bit)
    test(
        delegate void (Assembler a) 
        {
            a.instr(MOV, RAX, 0);
            auto LOOP = a.label("LOOP");
            a.instr(ADD, RAX, 1);
            a.instr(CMP, RAX, 10);
            a.instr(JB, LOOP);
            a.instr(RET);
        },
        "48C7C0000000004883C0014883F80A72F6C3"
    );
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
        // Create an assembler to generate code into
        auto assembler = new Assembler();

        // Generate the code
        genFunc(assembler);

        // Assemble to a code block (code only, no header)
        auto codeBlock = assembler.assemble();

        auto testFun = cast(TestFn)codeBlock.getAddress();

        //writefln("calling %s", testFun);

        auto ret = testFun();
        
        //writefln("ret: %s", ret);

        if (ret != retVal)
        {
            throw new Error(
                xformat(
                    "invalid return value for:\n" ~
                    "\n" ~
                    "%s\n" ~
                    "\n" ~
                    "got:\n" ~
                    "%s\n" ~
                    "expected:\n" ~
                    "%s",
                    assembler.toString(true),
                    ret,
                    retVal
                )
            );
        }
    }

    // Trivial return 3
    test(
        delegate void (Assembler a) 
        {
            a.instr(MOV, RAX, 3);
            a.instr(RET);
        },
        3
    );

    // Loop until 10
    test(
        delegate void (Assembler a) 
        {
            a.instr(MOV, RAX, 0);
            auto LOOP = a.label("LOOP");
            a.instr(ADD, RAX, 1);
            a.instr(CMP, RAX, 10);
            a.instr(JB, LOOP);
            a.instr(RET);
        },
        10
    );

    // Jump with a large offset (> 8 bits)
    test(
        delegate void (Assembler a)
        {
            a.instr(MOV, RAX, 0);
            auto LOOP = a.label("LOOP");
            a.instr(ADD, RAX, 1);
            a.instr(CMP, RAX, 15);
            for (auto i = 0; i < 400; ++i)
                a.instr(NOP);
            a.instr(JB, LOOP);
            a.instr(RET);
        },
        15
    );

    // Arithmetic
    test(
        delegate void (Assembler a)
        {
            a.instr(PUSH, RBX);
            a.instr(PUSH, RCX);
            a.instr(PUSH, RDX);

            a.instr(MOV, RAX, 4);       // a = 4
            a.instr(MOV, RBX, 5);       // b = 5
            a.instr(MOV, RCX, 3);       // c = 3
            a.instr(ADD, RAX, RBX);     // a = 9
            a.instr(SUB, RBX, RCX);     // b = 2
            a.instr(MUL, RBX);          // a = 18, d = 0
            a.instr(MOV, RDX, -2);      // d = -2
            a.instr(IMUL, RDX, RAX);    // d = -36
            a.instr(MOV, RAX, RDX);     // a = -36

            a.instr(POP, RDX);
            a.instr(POP, RCX);
            a.instr(POP, RBX);

            a.instr(RET);
        },
        -36
    );

    // Stack manipulation, sign extension
    test(
        delegate void (Assembler a)
        {
            a.instr(SUB, RSP, 1);
            auto sloc = new X86Mem(8, RSP, 0);
            a.instr(MOV, sloc, -3);
            a.instr(MOVSX, RAX, sloc);
            a.instr(ADD, RSP, 1);
            a.instr(RET);
        },
        -3
    );
    
    // fib(20), function calls
    test(
        delegate void (Assembler a)
        {
            auto COMP = new Label("COMP");
            auto FIB  = new Label("FIB");

            a.instr(PUSH, RBX);
            a.instr(MOV, RAX, 20);
            a.instr(CALL, FIB);
            a.instr(POP, RBX);
            a.instr(RET);

            // FIB
            a.addInstr(FIB);
            a.instr(CMP, RAX, 2);
            a.instr(JGE, COMP);
            a.instr(RET);

            // COMP
            a.addInstr(COMP);
            a.instr(PUSH, RAX);     // store n
            a.instr(SUB, RAX, 1);   // RAX = n-1
            a.instr(CALL, FIB);     // fib(n-1)
            a.instr(MOV, RBX, RAX); // RAX = fib(n-1)
            a.instr(POP, RAX);      // RAX = n
            a.instr(PUSH, RBX);     // store fib(n-1)
            a.instr(SUB, RAX, 2);   // RAX = n-2
            a.instr(CALL, FIB);     // fib(n-2)
            a.instr(POP, RBX);      // RBX = fib(n-1)
            a.instr(ADD, RAX, RBX); // RAX = fib(n-2) + fib(n-1)
            a.instr(RET);
        },
        6765
    );

    // SSE2 floating-point computation
    test(
        delegate void (Assembler a)
        {
            a.instr(MOV, RAX, 2);
            a.instr(CVTSI2SD, XMM0, RAX);
            a.instr(MOV, RAX, 7);
            a.instr(CVTSI2SD, XMM1, RAX);
            a.instr(ADDSD, XMM0, XMM1);
            a.instr(CVTSD2SI, RAX, XMM0);
            a.instr(RET);
        },
        9
    );

    // Floating-point comparison
    test(
        delegate void (Assembler a) 
        {
            a.instr(MOV, RAX, 10);
            a.instr(CVTSI2SD, XMM2, RAX);   // XMM2 = 10
            a.instr(MOV, RAX, 1);
            a.instr(CVTSI2SD, XMM1, RAX);   // XMM1 = 1
            a.instr(MOV, RAX, 0);
            a.instr(CVTSI2SD, XMM0, RAX);   // XMM0 = 0
            auto LOOP = a.label("LOOP");
            a.instr(ADDSD, XMM0, XMM1);
            a.instr(UCOMISD, XMM0, XMM2);
            a.instr(JBE, LOOP);
            a.instr(CVTSD2SI, RAX, XMM0);
            a.instr(RET);
        },
        11
    );
}

