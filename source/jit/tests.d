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
import jit.x86;
import jit.assembler;
import jit.codeblock;
import jit.encodings;

/// Code generation function for testing
alias void delegate(Assembler) CodeGenFun;

/**
Test x86 instruction encodings
*/
unittest
{
    // Test encodings for 32-bit and 64-bit
    void test(CodeGenFun codeFunc, string enc32, string enc64 = "")
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
                    assembler.toString(),
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

        writeln(enc64);
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
        delegate void (Assembler a) { a.instr(ADD, RDX, R14); },
        "",
        "4C01F2"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, EDX, X86Opnd(32, EAX)); },
        "0310",
        "670310"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, X86Opnd(32, EAX), EDX); },
        "0110",
        "670110"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, X86Opnd(64, RAX), RDX); },
        "", 
        "480110"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, X86Opnd(32, RAX), EDX); },
        "", 
        "0110"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, EAX, X86Opnd(32, ESP, 8)); }, 
        "03442408",
        "6703442408"
    );
    test(
        delegate void (Assembler a) { a.instr(ADD, X86Opnd(32, ESP, 8), 7); },
        "8344240807",
        "678344240807"
    );

    /*
    // addsd
    test(
        delegate void (Assembler a) { a.addsd(a.xmm3, a.xmm5); },
        "F20F58DD"
    );
    test(
        delegate void (Assembler a) { a.addsd(a.xmm15, a.mem(64, a.r13, 5)); },
        "",
        "F2450F587D05"
    );
    test(
        delegate void (Assembler a) { a.addsd(a.xmm15, a.mem(64, a.r11)); },
        "",
        "F2450F583B"
    );

    // and
    test(
        delegate void (Assembler a) { a.and(a.ebp, a.r12d); }, 
        "", 
        "4421E5"
    );

    // cmovcc
    test(
        delegate void (Assembler a) { a.cmovg(a.esi, a.edi); }, 
        "0F4FF7"
    );
    test(
        delegate void (Assembler a) { a.cmovg(a.esi, a.mem(32, a.ebp, 12)); }, 
        "0F4F750C", 
        "670F4F750C"
    );
    test(
        delegate void (Assembler a) { a.cmovl(a.eax, a.ecx); }, 
        "0F4CC1"
    );
    test(
        delegate void (Assembler a) { a.cmovl(a.rbx, a.rbp); }, 
        "",
        "480F4CDD"
    );
    test(
        delegate void (Assembler a) { a.cmovle(a.esi, a.mem(32, a.esp, 4)); }, 
        "0F4E742404", 
        "670F4E742404"
    );

    // cmp
    test(
        delegate void (Assembler a) { a.cmp(a.ecx, a.edi); },
        "39F9"
    );   
    test(
        delegate void (Assembler a) { a.cmp(a.rdx, a.mem(64, a.r12)); },
        "",
        "493B1424"
    );   

    // cpuid
    test(
        delegate void (Assembler a) { a.cpuid(); }, 
        "0FA2"
    );

    // cqo
    test(
        delegate void (Assembler a) { a.cqo(); },
        "",
        "4899"
    );

    // cvtsd2si
    test(
        delegate void (Assembler a) { a.cvtsd2si(a.ecx, a.xmm6); }, 
        "F20F2DCE"
    );
    test(
        delegate void (Assembler a) { a.cvtsd2si(a.rdx, a.xmm4); },
        "",
        "F2480F2DD4"
    );

    // cvtsi2sd
    test(
        delegate void (Assembler a) { a.cvtsi2sd(a.xmm7, a.edi); }, 
        "F20F2AFF"
    );
    test(
        delegate void (Assembler a) { a.cvtsi2sd(a.xmm7, a.mem(64, a.rcx)); },
        "",
        "F2480F2A39"
    );

    // dec
    test(
        delegate void (Assembler a) { a.dec(a.cx); }, 
        "6649",
        "66FFC9"
    );
    test(
        delegate void (Assembler a) { a.dec(a.edx); }, 
        "4A",
        "FFCA"
    );

    // div
    test(
        delegate void (Assembler a) { a.div(a.edx); }, 
        "F7F2"
    );
    test(
        delegate void (Assembler a) { a.div(a.mem(32, a.esp, -12)); }, 
        "F77424F4",
        "67F77424F4"
    );

    // fst
    test(
        delegate void (Assembler a) { a.fst(a.mem(64, a.esp, -8)); },
        "DD5424F8",
        "67DD5424F8"
    );
    test(
        delegate void (Assembler a) { a.fstp(a.mem(64, a.rsp, -16)); },
        "",
        "DD5C24F0"
    );

    // imul
    test(
        delegate void (Assembler a) { a.imul(a.edx, a.ecx); },
        "0FAFD1"
    );
    test(
        delegate void (Assembler a) { a.imul(a.rsi, a.rdi); },
        "",
        "480FAFF7"
    );
    test(
        delegate void (Assembler a) { a.imul(a.r14, a.r9); }, 
        "", 
        "4D0FAFF1"
    );
    test(
        delegate void (Assembler a) { a.imul(a.eax, a.mem(32, a.esp, 8)); },
        "0FAF442408",
        "670FAF442408"
    );

    // inc
    test(
        delegate void (Assembler a) { a.inc(a.bl); },
        "FEC3", 
        "FEC3"
    );
    test(
        delegate void (Assembler a) { a.inc(a.esp); },
        "44",
        "FFC4"
    );
    test(
        delegate void (Assembler a) { a.inc(a.mem(32, a.esp, 0)); },
        "FF0424",
        "67FF0424"
    );
    test(
        delegate void (Assembler a) { a.inc(a.mem(64, a.rsp, 4)); },
        "",
        "48FF442404"
    );

    // jcc
    test(
        delegate void (Assembler a) { var l = a.label("foo"); a.jge(l); },
        "7DFE"
    );
    test(
        delegate void (Assembler a) { var l = a.label("foo"); a.jno(l); },
        "71FE"
    );

    // lea
    test(
        delegate void (Assembler a) {a.lea(a.ebx, a.mem(32, a.esp, 4)); },
        "8D5C2404",
        "678D5C2404"
    );

    // mov
    test(
        delegate void (Assembler a) { a.mov(a.eax, 7); }, 
        "B807000000"
    );
    test(
        delegate void (Assembler a) { a.mov(a.eax, -3); }, 
        "B8FDFFFFFF"
    );
    test(
        delegate void (Assembler a) { a.mov(a.eax, a.ebx); }, 
        "89D8"
    );
    test(
        delegate void (Assembler a) { a.mov(a.eax, a.ecx); }, 
        "89C8"
    );
    test(
        delegate void (Assembler a) { a.mov(a.ecx, a.mem(32, a.esp, -4)); }, 
        "8B4C24FC",
        "678B4C24FC"
    );
    test(
        delegate void (Assembler a) { a.mov(a.cl, a.r9l); }, 
        "",
        "4488C9"
    );

    // movapd
    test(
        delegate void (Assembler a) { a.movapd(a.xmm5, a.mem(128, a.esp)); },
        "660F282C24",
        "67660F282C24"
    );
    test(
        delegate void (Assembler a) { a.movapd(a.mem(128, a.esp, -8), a.xmm6); },
        "660F297424F8",
        "67660F297424F8"
    );

    // movsd
    test(
        delegate void (Assembler a) { a.movsd(a.xmm3, a.xmm5); },
        "F20F10DD"
    );
    test(
        delegate void (Assembler a) { a.movsd(a.xmm3, a.mem(64, a.esp)); },
        "F20F101C24",
        "67F20F101C24"
    );
    test(
        delegate void (Assembler a) { a.movsd(a.mem(64, a.rsp), a.xmm14); },
        "",
        "F2440F113424"
    );

    // movsx
    test(
        delegate void (Assembler a) { a.movsx(a.ax, a.al); },
        "660FBEC0"
    );
    test(
        delegate void (Assembler a) { a.movsx(a.edx, a.al); },
        "0FBED0"
    );
    test(
        delegate void (Assembler a) { a.movsx(a.rax, a.bl); },
        "",
        "480FBEC3"
    );
    test(
        delegate void (Assembler a) { a.movsx(a.ecx, a.ax); },
        "0FBFC8"
    );
    test(
        delegate void (Assembler a) { a.movsx(a.r11, a.cl); },
        "",
        "4C0FBED9"
    );
    test(
        delegate void (Assembler a) { a.movsxd(a.r10, a.mem(32, a.esp, 12)); },
        "",
        "674C6354240C"
    );

    // movupd
    test(
        delegate void (Assembler a) { a.movupd(a.xmm7, a.mem(128, a.rsp)); },
        "",
        "660F103C24"
    );
    test(
        delegate void (Assembler a) { a.movupd(a.mem(128, a.rcx, -8), a.xmm9); },
        "",
        "66440F1149F8"
    );

    // movzx
    test(
        delegate void (Assembler a) { a.movzx(a.si, a.bl); },
        "660FB6F3"
    );
    test(
        delegate void (Assembler a) { a.movzx(a.ecx, a.al); },
        "0FB6C8"
    );
    test(
        delegate void (Assembler a) { a.movzx(a.edi, a.al); },
        "0FB6F8"
    );
    test(
        delegate void (Assembler a) { a.movzx(a.ebp, a.al); },
        "0FB6E8"
    );
    test(
        delegate void (Assembler a) { a.movzx(a.rcx, a.bl); },
        "",
        "480FB6CB"
    );
    test(
        delegate void (Assembler a) { a.movzx(a.ecx, a.ax); },
        "0FB7C8"
    );
    test(
        delegate void (Assembler a) { a.movzx(a.r11, a.cl); },
        "",
        "4C0FB6D9"
    );

    // mul
    test(
        delegate void (Assembler a) { a.mul(a.edx); }, 
        "F7E2"
    );
    test(
        delegate void (Assembler a) { a.mul(a.r15); },
        "",
        "49F7E7"
    );
    test(
        delegate void (Assembler a) { a.mul(a.r10d); },
        "",
        "41F7E2"
    );
    */

    // nop
    test(
        delegate void (Assembler a) { a.instr(NOP); }, 
        "90"
    );

    /*
    // not
    test(
        delegate void (Assembler a) { a.not(a.ax); }, 
        "66F7D0"
    );
    test(
        delegate void (Assembler a) { a.not(a.eax); }, 
        "F7D0"
    );
    test(
        delegate void (Assembler a) { a.not(a.rax); }, 
        "", 
        "48F7D0"
    );
    test(
        delegate void (Assembler a) { a.not(a.r11); }, 
        "", 
        "49F7D3"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.eax)); }, 
        "F710", 
        "67F710"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.esi)); },
        "F716", 
        "67F716"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.edi)); }, 
        "F717", 
        "67F717"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.edx, 55)); },
        "F75237", 
        "67F75237"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.edx, 1337)); },
        "F79239050000", 
        "67F79239050000"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.edx, -55)); },
        "F752C9", 
        "67F752C9"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.edx, -555)); },
        "F792D5FDFFFF", 
        "67F792D5FDFFFF"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.eax, 0, a.ebx)); }, 
        "F71418", 
        "67F71418"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rax, 0, a.rbx)); }, 
        "", 
        "F71418"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rax, 0, a.r12)); }, 
        "", 
        "42F71420"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.r15, 0, a.r12)); }, 
        "", 
        "43F71427"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.r15, 5, a.r12)); }, 
        "", 
        "43F7542705"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.r15, 5, a.r12, 8)); }, 
        "", 
        "43F754E705"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.r15, 5, a.r13, 8)); }, 
        "", 
        "43F754EF05"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(64, a.r12)); }, 
        "",
        "49F71424"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.r12, 5, a.r9, 4)); }, 
        "", 
        "43F7548C05"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.r12, 301, a.r9, 4)); }, 
        "", 
        "43F7948C2D010000"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.eax, 5, a.edx, 4)); }, 
        "F7549005",
        "67F7549005"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(64, a.eax, 0, a.edx, 2)); },
        "",
        "6748F71450"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.esp)); },
        "F71424",
        "67F71424"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.esp, 301)); }, 
        "F794242D010000",
        "67F794242D010000"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rsp)); },
        "",
        "F71424"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rsp, 0, a.rbx)); },
        "",
        "F7141C"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rsp, 3, a.rbx)); },
        "",
        "F7541C03"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rsp, 3)); },
        "",
        "F7542403"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.ebp)); },
        "F75500",
        "67F75500"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.ebp, 13)); },
        "F7550D",
        "67F7550D"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.ebp, 13, a.edx)); },
        "F754150D",
        "67F754150D"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rip)); },
        "",
        "F79500000000"
    );
    test(
        delegate void (Assembler a) { a.not(a.mem(32, a.rip, 13)); },
        "",
        "F7950D000000"
    );
    test(delegate void (Assembler a) { a.not(a.mem(32, undefined, 0, a.r8, 8)); }, 
        "", 
        "42F714C500000000"
    );
    test(delegate void (Assembler a) { a.not(a.mem(32, undefined, 5)); }, 
        "F71505000000", 
        "F7142505000000"
    );

    // or
    test(
        delegate void (Assembler a) { a.or(a.edx, a.esi); },
        "09F2"
    );

    // pop
    test(
        delegate void (Assembler a) { a.pop(a.eax); }, 
        "58",
        false
    );
    test(
        delegate void (Assembler a) { a.pop(a.ebx); },
        "5B",
        false
    );

    // push
    test(
        delegate void (Assembler a) { a.push(a.eax); },
        "50",
        false
    );
    test(
        delegate void (Assembler a) { a.push(a.bx); }, 
        "6653", 
        false
    );
    test(
        delegate void (Assembler a) { a.push(a.ebx); },
        "53",
        false
    );
    test(
        delegate void (Assembler a) { a.push(1); },
        "6A01",
        false
    );

    // ret
    test(
        delegate void (Assembler a) { a.ret(); },
        "C3"
    );
    test(
        delegate void (Assembler a) { a.ret(5); },
        "C20500"
    );

    // roundsd
    test(
        delegate void (Assembler a) { a.roundsd(a.xmm2, a.xmm5, 0); },
        "660F3A0BD500"
    );

    // sal
    test(
        delegate void (Assembler a) { a.sal(a.cx, 1); },
        "66D1E1"
    );
    test(
        delegate void (Assembler a) { a.sal(a.ecx, 1); },
        "D1E1"
    );
    test(
        delegate void (Assembler a) { a.sal(a.al, a.cl); },
        "D2E0"
    );
    test(
        delegate void (Assembler a) { a.sal(a.ebp, 5); },
        "C1E505"
    );
    test(
        delegate void (Assembler a) { a.sal(a.mem(32, a.esp, 68), 1); },
        "D1642444",
        "67D1642444"  
    );

    // sar
    test(
        delegate void (Assembler a) { a.sar(a.edx, 1); },
        "D1FA"
    );

    // shr
    test(
        delegate void (Assembler a) { a.shr(a.r14, 7); },
        "",
        "49C1EE07"
    );

    // sqrtsd
    test(
        delegate void (Assembler a) { a.sqrtsd(a.xmm2, a.xmm6); },
        "F20F51D6"
    );

    // sub
    test(
        delegate void (Assembler a) { a.sub(a.eax, 1); },
        "83E801",
        "83E801"
    );

    // test
    test(
        delegate void (Assembler a) { a.test(a.al, 4); },
        "A804"
    );
    test(
        delegate void (Assembler a) { a.test(a.cl, 255); },
        "F6C1FF"
    );
    test(
        delegate void (Assembler a) { a.test(a.dl, 7); },
        "F6C207"
    );
    test(
        delegate void (Assembler a) { a.test(a.ah, 12); },
        "F6C40C"
    );
    test(
        delegate void (Assembler a) { a.test(a.dil, 9); },
        "",
        "40F6C709"
    );

    // ucomisd
    test(
        delegate void (Assembler a) { a.ucomisd(a.xmm3, a.xmm5); },
        "660F2EDD"
    );
    test(
        delegate void (Assembler a) { a.ucomisd(a.xmm11, a.xmm13); },
        "",
        "66450F2EDD"
    );

    // xchg
    test(
        delegate void (Assembler a) { a.xchg(a.ax, a.dx); }, 
        "6692"
    );
    test(
        delegate void (Assembler a) { a.xchg(a.eax, a.edx); }, 
        "92"
    );
    test(
        delegate void (Assembler a) { a.xchg(a.rax, a.r15); },
        "",
        "4997"
    );
    test(
        delegate void (Assembler a) { a.xchg(a.r14, a.r15); }, 
        "", 
        "4D87FE"
    );

    // xor
    test(
        delegate void (Assembler a) { a.xor(a.eax, a.eax); },
        "", 
        "31C0"
    );

    // Simple loop from 0 to 10
    test(
        delegate void (Assembler a) { with (a) {
            mov(eax, 0);
            var LOOP = label("LOOP");
            add(eax, 1);
            cmp(eax, 10);
            jb(LOOP);
            ret();
        }},
        "B80000000083C00183F80A72F8C3"
    );
    */
}

