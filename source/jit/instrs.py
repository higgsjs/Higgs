import sys
import string
from copy import deepcopy

D_OUT_FILE = 'jit/instrs.d'

class Op:
    def __init__(self, mnem, *args):
        self.mnem = mnem
        self.encs = args

        # TODO: sort encodings by decreasing opndSize

        # TODO: determine szPref, rexW

class Enc:
    def __init__(self, opnds, opCode, opExt=None, opndSize=None):

        self.opnds = opnds
        self.opCode = opCode
        self.opExt = opExt

        # TODO: try to infer opnd size from operands if none
        if opndSize != None:
            self.opndSize = opndSize
        else:
            pass

        self.szPref = False
        self.rexW = False

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

    # Conditional jumps (relative near)
    #{mnem: 'ja', opnds: ['rel8'], opCode: [0x77]},
    #{mnem: 'jae', opnds: ['rel8'], opCode: [0x73]},
    #{mnem: 'jb', opnds: ['rel8'], opCode: [0x72]},
    #{mnem: 'jbe', opnds: ['rel8'], opCode: [0x76]},
    #{mnem: 'jc', opnds: ['rel8'], opCode: [0x72]},
    #{mnem: 'je', opnds: ['rel8'], opCode: [0x74]},
    #{mnem: 'jg', opnds: ['rel8'], opCode: [0x7F]},
    #{mnem: 'jge', opnds: ['rel8'], opCode: [0x7D]},
    #{mnem: 'jl', opnds: ['rel8'], opCode: [0x7C]},
    #{mnem: 'jle', opnds: ['rel8'], opCode: [0x7E]},
    #{mnem: 'jna', opnds: ['rel8'], opCode: [0x76]},
    #{mnem: 'jnae', opnds: ['rel8'], opCode: [0x72]},
    #{mnem: 'jnb', opnds: ['rel8'], opCode: [0x73]},
    #{mnem: 'jnbe', opnds: ['rel8'], opCode: [0x77]},
    #{mnem: 'jnc', opnds: ['rel8'], opCode: [0x73]},
    #{mnem: 'jne', opnds: ['rel8'], opCode: [0x75]},
    #{mnem: 'jng', opnds: ['rel8'], opCode: [0x7E]},
    #{mnem: 'jnge', opnds: ['rel8'], opCode: [0x7C]},
    #{mnem: 'jnl', opnds: ['rel8'], opCode: [0x7D]},
    #{mnem: 'jnle', opnds: ['rel8'], opCode: [0x7F]},
    #{mnem: 'jno', opnds: ['rel8'], opCode: [0x71]},
    #{mnem: 'jnp', opnds: ['rel8'], opCode: [0x7B]},
    #{mnem: 'jns', opnds: ['rel8'], opCode: [0x79]},
    #{mnem: 'jnz', opnds: ['rel8'], opCode: [0x75]},
    #{mnem: 'jo', opnds: ['rel8'], opCode: [0x70]},
    #{mnem: 'jp', opnds: ['rel8'], opCode: [0x7A]},
    #{mnem: 'jpe', opnds: ['rel8'], opCode: [0x7A]},
    #{mnem: 'jpo', opnds: ['rel8'], opCode: [0x7B]},
    #{mnem: 'js', opnds: ['rel8'], opCode: [0x78]},
    #{mnem: 'jz', opnds: ['rel8'], opCode: [0x74]},
    #{mnem: 'ja', opnds: ['rel32'], opCode: [0x0F, 0x87]},
    #{mnem: 'jae', opnds: ['rel32'], opCode: [0x0F, 0x83]},
    #{mnem: 'jb', opnds: ['rel32'], opCode: [0x0F, 0x82]},
    #{mnem: 'jbe', opnds: ['rel32'], opCode: [0x0F, 0x86]},
    #{mnem: 'jc', opnds: ['rel32'], opCode: [0x0F, 0x82]},
    #{mnem: 'je', opnds: ['rel32'], opCode: [0x0F, 0x84]},
    #{mnem: 'jz', opnds: ['rel32'], opCode: [0x0F, 0x84]},
    #{mnem: 'jg', opnds: ['rel32'], opCode: [0x0F, 0x8F]},
    #{mnem: 'jge', opnds: ['rel32'], opCode: [0x0F, 0x8D]},
    #{mnem: 'jl', opnds: ['rel32'], opCode: [0x0F, 0x8C]},
    #{mnem: 'jle', opnds: ['rel32'], opCode: [0x0F, 0x8E]},
    #{mnem: 'jna', opnds: ['rel32'], opCode: [0x0F, 0x86]},
    #{mnem: 'jnae', opnds: ['rel32'], opCode: [0x0F, 0x82]},
    #{mnem: 'jnb', opnds: ['rel32'], opCode: [0x0F, 0x83]},
    #{mnem: 'jnbe', opnds: ['rel32'], opCode: [0x0F, 0x87]},
    #{mnem: 'jnc', opnds: ['rel32'], opCode: [0x0F, 0x83]},
    #{mnem: 'jne', opnds: ['rel32'], opCode: [0x0F, 0x85]},
    #{mnem: 'jng', opnds: ['rel32'], opCode: [0x0F, 0x8E]},
    #{mnem: 'jnge', opnds: ['rel32'], opCode: [0x0F, 0x8C]},
    #{mnem: 'jnl', opnds: ['rel32'], opCode: [0x0F, 0x8D]},
    #{mnem: 'jnle', opnds: ['rel32'], opCode: [0x0F, 0x8F]},
    #{mnem: 'jno', opnds: ['rel32'], opCode: [0x0F, 0x81]},
    #{mnem: 'jnp', opnds: ['rel32'], opCode: [0x0F, 0x8b]},
    #{mnem: 'jns', opnds: ['rel32'], opCode: [0x0F, 0x89]},
    #{mnem: 'jnz', opnds: ['rel32'], opCode: [0x0F, 0x85]},
    #{mnem: 'jo', opnds: ['rel32'], opCode: [0x0F, 0x80]},
    #{mnem: 'jp', opnds: ['rel32'], opCode: [0x0F, 0x8A]},
    #{mnem: 'jpe', opnds: ['rel32'], opCode: [0x0F, 0x8A]},
    #{mnem: 'jpo', opnds: ['rel32'], opCode: [0x0F, 0x8B]},
    #{mnem: 'js', opnds: ['rel32'], opCode: [0x0F, 0x88]},
    #{mnem: 'jz', opnds: ['rel32'], opCode: [0x0F, 0x84]},

    # Call (relative and absolute)
    Op(
        'jmp',
        Enc(opnds=['rel32'], opCode=[0xE8]),
        Enc(opnds=['r/m64'], opCode=[0xFF], opExt=2),
    ),

    # Jump
    Op(
        'jmp',
        # Jump relative near
        Enc(opnds=['rel8'], opCode=[0xEB]),
        Enc(opnds=['rel32'], opCode=[0xE9]),
        # Jump absolute near
        Enc(opnds=['r/m64'], opCode=[0xFF], opExt=4),
    ),

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

    # Signed integer multiply
    Op(
        'mul',
        Enc(opnds=['r/m8'], opCode=[0xF6], opExt=4),
        Enc(opnds=['r/m16'], opCode=[0xF7], opExt=4),
        Enc(opnds=['r/m32'], opCode=[0xF7], opExt=4),
        Enc(opnds=['r/m64'], opCode=[0xF7], opExt=4),
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

    # Return
    Op(
        'ret',
        Enc(opnds=[], opCode=[0xC3]),
        # Return and pop bytes off the stack
        Enc(opnds=['imm16'], opCode=[0xC2]),
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
]

# Open the output file for writing
DFile = open(D_OUT_FILE, 'w')

comment =                                                               \
'//\n' +                                                                \
'// Code auto-generated from "' + sys.argv[0] + '". Do not modify.\n' + \
'//\n\n'

DFile.write(comment)




# TODO





DFile.close()

