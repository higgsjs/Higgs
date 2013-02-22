import sys
import string
from copy import deepcopy

D_OUT_FILE = 'jit/encodings.d'

class Op:
    def __init__(self, mnem, *encs):
        if type(mnem) != str:
            raise Exception('missing mnemonic string')
        self.mnem = mnem
        self.encs = list(encs)

class Enc:
    def __init__(self, opnds, opCode, prefix=[], opExt=None, opndSize=None, rexW=None):
        self.opnds = opnds
        self.opCode = opCode
        self.prefix = prefix
        self.opExt = opExt
        self.opndSize = opndSize
        self.szPref = False
        self.rexW = rexW

# x86 instruction description table.
# This table can contain multiple entries per instruction.
#
# mnem    : mnemonic name
# opnds   : operands, dst first
# opCode  : opcode bytes
# opExt   : opcode extension byte
instrTable = [

    # Integer addition
    Op(
        'add',
        Enc(opnds=['al', 'imm8'], opCode=[0x04]),
        Enc(opnds=['ax', 'imm16'], opCode=[0x05]),
        Enc(opnds=['eax', 'imm32'], opCode=[0x05]),
        Enc(opnds=['rax', 'imm32'], opCode=[0x05]),
        Enc(opnds=['r/m8', 'imm8'], opCode=[0x80], opExt=0),
        Enc(opnds=['r/m16', 'imm16'], opCode=[0x81], opExt=0),
        Enc(opnds=['r/m32', 'imm32'], opCode=[0x81], opExt=0),
        Enc(opnds=['r/m64', 'imm32'], opCode=[0x81], opExt=0),
        Enc(opnds=['r/m16', 'imm8'], opCode=[0x83], opExt=0),
        Enc(opnds=['r/m32', 'imm8'], opCode=[0x83], opExt=0),
        Enc(opnds=['r/m64', 'imm8'], opCode=[0x83], opExt=0),
        Enc(opnds=['r/m8', 'r8'], opCode=[0x00]),
        Enc(opnds=['r/m16', 'r16'], opCode=[0x01]),
        Enc(opnds=['r/m32', 'r32'], opCode=[0x01]),
        Enc(opnds=['r/m64', 'r64'], opCode=[0x01]),
        Enc(opnds=['r8', 'r/m8'], opCode=[0x02]),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x03]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x03]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x03])
    ),

    # Add scalar double
    Op(
        'addsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opCode=[0x0F, 0x58]),
    ),

    # Bitwise AND
    Op(
        'and',
        Enc(opnds=['al', 'imm8'], opCode=[0x24]),
        Enc(opnds=['ax', 'imm16'], opCode=[0x25]),
        Enc(opnds=['eax', 'imm32'], opCode=[0x25]),
        Enc(opnds=['rax', 'imm32'], opCode=[0x25]),
        Enc(opnds=['r/m8', 'imm8'], opCode=[0x80], opExt=4),
        Enc(opnds=['r/m16', 'imm16'], opCode=[0x81], opExt=4),
        Enc(opnds=['r/m32', 'imm32'], opCode=[0x81], opExt=4),
        Enc(opnds=['r/m64', 'imm32'], opCode=[0x81], opExt=4),
        Enc(opnds=['r/m16', 'imm8'], opCode=[0x83], opExt=4),
        Enc(opnds=['r/m32', 'imm8'], opCode=[0x83], opExt=4),
        Enc(opnds=['r/m64', 'imm8'], opCode=[0x83], opExt=4),
        Enc(opnds=['r/m8', 'r8'], opCode=[0x20]),
        Enc(opnds=['r/m16', 'r16'], opCode=[0x21]),
        Enc(opnds=['r/m32', 'r32'], opCode=[0x21]),
        Enc(opnds=['r/m64', 'r64'], opCode=[0x21]),
        Enc(opnds=['r8', 'r/m8'], opCode=[0x22]),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x23]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x23]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x23]),
    ),

    # Call (relative and absolute)
    Op(
        'call',
        Enc(opnds=['rel32'], opCode=[0xE8]),
        Enc(opnds=['r/m64'], opCode=[0xFF], opExt=2, rexW=False)
    ),

    # Convert word to doubleword (sign extension)
    # Used before div and idiv
    Op(
        'cwd', 
        Enc(opnds=[], opCode=[0x99], opndSize=16),
    ),
    Op(
        'cwq', 
        Enc(opnds=[], opCode=[0x99], opndSize=32),
    ),
    Op(
        'cwo', 
        Enc(opnds=[], opCode=[0x99], opndSize=64),
    ),

    # Conditional move
    #{mnem: 'cmova', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x47], szPref: true},
    #{mnem: 'cmova', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x47]},
    #{mnem: 'cmova', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x47], REX_W: 1},
    #{mnem: 'cmovae', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x43], szPref: true},
    #{mnem: 'cmovae', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x43]},
    #{mnem: 'cmovae', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x43], REX_W: 1},
    #{mnem: 'cmovb', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x42], szPref: true},
    #{mnem: 'cmovb', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x42]},
    #{mnem: 'cmovb', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x42], REX_W: 1},
    #{mnem: 'cmovbe', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x46], szPref: true},
    #{mnem: 'cmovbe', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x46]},
    #{mnem: 'cmovbe', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x46], REX_W: 1},
    #{mnem: 'cmovc', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x42], szPref: true},
    #{mnem: 'cmovc', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x42]},
    #{mnem: 'cmovc', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x42], REX_W: 1},
    #{mnem: 'cmove', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x44], szPref: true},
    #{mnem: 'cmove', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x44]},
    #{mnem: 'cmove', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x44], REX_W: 1},
    #{mnem: 'cmovg', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4F], szPref: true},
    #{mnem: 'cmovg', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4F]},
    #{mnem: 'cmovg', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4F], REX_W: 1},
    #{mnem: 'cmovge', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4D], szPref: true},
    #{mnem: 'cmovge', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4D]},
    #{mnem: 'cmovge', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4D], REX_W: 1},
    #{mnem: 'cmovl', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4C], szPref: true},
    #{mnem: 'cmovl', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4C]},
    #{mnem: 'cmovl', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4C], REX_W: 1},
    #{mnem: 'cmovle', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4E], szPref: true},
    #{mnem: 'cmovle', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4E]},
    #{mnem: 'cmovle', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4E], REX_W: 1},
    #{mnem: 'cmovna', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x46], szPref: true},
    #{mnem: 'cmovna', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x46]},
    #{mnem: 'cmovna', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x46], REX_W: 1},
    #{mnem: 'cmovnae', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x42], szPref: true},
    #{mnem: 'cmovnae', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x42]},
    #{mnem: 'cmovnae', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x42], REX_W: 1},
    #{mnem: 'cmovnb', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x43], szPref: true},
    #{mnem: 'cmovnb', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x43]},
    #{mnem: 'cmovnb', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x43], REX_W: 1},
    #{mnem: 'cmovnbe', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x47], szPref: true},
    #{mnem: 'cmovnbe', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x47]},
    #{mnem: 'cmovnbe', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x47], REX_W: 1},
    #{mnem: 'cmovnc', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x43], szPref: true},
    #{mnem: 'cmovnc', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x43]},
    #{mnem: 'cmovnc', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x43], REX_W: 1},
    #{mnem: 'cmovne', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x45], szPref: true},
    #{mnem: 'cmovne', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x45]},
    #{mnem: 'cmovne', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x45], REX_W: 1},
    #{mnem: 'cmovng', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4E], szPref: true},
    #{mnem: 'cmovng', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4E]},
    #{mnem: 'cmovng', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4E], REX_W: 1},
    #{mnem: 'cmovnge', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4C], szPref: true},
    #{mnem: 'cmovnge', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4C]},
    #{mnem: 'cmovnge', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4C], REX_W: 1},
    #{mnem: 'cmovnl', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4D], szPref: true},
    #{mnem: 'cmovnl', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4D]},
    #{mnem: 'cmovnl', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4D], REX_W: 1},
    #{mnem: 'cmovnle', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4F], szPref: true},
    #{mnem: 'cmovnle', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4F]},
    #{mnem: 'cmovnle', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4F], REX_W: 1},
    #{mnem: 'cmovno', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x41], szPref: true},
    #{mnem: 'cmovno', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x41]},
    #{mnem: 'cmovno', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x41], REX_W: 1},
    #{mnem: 'cmovnp', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4B], szPref: true},
    #{mnem: 'cmovnp', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4B]},
    #{mnem: 'cmovnp', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4B], REX_W: 1},
    #{mnem: 'cmovns', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x49], szPref: true},
    #{mnem: 'cmovns', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x49]},
    #{mnem: 'cmovns', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x49], REX_W: 1},
    #{mnem: 'cmovnz', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x45], szPref: true},
    #{mnem: 'cmovnz', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x45]},
    #{mnem: 'cmovnz', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x45], REX_W: 1},
    #{mnem: 'cmovo', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x40], szPref: true},
    #{mnem: 'cmovo', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x40]},
    #{mnem: 'cmovo', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x40], REX_W: 1},
    #{mnem: 'cmovp', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4A], szPref: true},
    #{mnem: 'cmovp', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4A]},
    #{mnem: 'cmovp', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4A], REX_W: 1},
    #{mnem: 'cmovpe', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4A], szPref: true},
    #{mnem: 'cmovpe', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4A]},
    #{mnem: 'cmovpe', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4A], REX_W: 1},
    #{mnem: 'cmovpo', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x4B], szPref: true},
    #{mnem: 'cmovpo', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x4B]},
    #{mnem: 'cmovpo', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x4B], REX_W: 1},
    #{mnem: 'cmovs', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x48], szPref: true},
    #{mnem: 'cmovs', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x48]},
    #{mnem: 'cmovs', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x48], REX_W: 1},
    #{mnem: 'cmovz', opnds: ['r16', 'r/m16'], opCode: [0x0F, 0x44], szPref: true},
    #{mnem: 'cmovz', opnds: ['r32', 'r/m32'], opCode: [0x0F, 0x44]},
    #{mnem: 'cmovz', opnds: ['r64', 'r/m64'], opCode: [0x0F, 0x44], REX_W: 1},

    # Integer comparison
    Op(
        'cmp',
        Enc(opnds=['al', 'imm8'], opCode=[0x3C]),
        Enc(opnds=['ax', 'imm16'], opCode=[0x3D]),
        Enc(opnds=['eax', 'imm32'], opCode=[0x3D]),
        Enc(opnds=['rax', 'imm32'], opCode=[0x3D]),
        Enc(opnds=['r/m8', 'imm8'], opCode=[0x80], opExt=7),
        Enc(opnds=['r/m16', 'imm16'], opCode=[0x81], opExt=7),
        Enc(opnds=['r/m32', 'imm32'], opCode=[0x81], opExt=7),
        Enc(opnds=['r/m64', 'imm32'], opCode=[0x81], opExt=7),
        Enc(opnds=['r/m16', 'imm8'], opCode=[0x83], opExt=7),
        Enc(opnds=['r/m32', 'imm8'], opCode=[0x83], opExt=7),
        Enc(opnds=['r/m64', 'imm8'], opCode=[0x83], opExt=7),
        Enc(opnds=['r/m8', 'r8'], opCode=[0x38]),
        Enc(opnds=['r/m16', 'r16'], opCode=[0x39]),
        Enc(opnds=['r/m32', 'r32'], opCode=[0x39]),
        Enc(opnds=['r/m64', 'r64'], opCode=[0x39]),
        Enc(opnds=['r8', 'r/m8'], opCode=[0x3A]),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x3B]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x3B]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x3B]),
    ),

    # Convert integer to scalar double
    #{mnem: 'cvtsi2sd', opnds: ['xmm', 'r/m32'], prefix: [0xF2], opCode: [0x0F, 0x2A]},
    #{mnem: 'cvtsi2sd', opnds: ['xmm', 'r/m64'], prefix: [0xF2], opCode: [0x0F, 0x2A], REX_W: 1},

    # Convert scalar double to integer
    #{mnem: 'cvtsd2si', opnds: ['r32', 'xmm/m64'], prefix: [0xF2], opCode: [0x0F, 0x2D]},
    #{mnem: 'cvtsd2si', opnds: ['r64', 'xmm/m64'], prefix: [0xF2], opCode: [0x0F, 0x2D], REX_W: 1},

    # Decrement by 1
    #{mnem: 'dec', opnds: ['r/m8'], opCode: [0xFE], opExt: 1},
    #{mnem: 'dec', opnds: ['r/m16'], opCode: [0xFF], opExt: 1, szPref: true},
    #{mnem: 'dec', opnds: ['r/m32'], opCode: [0xFF], opExt: 1},
    #{mnem: 'dec', opnds: ['r/m64'], opCode: [0xFF], opExt: 1, REX_W: 1},
    #{mnem: 'dec', opnds: ['r16'], opCode: [0x48], szPref: true, x86_64: false},
    #{mnem: 'dec', opnds: ['r32'], opCode: [0x48], x86_64: false},

    # Unsigned integer division
    Op(
        'div',
        Enc(opnds=['r/m8'], opCode=[0xF6], opExt=6),
        Enc(opnds=['r/m16'], opCode=[0xF7], opExt=6),
        Enc(opnds=['r/m32'], opCode=[0xF7], opExt=6),
        Enc(opnds=['r/m64'], opCode=[0xF7], opExt=6),
    ),

    # Divide scalar double
    Op(
        'divsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opCode=[0x0F, 0x5E]),
    ),

    # Store and pop floating-point value (x87)
    Op(
        'fstp', 
        Enc(opnds=['m64'], opCode=[0xDD], opExt=3),
    ),

    # Signed integer division
    Op(
        'idiv',
        Enc(opnds=['r/m8'], opCode=[0xF6], opExt=7),
        Enc(opnds=['r/m16'], opCode=[0xF7], opExt=7),
        Enc(opnds=['r/m32'], opCode=[0xF7], opExt=7),
        Enc(opnds=['r/m64'], opCode=[0xF7], opExt=7),
    ),

    # Signed integer multiply
    Op(
        'imul',
        Enc(opnds=['r/m8'], opCode=[0xF6], opExt=5),
        Enc(opnds=['r/m16'], opCode=[0xF7], opExt=5),
        Enc(opnds=['r/m32'], opCode=[0xF7], opExt=5),
        Enc(opnds=['r/m64'], opCode=[0xF7], opExt=5),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x0F, 0xAF]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x0F, 0xAF]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x0F, 0xAF]),
        Enc(opnds=['r16', 'r/m16', 'imm8'], opCode=[0x6B]),
        Enc(opnds=['r32', 'r/m32', 'imm8'], opCode=[0x6B]),
        Enc(opnds=['r64', 'r/m64', 'imm8'], opCode=[0x6B]),
        Enc(opnds=['r16', 'r/m16', 'imm16'], opCode=[0x69]),
        Enc(opnds=['r32', 'r/m32', 'imm32'], opCode=[0x69]),
        Enc(opnds=['r64', 'r/m64', 'imm32'], opCode=[0x69]),
    ),

    # Increment by 1
    #{mnem: 'inc', opnds: ['r/m8'], opCode: [0xFE], opExt: 0},
    #{mnem: 'inc', opnds: ['r/m16'], opCode: [0xFF], opExt: 0, szPref: true},
    #{mnem: 'inc', opnds: ['r/m32'], opCode: [0xFF], opExt: 0},
    #{mnem: 'inc', opnds: ['r/m64'], opCode: [0xFF], opExt: 0, REX_W: 1},

    # Conditional jumps (relative near)
    Op('ja', 
        Enc(opnds=['rel8'], opCode=[0x77]),
        Enc(opnds=['rel32'], opCode=[0x0F, 0x87]),
    ),
    Op('jae',
        Enc(opnds=['rel8'], opCode=[0x73]),
        Enc(opnds=['rel32'], opCode=[0x0F, 0x83]),
    ),
    #{mnem: 'jb', opnds: ['rel8'], opCode=[0x72]},
    #{mnem: 'jb', opnds: ['rel32'], opCode=[0x0F, 0x82]},
    #{mnem: 'jbe', opnds: ['rel8'], opCode=[0x76]},
    #{mnem: 'jbe', opnds: ['rel32'], opCode=[0x0F, 0x86]},
    #{mnem: 'jc', opnds: ['rel8'], opCode=[0x72]},
    #{mnem: 'jc', opnds: ['rel32'], opCode=[0x0F, 0x82]},
    #{mnem: 'je', opnds: ['rel8'], opCode=[0x74]},
    #{mnem: 'je', opnds: ['rel32'], opCode=[0x0F, 0x84]},
    #{mnem: 'jg', opnds: ['rel8'], opCode=[0x7F]},
    #{mnem: 'jg', opnds: ['rel32'], opCode=[0x0F, 0x8F]},
    #{mnem: 'jge', opnds: ['rel8'], opCode=[0x7D]},
    #{mnem: 'jge', opnds: ['rel32'], opCode=[0x0F, 0x8D]},
    #{mnem: 'jl', opnds: ['rel8'], opCode=[0x7C]},
    #{mnem: 'jl', opnds: ['rel32'], opCode=[0x0F, 0x8C]},
    #{mnem: 'jle', opnds: ['rel8'], opCode=[0x7E]},
    #{mnem: 'jle', opnds: ['rel32'], opCode=[0x0F, 0x8E]},
    #{mnem: 'jna', opnds: ['rel8'], opCode=[0x76]},
    #{mnem: 'jna', opnds: ['rel32'], opCode=[0x0F, 0x86]},
    #{mnem: 'jnae', opnds: ['rel8'], opCode=[0x72]},
    #{mnem: 'jnae', opnds: ['rel32'], opCode=[0x0F, 0x82]},
    #{mnem: 'jnb', opnds: ['rel8'], opCode=[0x73]},
    #{mnem: 'jnb', opnds: ['rel32'], opCode=[0x0F, 0x83]},
    #{mnem: 'jnbe', opnds: ['rel8'], opCode=[0x77]},
    #{mnem: 'jnbe', opnds: ['rel32'], opCode=[0x0F, 0x87]},
    #{mnem: 'jnc', opnds: ['rel8'], opCode=[0x73]},
    #{mnem: 'jnc', opnds: ['rel32'], opCode=[0x0F, 0x83]},
    #{mnem: 'jne', opnds: ['rel8'], opCode=[0x75]},
    #{mnem: 'jne', opnds: ['rel32'], opCode=[0x0F, 0x85]},
    #{mnem: 'jng', opnds: ['rel8'], opCode=[0x7E]},
    #{mnem: 'jng', opnds: ['rel32'], opCode=[0x0F, 0x8E]},
    #{mnem: 'jnge', opnds: ['rel8'], opCode=[0x7C]},
    #{mnem: 'jnge', opnds: ['rel32'], opCode=[0x0F, 0x8C]},
    #{mnem: 'jnl', opnds: ['rel8'], opCode=[0x7D]},
    #{mnem: 'jnl', opnds: ['rel32'], opCode=[0x0F, 0x8D]},
    #{mnem: 'jnle', opnds: ['rel8'], opCode=[0x7F]},
    #{mnem: 'jnle', opnds: ['rel32'], opCode=[0x0F, 0x8F]},
    #{mnem: 'jno', opnds: ['rel8'], opCode=[0x71]},
    #{mnem: 'jno', opnds: ['rel32'], opCode=[0x0F, 0x81]},
    #{mnem: 'jnp', opnds: ['rel8'], opCode=[0x7B]},
    #{mnem: 'jnp', opnds: ['rel32'], opCode=[0x0F, 0x8b]},
    #{mnem: 'jns', opnds: ['rel8'], opCode=[0x79]},
    #{mnem: 'jns', opnds: ['rel32'], opCode=[0x0F, 0x89]},
    #{mnem: 'jnz', opnds: ['rel8'], opCode=[0x75]},
    #{mnem: 'jnz', opnds: ['rel32'], opCode=[0x0F, 0x85]},
    #{mnem: 'jo', opnds: ['rel8'], opCode=[0x70]},
    #{mnem: 'jo', opnds: ['rel32'], opCode=[0x0F, 0x80]},
    #{mnem: 'jp', opnds: ['rel8'], opCode=[0x7A]},
    #{mnem: 'jp', opnds: ['rel32'], opCode=[0x0F, 0x8A]},
    #{mnem: 'jpe', opnds: ['rel8'], opCode=[0x7A]},
    #{mnem: 'jpe', opnds: ['rel32'], opCode=[0x0F, 0x8A]},
    #{mnem: 'jpo', opnds: ['rel8'], opCode=[0x7B]},
    #{mnem: 'jpo', opnds: ['rel32'], opCode=[0x0F, 0x8B]},
    #{mnem: 'js', opnds: ['rel8'], opCode=[0x78]},
    #{mnem: 'js', opnds: ['rel32'], opCode=[0x0F, 0x88]},
    #{mnem: 'jz', opnds: ['rel8'], opCode=[0x74]},
    #{mnem: 'jz', opnds: ['rel32'], opCode=[0x0F, 0x84]},

    # Jump
    Op(
        'jmp',
        # Jump relative near
        Enc(opnds=['rel8'], opCode=[0xEB]),
        Enc(opnds=['rel32'], opCode=[0xE9]),
        # Jump absolute near
        Enc(opnds=['r/m64'], opCode=[0xFF], opExt=4),
    ),

    # Load effective address
    #{mnem: 'lea', opnds: ['r32', 'm'], opCode: [0x8D]},
    #{mnem: 'lea', opnds: ['r64', 'm'], opCode: [0x8D], REX_W: 1},

    # Move data
    Op(
        'mov',
        Enc(opnds=['r/m8', 'r8'], opCode=[0x88]),
        Enc(opnds=['r/m16', 'r16'], opCode=[0x89]),
        Enc(opnds=['r/m32', 'r32'], opCode=[0x89]),
        Enc(opnds=['r/m64', 'r64'], opCode=[0x89]),
        Enc(opnds=['r8', 'r/m8'], opCode=[0x8A]),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x8B]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x8B]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x8B]),
        Enc(opnds=['eax', 'moffs32'], opCode=[0xA1]),
        Enc(opnds=['rax', 'moffs64'], opCode=[0xA1]),
        Enc(opnds=['moffs32', 'eax'], opCode=[0xA3]),
        Enc(opnds=['moffs64', 'rax'], opCode=[0xA3]),
        Enc(opnds=['r8', 'imm8'], opCode=[0xB0]),
        Enc(opnds=['r16', 'imm16'], opCode=[0xB8]),
        Enc(opnds=['r32', 'imm32'], opCode=[0xB8]),
        Enc(opnds=['r64', 'imm64'], opCode=[0xB8]),
        Enc(opnds=['r/m8', 'imm8'], opCode=[0xC6]),
        Enc(opnds=['r/m16', 'imm16'], opCode=[0xC7], opExt=0),
        Enc(opnds=['r/m32', 'imm32'], opCode=[0xC7], opExt=0),
        Enc(opnds=['r/m64', 'imm32'], opCode=[0xC7], opExt=0),
    ),

    # Move memory-aligned packed double
    #{mnem: 'movapd', opnds: ['xmm', 'xmm/m128'], prefix: [0x66], opCode: [0x0F, 0x28]},
    #{mnem: 'movapd', opnds: ['xmm/m128', 'xmm'], prefix: [0x66], opCode: [0x0F, 0x29]},

    # Move scalar double to/from XMM
    #{mnem: 'movsd', opnds: ['xmm', 'xmm/m64'], prefix: [0xF2], opCode: [0x0F, 0x10]},
    #{mnem: 'movsd', opnds: ['xmm/m64', 'xmm'], prefix: [0xF2], opCode: [0x0F, 0x11]},

    # Move with sign extension
    #{mnem: 'movsx', opnds: ['r16', 'r/m8'], opCode: [0x0F, 0xBE], szPref: true},
    #{mnem: 'movsx', opnds: ['r32', 'r/m8'], opCode: [0x0F, 0xBE]},
    #{mnem: 'movsx', opnds: ['r64', 'r/m8'], opCode: [0x0F, 0xBE], REX_W: 1},
    #{mnem: 'movsx', opnds: ['r32', 'r/m16'], opCode: [0x0F, 0xBF]},
    #{mnem: 'movsx', opnds: ['r64', 'r/m16'], opCode: [0x0F, 0xBF], REX_W: 1},
    #{mnem: 'movsxd', opnds: ['r64', 'r/m32'], opCode: [0x63], REX_W: 1},

    # Move unaligned packed double
    #{mnem: 'movupd', opnds: ['xmm', 'xmm/m128'], prefix: [0x66], opCode: [0x0F, 0x10]},
    #{mnem: 'movupd', opnds: ['xmm/m128', 'xmm'], prefix: [0x66], opCode: [0x0F, 0x11]},

    # Move with zero extension (unsigned)
    #{mnem: 'movzx', opnds: ['r16', 'r/m8'], opCode: [0x0F, 0xB6], szPref: true},
    #{mnem: 'movzx', opnds: ['r32', 'r/m8'], opCode: [0x0F, 0xB6]},
    #{mnem: 'movzx', opnds: ['r64', 'r/m8'], opCode: [0x0F, 0xB6], REX_W: 1},
    #{mnem: 'movzx', opnds: ['r32', 'r/m16'], opCode: [0x0F, 0xB7]},
    #{mnem: 'movzx', opnds: ['r64', 'r/m16'], opCode: [0x0F, 0xB7], REX_W: 1},

    # Signed integer multiply
    Op(
        'mul',
        Enc(opnds=['r/m8'], opCode=[0xF6], opExt=4),
        Enc(opnds=['r/m16'], opCode=[0xF7], opExt=4),
        Enc(opnds=['r/m32'], opCode=[0xF7], opExt=4),
        Enc(opnds=['r/m64'], opCode=[0xF7], opExt=4),
    ),

    # Multiply scalar double
    Op(
        'mulsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opCode=[0x0F, 0x59]),
    ),

    # Negation (multiplication by -1)
    #{mnem: 'neg', opnds: ['r/m8'], opCode: [0xF6], opExt: 3},
    #{mnem: 'neg', opnds: ['r/m16'], opCode: [0xF7], opExt: 3, szPref: true},
    #{mnem: 'neg', opnds: ['r/m32'], opCode: [0xF7], opExt: 3},
    #{mnem: 'neg', opnds: ['r/m64'], opCode: [0xF7], opExt: 3, REX_W: 1},

    # No operation
    Op(
        'nop',
        Enc(opnds=[], opCode=[0x90])
    ),

    # Bitwise negation
    Op(
        'not',
         Enc(opnds=['r/m8'], opCode=[0xF6], opExt=2),
         Enc(opnds=['r/m16'], opCode=[0xF7], opExt=2),
         Enc(opnds=['r/m32'], opCode=[0xF7], opExt=2),
         Enc(opnds=['r/m64'], opCode=[0xF7], opExt=2),
    ),

    # Bitwise OR
    Op(
        'or',
        Enc(opnds=['al', 'imm8'], opCode=[0x0C]),
        Enc(opnds=['ax', 'imm16'], opCode=[0x0D]),
        Enc(opnds=['eax', 'imm32'], opCode=[0x0D]),           
        Enc(opnds=['rax', 'imm32'], opCode=[0x0D]),
        Enc(opnds=['r/m8', 'imm8'], opCode=[0x80], opExt=1),
        Enc(opnds=['r/m16', 'imm16'], opCode=[0x81], opExt=1),
        Enc(opnds=['r/m32', 'imm32'], opCode=[0x81], opExt=1),
        Enc(opnds=['r/m64', 'imm32'], opCode=[0x81], opExt=1),
        Enc(opnds=['r/m16', 'imm8'], opCode=[0x83], opExt=1),
        Enc(opnds=['r/m32', 'imm8'], opCode=[0x83], opExt=1),
        Enc(opnds=['r/m64', 'imm8'], opCode=[0x83], opExt=1),
        Enc(opnds=['r/m8', 'r8'], opCode=[0x08]),
        Enc(opnds=['r/m16', 'r16'], opCode=[0x09]),
        Enc(opnds=['r/m32', 'r32'], opCode=[0x09]),
        Enc(opnds=['r/m64', 'r64'], opCode=[0x09]),
        Enc(opnds=['r8', 'r/m8'], opCode=[0x0A]),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x0B]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x0B]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x0B]),
    ),

    # Pop off the stack
    Op(
        'pop',
        Enc(opnds=['r/m16'], opCode=[0x8F], opExt=0),
        Enc(opnds=['r/m64'], opCode=[0x8F], opExt=0),
        Enc(opnds=['r16'], opCode=[0x58]),
        Enc(opnds=['r64'], opCode=[0x58]),
    ),

    # Pop into the flags register
    Op(
        'popf',
        Enc(opnds=[], opCode=[0x9D], opndSize=16)
    ),
    Op(
        'popfq',
        Enc(opnds=[], opCode=[0x9D], opndSize=64)
    ),

    # Push on the stack
    Op(
        'push',
        Enc(opnds=['r/m16'], opCode=[0xFF], opExt=6),
        Enc(opnds=['r/m64'], opCode=[0xFF], opExt=6),
        Enc(opnds=['r16'], opCode=[0x50]),
        Enc(opnds=['r64'], opCode=[0x50]),
        Enc(opnds=['imm8'], opCode=[0x6A]),
        Enc(opnds=['imm32'], opCode=[0x68]),
    ),

    # Push the flags register
    Op(
        'pushf',
        Enc(opnds=[], opCode=[0x9C], opndSize=16)
    ),
    Op(
        'pushfq',
        Enc(opnds=[], opCode=[0x9C], opndSize=64)
    ),

    # Read performance monitoring counters
    Op(
        'rdpmc',
        Enc(opnds=[], opCode=[0x0F, 0x33]),
    ),

    # Read time stamp counter
    Op(
        'rdtsc',
        Enc(opnds=[], opCode=[0x0F, 0x31]),
    ),

    # Return
    Op(
        'ret',
        Enc(opnds=[], opCode=[0xC3]),
        # Return and pop bytes off the stack
        Enc(opnds=['imm16'], opCode=[0xC2]),
    ),

    # Round scalar double
    # The rounding mode is determined by the immediate
    Op(
        'roundsd',
        Enc(opnds=['xmm', 'xmm/m64', 'imm8'], prefix=[0x66], opCode=[0x0F, 0x3A, 0x0B]),
    ),

    # Shift arithmetic left
    #{mnem: 'sal', opnds: ['r/m8', 1], opCode: [0xD0], opExt: 4},
    #{mnem: 'sal', opnds: ['r/m8', 'cl'], opCode: [0xD2], opExt: 4},
    #{mnem: 'sal', opnds: ['r/m8', 'imm8'], opCode: [0xC0], opExt: 4},
    #{mnem: 'sal', opnds: ['r/m16', 1], opCode: [0xD1], opExt: 4, szPref: true},
    #{mnem: 'sal', opnds: ['r/m16', 'cl'], opCode: [0xD3], opExt: 4, szPref: true},
    #{mnem: 'sal', opnds: ['r/m16', 'imm8'], opCode: [0xC1], opExt: 4, szPref: true},
    #{mnem: 'sal', opnds: ['r/m32', 1], opCode: [0xD1], opExt: 4},
    #{mnem: 'sal', opnds: ['r/m32', 'cl'], opCode: [0xD3], opExt: 4},
    #{mnem: 'sal', opnds: ['r/m32', 'imm8'], opCode: [0xC1], opExt: 4},
    #{mnem: 'sal', opnds: ['r/m64', 1], opCode: [0xD1], opExt: 4, REX_W: 1},
    #{mnem: 'sal', opnds: ['r/m64', 'cl'], opCode: [0xD3], opExt: 4, REX_W: 1},
    #{mnem: 'sal', opnds: ['r/m64', 'imm8'], opCode: [0xC1], opExt: 4, REX_W: 1},

    # Shift arithmetic right (signed)
    #{mnem: 'sar', opnds: ['r/m8', 1], opCode: [0xD0], opExt: 7},
    #{mnem: 'sar', opnds: ['r/m8', 'cl'], opCode: [0xD2], opExt: 7},
    #{mnem: 'sar', opnds: ['r/m8', 'imm8'], opCode: [0xC0], opExt: 7},
    #{mnem: 'sar', opnds: ['r/m16', 1], opCode: [0xD1], opExt: 7, szPref: true},
    #{mnem: 'sar', opnds: ['r/m16', 'cl'], opCode: [0xD3], opExt: 7, szPref: true},
    #{mnem: 'sar', opnds: ['r/m16', 'imm8'], opCode: [0xC1], opExt: 7, szPref: true},
    #{mnem: 'sar', opnds: ['r/m32', 1], opCode: [0xD1], opExt: 7},
    #{mnem: 'sar', opnds: ['r/m32', 'cl'], opCode: [0xD3], opExt: 7},
    #{mnem: 'sar', opnds: ['r/m32', 'imm8'], opCode: [0xC1], opExt: 7},
    #{mnem: 'sar', opnds: ['r/m64', 1], opCode: [0xD1], opExt: 7, REX_W: 1},
    #{mnem: 'sar', opnds: ['r/m64', 'cl'], opCode: [0xD3], opExt: 7, REX_W: 1},
    #{mnem: 'sar', opnds: ['r/m64', 'imm8'], opCode: [0xC1], opExt: 7, REX_W: 1},

    # Shift logical left
    #{mnem: 'shl', opnds: ['r/m8', 1], opCode: [0xD0], opExt: 4},
    #{mnem: 'shl', opnds: ['r/m8', 'cl'], opCode: [0xD2], opExt: 4},
    #{mnem: 'shl', opnds: ['r/m8', 'imm8'], opCode: [0xC0], opExt: 4},
    #{mnem: 'shl', opnds: ['r/m16', 1], opCode: [0xD1], opExt: 4, szPref: true},
    #{mnem: 'shl', opnds: ['r/m16', 'cl'], opCode: [0xD3], opExt: 4, szPref: true},
    #{mnem: 'shl', opnds: ['r/m16', 'imm8'], opCode: [0xC1], opExt: 4, szPref: true},
    #{mnem: 'shl', opnds: ['r/m32', 1], opCode: [0xD1], opExt: 4},
    #{mnem: 'shl', opnds: ['r/m32', 'cl'], opCode: [0xD3], opExt: 4},
    #{mnem: 'shl', opnds: ['r/m32', 'imm8'], opCode: [0xC1], opExt: 4},
    #{mnem: 'shl', opnds: ['r/m64', 1], opCode: [0xD1], opExt: 4, REX_W: 1},
    #{mnem: 'shl', opnds: ['r/m64', 'cl'], opCode: [0xD3], opExt: 4, REX_W: 1},
    #{mnem: 'shl', opnds: ['r/m64', 'imm8'], opCode: [0xC1], opExt: 4, REX_W: 1},

    # Shift logical right (unsigned)
    #{mnem: 'shr', opnds: ['r/m8', 1], opCode: [0xD0], opExt: 5},
    #{mnem: 'shr', opnds: ['r/m8', 'cl'], opCode: [0xD2], opExt: 5},
    #{mnem: 'shr', opnds: ['r/m8', 'imm8'], opCode: [0xC0], opExt: 5},
    #{mnem: 'shr', opnds: ['r/m16', 1], opCode: [0xD1], opExt: 5, szPref: true},
    #{mnem: 'shr', opnds: ['r/m16', 'cl'], opCode: [0xD3], opExt: 5, szPref: true},
    #{mnem: 'shr', opnds: ['r/m16', 'imm8'], opCode: [0xC1], opExt: 5, szPref: true},
    #{mnem: 'shr', opnds: ['r/m32', 1], opCode: [0xD1], opExt: 5},
    #{mnem: 'shr', opnds: ['r/m32', 'cl'], opCode: [0xD3], opExt: 5},
    #{mnem: 'shr', opnds: ['r/m32', 'imm8'], opCode: [0xC1], opExt: 5},
    #{mnem: 'shr', opnds: ['r/m64', 1], opCode: [0xD1], opExt: 5, REX_W: 1},
    #{mnem: 'shr', opnds: ['r/m64', 'cl'], opCode: [0xD3], opExt: 5, REX_W: 1},
    #{mnem: 'shr', opnds: ['r/m64', 'imm8'], opCode: [0xC1], opExt: 5, REX_W: 1},

    # Square root of scalar doubles (SSE2)
    Op(
        'sqrtsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opCode=[0x0F, 0x51]),
    ),

    # Integer subtraction
    Op(
        'sub',
        Enc(opnds=['al', 'imm8'], opCode=[0x2C]),
        Enc(opnds=['ax', 'imm16'], opCode=[0x2D]),
        Enc(opnds=['eax', 'imm32'], opCode=[0x2D]),
        Enc(opnds=['rax', 'imm32'], opCode=[0x2D]),
        Enc(opnds=['r/m8', 'imm8'], opCode=[0x80], opExt=5),
        Enc(opnds=['r/m16', 'imm16'], opCode=[0x81], opExt=5),
        Enc(opnds=['r/m32', 'imm32'], opCode=[0x81], opExt=5),
        Enc(opnds=['r/m64', 'imm32'], opCode=[0x81], opExt=5),
        Enc(opnds=['r/m16', 'imm8'], opCode=[0x83], opExt=5),
        Enc(opnds=['r/m32', 'imm8'], opCode=[0x83], opExt=5),
        Enc(opnds=['r/m64', 'imm8'], opCode=[0x83], opExt=5),
        Enc(opnds=['r/m8', 'r8'], opCode=[0x28]),
        Enc(opnds=['r/m16', 'r16'], opCode=[0x29]),
        Enc(opnds=['r/m32', 'r32'], opCode=[0x29]),
        Enc(opnds=['r/m64', 'r64'], opCode=[0x29]),
        Enc(opnds=['r8', 'r/m8'], opCode=[0x2A]),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x2B]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x2B]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x2B]),
    ),

    # Subtract scalar double
    Op(
        'subsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opCode=[0x0F, 0x5C]),
    ),

    # Logical AND compare
    #{mnem: 'test', opnds: ['al', 'imm8'], opCode: [0xA8]},
    #{mnem: 'test', opnds: ['ax', 'imm16'], opCode: [0xA9], szPref: true},
    #{mnem: 'test', opnds: ['eax', 'imm32'], opCode: [0xA9]},           
    #{mnem: 'test', opnds: ['rax', 'imm32'], opCode: [0xA9], REX_W: 1},
    #{mnem: 'test', opnds: ['r/m8', 'imm8'], opCode: [0xF6], opExt: 0},
    #{mnem: 'test', opnds: ['r/m16', 'imm16'], opCode: [0xF7], opExt: 0, szPref: true},
    #{mnem: 'test', opnds: ['r/m32', 'imm32'], opCode: [0xF7], opExt: 0},
    #{mnem: 'test', opnds: ['r/m64', 'imm32'], opCode: [0xF7], opExt: 0, REX_W: 1},
    #{mnem: 'test', opnds: ['r/m8', 'r8'], opCode: [0x84]},
    #{mnem: 'test', opnds: ['r/m16', 'r16'], opCode: [0x85], szPref: true},
    #{mnem: 'test', opnds: ['r/m32', 'r32'], opCode: [0x85]},
    #{mnem: 'test', opnds: ['r/m64', 'r64'], opCode: [0x85], REX_W: 1},

    # Unordered compare scalar double
    Op(
        'ucomisd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0x66], opCode=[0x0F, 0x2E]),
    ),

    # Exchange
    # The ax/eax/rax + rXX variants use the opcode reg field
    #{mnem: 'xchg', opnds: ['ax', 'r16'], opCode: [0x90], szPref: true},
    #{mnem: 'xchg', opnds: ['r16', 'ax'], opCode: [0x90], szPref: true},
    #{mnem: 'xchg', opnds: ['eax', 'r32'], opCode: [0x90]},
    #{mnem: 'xchg', opnds: ['r32', 'eax'], opCode: [0x90]},
    #{mnem: 'xchg', opnds: ['rax', 'r64'], opCode: [0x90], REX_W: 1},
    #{mnem: 'xchg', opnds: ['r64', 'eax'], opCode: [0x90], REX_W: 1},
    #{mnem: 'xchg', opnds: ['r/m8', 'r8'], opCode: [0x86]},
    #{mnem: 'xchg', opnds: ['r8', 'r/m8'], opCode: [0x86]},
    #{mnem: 'xchg', opnds: ['r/m16', 'r16'], opCode: [0x87], szPref: true},
    #{mnem: 'xchg', opnds: ['r/m32', 'r32'], opCode: [0x87]},
    #{mnem: 'xchg', opnds: ['r/m64', 'r64'], opCode: [0x87], REX_W: 1},
    #{mnem: 'xchg', opnds: ['r16', 'r/m16'], opCode: [0x87], szPref: true},
    #{mnem: 'xchg', opnds: ['r32', 'r/m32'], opCode: [0x87]},
    #{mnem: 'xchg', opnds: ['r64', 'r/m64'], opCode: [0x87], REX_W: 1},

    # Exclusive bitwise OR
    Op(
        'xor',
        Enc(opnds=['al', 'imm8'], opCode=[0x34]),
        Enc(opnds=['ax', 'imm16'], opCode=[0x35]),
        Enc(opnds=['eax', 'imm32'], opCode=[0x35]),
        Enc(opnds=['rax', 'imm32'], opCode=[0x35]),
        Enc(opnds=['r/m8', 'imm8'], opCode=[0x80], opExt=6),
        Enc(opnds=['r/m16', 'imm16'], opCode=[0x81], opExt=6),
        Enc(opnds=['r/m32', 'imm32'], opCode=[0x81], opExt=6),
        Enc(opnds=['r/m64', 'imm32'], opCode=[0x81], opExt=6),
        Enc(opnds=['r/m16', 'imm8'], opCode=[0x83], opExt=6),
        Enc(opnds=['r/m32', 'imm8'], opCode=[0x83], opExt=6),
        Enc(opnds=['r/m64', 'imm8'], opCode=[0x83], opExt=6),
        Enc(opnds=['r/m8', 'r8'], opCode=[0x30]),
        Enc(opnds=['r/m16', 'r16'], opCode=[0x31]),
        Enc(opnds=['r/m32', 'r32'], opCode=[0x31]),
        Enc(opnds=['r/m64', 'r64'], opCode=[0x31]),
        Enc(opnds=['r8', 'r/m8'], opCode=[0x32]),
        Enc(opnds=['r16', 'r/m16'], opCode=[0x33]),
        Enc(opnds=['r32', 'r/m32'], opCode=[0x33]),
        Enc(opnds=['r64', 'r/m64'], opCode=[0x33]),
    ),
]