/**
Test the execution of x86 code snippets
*/
unittest
{
    /*
    // Check if we are running in 32-bit or 64-bit
    const x86_64 = PLATFORM_64BIT;

    // Test the execution of a piece of code
    function test(genFunc, retVal, argVals)
    {
        if (argVals === undefined)
            argVals = [];

        // Create an assembler to generate code into
        var assembler = new x86.Assembler(x86_64);

        // Generate the code
        genFunc(assembler);

        // Assemble to a code block (code only, no header)
        var codeBlock = assembler.assemble(true);

        var blockAddr = codeBlock.getAddress();

        var argTypes = [];
        for (var i = 0; i < argVals.length; ++i)
            argTypes.push('int');

        var ctxPtr = x86_64? [0,0,0,0,0,0,0,0]:[0,0,0,0];

        var ret = callTachyonFFI(
            argTypes,
            'int',
            blockAddr,
            ctxPtr,
            argVals
        );

        if (ret !== retVal)
        {
            error(
                'invalid return value for:\n'+
                '\n' +
                assembler.toString(true) + '\n' +
                '\n' +
                'got:\n' +
                ret + '\n' +
                'expected:\n' +
                retVal
            );
        }
    }

    // GP register aliases for 32-bit and 64-bit
    var rega = x86_64? x86.regs.rax:x86.regs.eax;
    var regb = x86_64? x86.regs.rbx:x86.regs.ebx;
    var regc = x86_64? x86.regs.rcx:x86.regs.ecx;
    var regd = x86_64? x86.regs.rdx:x86.regs.edx;
    var regsp = x86_64? x86.regs.rsp:x86.regs.esp;

    // Loop until 10
    test(
        delegate void (Assembler a) { with (a) {
            mov(eax, 0);
            var LOOP = label('LOOP');
            add(eax, 1);
            cmp(eax, 10);
            jb(LOOP);
            ret();
        }},
        10
    );

    // Jump with a large offset (> 8 bits)
    test(
        delegate void (Assembler a) { with (a) {
            mov(eax, 0);
            var LOOP = label('LOOP');
            add(eax, 1);
            cmp(eax, 15);
            for (var i = 0; i < 400; ++i)
                nop();
            jb(LOOP);
            ret();
        }},
        15
    );

    // Arithmetic
    test(
        delegate void (Assembler a) { with (a) {
            push(regb);
            push(regc);
            push(regd);

            mov(rega, 4);       // a = 4
            mov(regb, 5);       // b = 5
            mov(regc, 3);       // c = 3
            add(rega, regb);    // a = 9
            sub(regb, regc);    // b = 2
            mul(regb);          // a = 18, d = 0
            mov(regd, -2);      // d = -2
            imul(regd, rega);   // d = -36
            mov(rega, regd);    // a = -36

            pop(regd);
            pop(regc);
            pop(regb);

            ret();
        }},
        -36
    );

    // Stack manipulation, sign extension
    test(
        delegate void (Assembler a) { with (a) {
            sub(regsp, 1);
            var sloc = mem(8, regsp, 0);
            mov(sloc, -3);
            movsx(rega, sloc);
            add(regsp, 1);
            ret();
        }},
        -3
    );
    
    // fib(20), function calls
    test(
        delegate void (Assembler a) { with (a) {
            var CALL = new x86.Label('CALL');
            var COMP = new x86.Label('COMP');
            var FIB = new x86.Label('FIB');

            push(regb);
            mov(rega, 20);
            call(FIB);
            pop(regb);
            ret();

            // FIB
            addInstr(FIB);
            cmp(rega, 2);
            jge(COMP);
            ret();

            // COMP
            addInstr(COMP);
            push(rega);         // store n
            sub(eax, 1);        // eax = n-1
            call(FIB);          // fib(n-1)
            mov(regb, rega);    // eax = fib(n-1)
            pop(rega);          // eax = n
            push(regb);         // store fib(n-1)
            sub(rega, 2);       // eax = n-2
            call(FIB);          // fib(n-2)
            pop(regb);          // ebx = fib(n-1)
            add(rega, regb);    // eax = fib(n-2) + fib(n-1)
            ret();
        }},
        6765
    );

    // SSE2 floating-point computation
    test(
        delegate void (Assembler a) { with (a) {
            mov(rega, 2);
            cvtsi2sd(xmm0, rega);
            mov(rega, 7);
            cvtsi2sd(xmm1, rega);
            addsd(xmm0, xmm1);
            cvtsd2si(rega, xmm0);
            ret();
        }},
        9
    );

    // Floating-point comparison
    test(
        delegate void (Assembler a) { with (a) {
            mov(rega, 10);
            cvtsi2sd(xmm2, rega);       // xmm2 = 10
            mov(rega, 1);
            cvtsi2sd(xmm1, rega);       // xmm1 = 1
            mov(rega, 0);
            cvtsi2sd(xmm0, rega);       // xmm0 = 0
            var LOOP = label('LOOP');
            addsd(xmm0, xmm1);
            ucomisd(xmm0, xmm2);
            jbe(LOOP);
            cvtsd2si(rega, xmm0);
            ret();
        }},
        11
    );
    */
}