# Get the size in bits of an operand designation
def opndSize(opnd):

    if opnd.endswith('8') or opnd == 'al':
        return 8

    if opnd.endswith('16') or opnd == 'ax':
        return 16

    if opnd.endswith('32') or opnd == 'eax':
        return 32

    if opnd.endswith('64') or opnd == 'rax':
        return 64

    if opnd == 'xmm':
        return 128

    raise Exception("unknown operand " + opnd)

# For each opcode in the instruction table
for op in instrTable:

    # For each possible encoding of this opcode
    for enc in op.encs:

        if len(enc.opCode) == 0 or len(enc.opCode) > 3:
            raise Exception('invalid opcode length')

        if enc.opExt != None and not (enc.opExt >= 0 and enc.opExt <= 7):
            raise Exception('invalid opcode extension')

        # Try to infer the operand size from operands if necessary
        if enc.opndSize == None:
            if len(enc.opnds) > 0:
                enc.opndSize = opndSize(enc.opnds[0])
            else:
                enc.opndSize = 32

        # Determine necessity of szPref, rexW
        enc.szPref = (enc.opndSize == 16)
        enc.rexW   = (enc.rexW == None and enc.opndSize == 64)

    # Sort encodings by decreasing operand size
    op.encs.sort(key=lambda e: -e.opndSize)

# Open the output file for writing
DFile = open(D_OUT_FILE, 'w')

comment =                                                               \
'//\n' +                                                                \
'// Code auto-generated from "' + sys.argv[0] + '". Do not modify.\n' + \
'//\n\n'

DFile.write(comment)




# TODO





DFile.close()

