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
    def __init__(self, opnds, opcode, prefix=[], opExt=None, opndSize=None, szPref=None, rexW=None):
        self.opnds = opnds
        self.opcode = opcode
        self.prefix = prefix
        self.opExt = opExt
        self.opndSize = opndSize
        self.szPref = szPref
        self.rexW = rexW

# x86 instruction description table.
# This table can contain multiple entries per instruction.
#
# mnem    : mnemonic name
# opnds   : operands, dst first
# opcode  : opcode bytes
# opExt   : opcode extension byte
instrTable = [

    # Integer addition
    Op(
        'add',
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
    ),

    # Add scalar double
    Op(
        'addsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x58], rexW=False),
    ),

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

    # Call (relative and absolute)
    Op(
        'call',
        Enc(opnds=['rel32'], opcode=[0xE8]),
        Enc(opnds=['r/m64'], opcode=[0xFF], opExt=2, rexW=False)
    ),

    # Convert word to doubleword (sign extension)
    # Used before div and idiv
    Op(
        'cwd', 
        Enc(opnds=[], opcode=[0x99], opndSize=16),
    ),
    Op(
        'cdq', 
        Enc(opnds=[], opcode=[0x99], opndSize=32),
    ),
    Op(
        'cqo', 
        Enc(opnds=[], opcode=[0x99], opndSize=64),
    ),

    # Conditional move
    Op(
        'cmova',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x47]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x47]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x47]),
    ),
    Op(
        'cmovae',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x43]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x43]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x43]),
    ),
    Op(
        'cmovb',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x42]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x42]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x42]),
    ),
    Op(
        'cmovbe',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x46]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x46]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x46]),
    ),
    Op(
        'cmovc',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x42]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x42]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x42]),
    ),
    Op(
        'cmove',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x44]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x44]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x44]),
    ),
    Op(
        'cmovg',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4F]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4F]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4F]),
    ),
    Op(
        'cmovge',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4D]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4D]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4D]),
    ),
    Op(
        'cmovl',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4C]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4C]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4C]),
    ),
    Op(
        'cmovle',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4E]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4E]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4E]),
    ),
    Op(
        'cmovna',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x46]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x46]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x46]),
    ),
    Op(
        'cmovnae',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x42]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x42]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x42]),
    ),
    Op(
        'cmovnb',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x43]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x43]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x43]),
    ),
    Op(
        'cmovnbe',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x47]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x47]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x47]),
    ),
    Op(
        'cmovnc',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x43]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x43]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x43]),
    ),
    Op(
        'cmovne',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x45]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x45]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x45]),
    ),
    Op(
        'cmovng',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4E]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4E]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4E]),
    ),
    Op(
        'cmovnge',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4C]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4C]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4C]),
    ),
    Op(
        'cmovnl',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4D]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4D]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4D]),
    ),
    Op(
        'cmovnle',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4F]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4F]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4F]),
    ),
    Op(
        'cmovno',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x41]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x41]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x41]),
    ),
    Op(
        'cmovnp',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4B]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4B]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4B]),
    ),
    Op(
        'cmovns',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x49]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x49]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x49]),
    ),
    Op(
        'cmovnz',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x45]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x45]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x45]),
    ),
    Op(
        'cmovo',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x40]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x40]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x40]),
    ),
    Op(
        'cmovp',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4A]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4A]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4A]),
    ),
    Op(
        'cmovpe',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4A]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4A]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4A]),
    ),
    Op(
        'cmovpo',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x4B]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x4B]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x4B]),
    ),
    Op(
        'cmovs',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x48]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x48]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x48]),
    ),
    Op(
        'cmovz',
        Enc(opnds=['r16', 'r/m16'], opcode=[0x0F, 0x44]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x0F, 0x44]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x0F, 0x44]),
    ),

    # Integer comparison
    Op(
        'cmp',
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
    ),

    # Convert integer to scalar double
    Op(
        'cvtsi2sd', 
        Enc(opnds=['xmm', 'r/m32'], prefix=[0xF2], opcode=[0x0F, 0x2A]),
        Enc(opnds=['xmm', 'r/m64'], prefix=[0xF2], opcode=[0x0F, 0x2A]),
    ),

    # Convert scalar double to integer
    Op(
        'cvtsd2si', 
        Enc(opnds=['r32', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x2D]),
        Enc(opnds=['r64', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x2D]),
    ),

    # Decrement by 1
    Op(
        'dec', 
        Enc(opnds=['r/m8'], opcode=[0xFE], opExt=1),
        Enc(opnds=['r/m16'], opcode=[0xFF], opExt=1),
        Enc(opnds=['r/m32'], opcode=[0xFF], opExt=1),
        Enc(opnds=['r/m64'], opcode=[0xFF], opExt=1),
    ),

    # Unsigned integer division
    Op(
        'div',
        Enc(opnds=['r/m8'], opcode=[0xF6], opExt=6),
        Enc(opnds=['r/m16'], opcode=[0xF7], opExt=6),
        Enc(opnds=['r/m32'], opcode=[0xF7], opExt=6),
        Enc(opnds=['r/m64'], opcode=[0xF7], opExt=6),
    ),

    # Divide scalar double
    Op(
        'divsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x5E]),
    ),

    # Store and pop floating-point value (x87)
    Op(
        'fstp', 
        Enc(opnds=['m64'], opcode=[0xDD], opExt=3, rexW=False),
    ),

    # Signed integer division
    Op(
        'idiv',
        Enc(opnds=['r/m8'], opcode=[0xF6], opExt=7),
        Enc(opnds=['r/m16'], opcode=[0xF7], opExt=7),
        Enc(opnds=['r/m32'], opcode=[0xF7], opExt=7),
        Enc(opnds=['r/m64'], opcode=[0xF7], opExt=7),
    ),

    # Signed integer multiply
    Op(
        'imul',
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
    ),

    # Increment by 1
    Op(
        'inc',
        Enc(opnds=['r/m8'], opcode=[0xFE], opExt=0),
        Enc(opnds=['r/m16'], opcode=[0xFF], opExt=0),
        Enc(opnds=['r/m32'], opcode=[0xFF], opExt=0),
        Enc(opnds=['r/m64'], opcode=[0xFF], opExt=0),
    ),

    # Conditional jumps (relative near)
    Op('ja', 
        Enc(opnds=['rel8'], opcode=[0x77]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x87]),
    ),
    Op('jae',
        Enc(opnds=['rel8'], opcode=[0x73]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x83]),
    ),
    Op(
        'jb',
        Enc(opnds=['rel8'], opcode=[0x72]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x82]),
    ),
    Op(
        'jbe',
        Enc(opnds=['rel8'], opcode=[0x76]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x86]),
    ),
    Op(
        'jc',
        Enc(opnds=['rel8'], opcode=[0x72]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x82]),
    ),
    Op(
        'je',
        Enc(opnds=['rel8'], opcode=[0x74]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x84]),
    ),
    Op(
        'jg',
        Enc(opnds=['rel8'], opcode=[0x7F]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8F]),
    ),
    Op(
        'jge',
        Enc(opnds=['rel8'], opcode=[0x7D]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8D]),
    ),
    Op(
        'jl',
        Enc(opnds=['rel8'], opcode=[0x7C]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8C]),
    ),
    Op(
        'jle',
        Enc(opnds=['rel8'], opcode=[0x7E]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8E]),
    ),
    Op(
        'jna',
        Enc(opnds=['rel8'], opcode=[0x76]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x86]),
    ),
    Op(
        'jnae',
        Enc(opnds=['rel8'], opcode=[0x72]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x82]),
    ),
    Op(
        'jnb',
        Enc(opnds=['rel8'], opcode=[0x73]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x83]),
    ),
    Op(
        'jnbe',
        Enc(opnds=['rel8'], opcode=[0x77]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x87]),
    ),
    Op(
        'jnc',
        Enc(opnds=['rel8'], opcode=[0x73]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x83]),
    ),
    Op(
        'jne',
        Enc(opnds=['rel8'], opcode=[0x75]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x85]),
    ),
    Op(
        'jng',
        Enc(opnds=['rel8'], opcode=[0x7E]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8E]),
    ),
    Op(
        'jnge',
        Enc(opnds=['rel8'], opcode=[0x7C]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8C]),
    ),
    Op(
        'jnl',
        Enc(opnds=['rel8'], opcode=[0x7D]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8D]),
    ),
    Op(
        'jnle',
        Enc(opnds=['rel8'], opcode=[0x7F]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8F]),
    ),
    Op(
        'jno',
        Enc(opnds=['rel8'], opcode=[0x71]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x81]),
    ),
    Op(
        'jnp',
        Enc(opnds=['rel8'], opcode=[0x7B]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8b]),
    ),
    Op(
        'jns',
        Enc(opnds=['rel8'], opcode=[0x79]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x89]),
    ),
    Op(
        'jnz',
        Enc(opnds=['rel8'], opcode=[0x75]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x85]),
    ),
    Op(
        'jo',
        Enc(opnds=['rel8'], opcode=[0x70]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x80]),
    ),
    Op(
        'jp',
        Enc(opnds=['rel8'], opcode=[0x7A]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8A]),
    ),
    Op(
        'jpe',
        Enc(opnds=['rel8'], opcode=[0x7A]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8A]),
    ),
    Op(
        'jpo',
        Enc(opnds=['rel8'], opcode=[0x7B]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x8B]),
    ),
    Op(
        'js',
        Enc(opnds=['rel8'], opcode=[0x78]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x88]),
    ),
    Op(
        'jz',
        Enc(opnds=['rel8'], opcode=[0x74]),
        Enc(opnds=['rel32'], opcode=[0x0F, 0x84]),
    ),

    # Jump
    Op(
        'jmp',
        # Jump relative near
        Enc(opnds=['rel8'], opcode=[0xEB]),
        Enc(opnds=['rel32'], opcode=[0xE9]),
        # Jump absolute near
        Enc(opnds=['r/m64'], opcode=[0xFF], opExt=4),
    ),

    # Load effective address
    Op(
        'lea',
        Enc(opnds=['r32', 'm'], opcode=[0x8D]),
        Enc(opnds=['r64', 'm'], opcode=[0x8D]),
    ),

    # Move data
    Op(
        'mov',
        Enc(opnds=['r/m8', 'r8'], opcode=[0x88]),
        Enc(opnds=['r/m16', 'r16'], opcode=[0x89]),
        Enc(opnds=['r/m32', 'r32'], opcode=[0x89]),
        Enc(opnds=['r/m64', 'r64'], opcode=[0x89]),
        Enc(opnds=['r8', 'r/m8'], opcode=[0x8A]),
        Enc(opnds=['r16', 'r/m16'], opcode=[0x8B]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x8B]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x8B]),
        Enc(opnds=['eax', 'moffs32'], opcode=[0xA1]),
        Enc(opnds=['rax', 'moffs64'], opcode=[0xA1]),
        Enc(opnds=['moffs32', 'eax'], opcode=[0xA3]),
        Enc(opnds=['moffs64', 'rax'], opcode=[0xA3]),
        Enc(opnds=['r8', 'imm8'], opcode=[0xB0]),
        Enc(opnds=['r16', 'imm16'], opcode=[0xB8]),
        Enc(opnds=['r32', 'imm32'], opcode=[0xB8]),
        Enc(opnds=['r64', 'imm64'], opcode=[0xB8]),
        Enc(opnds=['r/m8', 'imm8'], opcode=[0xC6]),
        Enc(opnds=['r/m16', 'imm16'], opcode=[0xC7], opExt=0),
        Enc(opnds=['r/m32', 'imm32'], opcode=[0xC7], opExt=0),
        Enc(opnds=['r/m64', 'imm32'], opcode=[0xC7], opExt=0),
    ),

    # Move memory-aligned packed double
    Op(
        'movapd', 
        Enc(opnds=['xmm', 'xmm/m128'], prefix=[0x66], opcode=[0x0F, 0x28]),
        Enc(opnds=['xmm/m128', 'xmm'], prefix=[0x66], opcode=[0x0F, 0x29]),
    ),

    # Move scalar double to/from XMM
    Op(
        'movsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x10], rexW=False),
        Enc(opnds=['xmm/m64', 'xmm'], prefix=[0xF2], opcode=[0x0F, 0x11], rexW=False),
    ),

    # Move quadword
    Op(
        'movq',
        Enc(opnds=['xmm', 'r/m64'], prefix=[0x66], opcode=[0x0F, 0x6E]),
        Enc(opnds=['r/m64', 'xmm'], prefix=[0x66], opcode=[0x0F, 0x7E]),
    ),

    # Move with sign extension
    Op(
        'movsx',
        Enc(opnds=['r16', 'r/m8'], opcode=[0x0F, 0xBE]),
        Enc(opnds=['r32', 'r/m8'], opcode=[0x0F, 0xBE]),
        Enc(opnds=['r64', 'r/m8'], opcode=[0x0F, 0xBE]),
        Enc(opnds=['r32', 'r/m16'], opcode=[0x0F, 0xBF]),
        Enc(opnds=['r64', 'r/m16'], opcode=[0x0F, 0xBF]),
    ),
    Op(
        'movsxd',
        Enc(opnds=['r64', 'r/m32'], opcode=[0x63]),
    ),

    # Move unaligned packed double
    Op(
        'movupd',
        Enc(opnds=['xmm', 'xmm/m128'], prefix=[0x66], opcode=[0x0F, 0x10]),
        Enc(opnds=['xmm/m128', 'xmm'], prefix=[0x66], opcode=[0x0F, 0x11]),
    ),

    # Move with zero extension (unsigned)
    Op(
        'movzx',
        Enc(opnds=['r16', 'r/m8'], opcode=[0x0F, 0xB6]),
        Enc(opnds=['r32', 'r/m8'], opcode=[0x0F, 0xB6]),
        Enc(opnds=['r64', 'r/m8'], opcode=[0x0F, 0xB6]),
        Enc(opnds=['r32', 'r/m16'], opcode=[0x0F, 0xB7]),
        Enc(opnds=['r64', 'r/m16'], opcode=[0x0F, 0xB7]),
    ),

    # Signed integer multiply
    Op(
        'mul',
        Enc(opnds=['r/m8'], opcode=[0xF6], opExt=4),
        Enc(opnds=['r/m16'], opcode=[0xF7], opExt=4),
        Enc(opnds=['r/m32'], opcode=[0xF7], opExt=4),
        Enc(opnds=['r/m64'], opcode=[0xF7], opExt=4),
    ),

    # Multiply scalar double
    Op(
        'mulsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x59]),
    ),

    # Negation (multiplication by -1)
    Op(
        'neg',
        Enc(opnds=['r/m8'], opcode=[0xF6], opExt=3),
        Enc(opnds=['r/m16'], opcode=[0xF7], opExt=3),
        Enc(opnds=['r/m32'], opcode=[0xF7], opExt=3),
        Enc(opnds=['r/m64'], opcode=[0xF7], opExt=3),
    ),

    # No operation
    Op(
        'nop',
        Enc(opnds=[], opcode=[0x90])
    ),

    # Bitwise negation
    Op(
        'not',
         Enc(opnds=['r/m8'], opcode=[0xF6], opExt=2),
         Enc(opnds=['r/m16'], opcode=[0xF7], opExt=2),
         Enc(opnds=['r/m32'], opcode=[0xF7], opExt=2),
         Enc(opnds=['r/m64'], opcode=[0xF7], opExt=2),
    ),

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

    # Pop off the stack
    Op(
        'pop',
        Enc(opnds=['r/m16'], opcode=[0x8F], opExt=0),
        Enc(opnds=['r/m64'], opcode=[0x8F], opExt=0, rexW=False),
        Enc(opnds=['r16'], opcode=[0x58]),
        Enc(opnds=['r64'], opcode=[0x58], rexW=False),
    ),

    # Pop into the flags register
    Op(
        'popf',
        Enc(opnds=[], opcode=[0x9D], opndSize=16)
    ),
    Op(
        'popfq',
        Enc(opnds=[], opcode=[0x9D], opndSize=64)
    ),

    # Push on the stack
    Op(
        'push',
        Enc(opnds=['r/m16'], opcode=[0xFF], opExt=6),
        Enc(opnds=['r/m64'], opcode=[0xFF], opExt=6, rexW=False),
        Enc(opnds=['r16'], opcode=[0x50]),
        Enc(opnds=['r64'], opcode=[0x50], rexW=False),
        Enc(opnds=['imm8'], opcode=[0x6A]),
        Enc(opnds=['imm32'], opcode=[0x68]),
    ),

    # Push the flags register
    Op(
        'pushf',
        Enc(opnds=[], opcode=[0x9C], opndSize=16)
    ),
    Op(
        'pushfq',
        Enc(opnds=[], opcode=[0x9C], opndSize=64)
    ),

    # Read performance monitoring counters
    Op(
        'rdpmc',
        Enc(opnds=[], opcode=[0x0F, 0x33]),
    ),

    # Read time stamp counter
    Op(
        'rdtsc',
        Enc(opnds=[], opcode=[0x0F, 0x31]),
    ),

    # Return
    Op(
        'ret',
        Enc(opnds=[], opcode=[0xC3]),
        # Return and pop bytes off the stack
        Enc(opnds=['imm16'], opcode=[0xC2], szPref=False),
    ),

    # Round scalar double
    # The rounding mode is determined by the immediate
    Op(
        'roundsd',
        Enc(opnds=['xmm', 'xmm/m64', 'imm8'], prefix=[0x66], opcode=[0x0F, 0x3A, 0x0B], rexW=False),
    ),

    # Shift arithmetic left
    Op(
        'sal',
        Enc(opnds=['r/m8', 1], opcode=[0xD0], opExt=4),
        Enc(opnds=['r/m8', 'cl'], opcode=[0xD2], opExt=4),
        Enc(opnds=['r/m8', 'imm8'], opcode=[0xC0], opExt=4),
        Enc(opnds=['r/m16', 1], opcode=[0xD1], opExt=4),
        Enc(opnds=['r/m16', 'cl'], opcode=[0xD3], opExt=4),
        Enc(opnds=['r/m16', 'imm8'], opcode=[0xC1], opExt=4),
        Enc(opnds=['r/m32', 1], opcode=[0xD1], opExt=4),
        Enc(opnds=['r/m32', 'cl'], opcode=[0xD3], opExt=4),
        Enc(opnds=['r/m32', 'imm8'], opcode=[0xC1], opExt=4),
        Enc(opnds=['r/m64', 1], opcode=[0xD1], opExt=4),
        Enc(opnds=['r/m64', 'cl'], opcode=[0xD3], opExt=4),
        Enc(opnds= ['r/m64', 'imm8'], opcode=[0xC1], opExt=4),
    ),

    # Shift arithmetic right (signed)
    Op(
        'sar',
        Enc(opnds=['r/m8', 1], opcode=[0xD0], opExt=7),
        Enc(opnds=['r/m8', 'cl'], opcode=[0xD2], opExt=7),
        Enc(opnds=['r/m8', 'imm8'], opcode=[0xC0], opExt=7),
        Enc(opnds=['r/m16', 1], opcode=[0xD1], opExt=7),
        Enc(opnds=['r/m16', 'cl'], opcode=[0xD3], opExt=7),
        Enc(opnds=['r/m16', 'imm8'], opcode=[0xC1], opExt=7),
        Enc(opnds=['r/m32', 1], opcode=[0xD1], opExt=7),
        Enc(opnds=['r/m32', 'cl'], opcode=[0xD3], opExt=7),
        Enc(opnds=['r/m32', 'imm8'], opcode=[0xC1], opExt=7),
        Enc(opnds=['r/m64', 1], opcode=[0xD1], opExt=7),
        Enc(opnds=['r/m64', 'cl'], opcode=[0xD3], opExt=7),
        Enc(opnds= ['r/m64', 'imm8'], opcode=[0xC1], opExt=7),
    ),

    # Shift logical left
    Op(
        'shl',
        Enc(opnds=['r/m8', 1], opcode=[0xD0], opExt=4),
        Enc(opnds=['r/m8', 'cl'], opcode=[0xD2], opExt=4),
        Enc(opnds=['r/m8', 'imm8'], opcode=[0xC0], opExt=4),
        Enc(opnds=['r/m16', 1], opcode=[0xD1], opExt=4),
        Enc(opnds=['r/m16', 'cl'], opcode=[0xD3], opExt=4),
        Enc(opnds=['r/m16', 'imm8'], opcode=[0xC1], opExt=4),
        Enc(opnds=['r/m32', 1], opcode=[0xD1], opExt=4),
        Enc(opnds=['r/m32', 'cl'], opcode=[0xD3], opExt=4),
        Enc(opnds=['r/m32', 'imm8'], opcode=[0xC1], opExt=4),
        Enc(opnds=['r/m64', 1], opcode=[0xD1], opExt=4),
        Enc(opnds=['r/m64', 'cl'], opcode=[0xD3], opExt=4),
        Enc(opnds= ['r/m64', 'imm8'], opcode=[0xC1], opExt=4),
    ),

    # Shift logical right (unsigned)
    Op(
        'shr',
        Enc(opnds=['r/m8', 1], opcode=[0xD0], opExt=5),
        Enc(opnds=['r/m8', 'cl'], opcode=[0xD2], opExt=5),
        Enc(opnds=['r/m8', 'imm8'], opcode=[0xC0], opExt=5),
        Enc(opnds=['r/m16', 1], opcode=[0xD1], opExt=5),
        Enc(opnds=['r/m16', 'cl'], opcode=[0xD3], opExt=5),
        Enc(opnds=['r/m16', 'imm8'], opcode=[0xC1], opExt=5),
        Enc(opnds=['r/m32', 1], opcode=[0xD1], opExt=5),
        Enc(opnds=['r/m32', 'cl'], opcode=[0xD3], opExt=5),
        Enc(opnds=['r/m32', 'imm8'], opcode=[0xC1], opExt=5),
        Enc(opnds=['r/m64', 1], opcode=[0xD1], opExt=5),
        Enc(opnds=['r/m64', 'cl'], opcode=[0xD3], opExt=5),
        Enc(opnds= ['r/m64', 'imm8'], opcode=[0xC1], opExt=5),
    ),

    # Square root of scalar doubles (SSE2)
    Op(
        'sqrtsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x51], rexW=False),
    ),

    # Integer subtraction
    Op(
        'sub',
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
    ),

    # Subtract scalar double
    Op(
        'subsd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0xF2], opcode=[0x0F, 0x5C]),
    ),

    # Logical AND compare
    Op(
        'test',
        Enc(opnds=['al', 'imm8'], opcode=[0xA8]),
        Enc(opnds=['ax', 'imm16'], opcode=[0xA9]),
        Enc(opnds=['eax', 'imm32'], opcode=[0xA9]),           
        Enc(opnds=['rax', 'imm32'], opcode=[0xA9]),
        Enc(opnds=['r/m8', 'imm8'], opcode=[0xF6], opExt=0),
        Enc(opnds=['r/m16', 'imm16'], opcode=[0xF7], opExt=0),
        Enc(opnds=['r/m32', 'imm32'], opcode=[0xF7], opExt=0),
        Enc(opnds=['r/m64', 'imm32'], opcode=[0xF7], opExt=0),
        Enc(opnds=['r/m8', 'r8'], opcode=[0x84]),
        Enc(opnds=['r/m16', 'r16'], opcode=[0x85]),
        Enc(opnds=['r/m32', 'r32'], opcode=[0x85]),
        Enc(opnds=['r/m64', 'r64'], opcode=[0x85]),
    ),

    # Unordered compare scalar double
    Op(
        'ucomisd',
        Enc(opnds=['xmm', 'xmm/m64'], prefix=[0x66], opcode=[0x0F, 0x2E], rexW=False),
    ),

    # Exchange
    # The ax/eax/rax + rXX variants use the opcode reg field
    Op(
        'xchg',
        Enc(opnds=['ax', 'r16'], opcode=[0x90]),
        Enc(opnds=['r16', 'ax'], opcode=[0x90]),
        Enc(opnds=['eax', 'r32'], opcode=[0x90]),
        Enc(opnds=['r32', 'eax'], opcode=[0x90]),
        Enc(opnds=['rax', 'r64'], opcode=[0x90]),
        Enc(opnds=['r64', 'eax'], opcode=[0x90]),
        Enc(opnds=['r/m8', 'r8'], opcode=[0x86]),
        Enc(opnds=['r8', 'r/m8'], opcode=[0x86]),
        Enc(opnds=['r/m16', 'r16'], opcode=[0x87]),
        Enc(opnds=['r/m32', 'r32'], opcode=[0x87]),
        Enc(opnds=['r/m64', 'r64'], opcode=[0x87]),
        Enc(opnds=['r16', 'r/m16'], opcode=[0x87]),
        Enc(opnds=['r32', 'r/m32'], opcode=[0x87]),
        Enc(opnds=['r64', 'r/m64'], opcode=[0x87]),
    ),

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
]

# Get the size in bits of an operand designation
def opndSize(opnd):

    if opnd == 'm':
        return 0
    if opnd == 1:
        return 8
    if opnd == 'xmm':
        return 128

    if opnd.endswith('128'):
        return 128

    if opnd.endswith('64') or opnd == 'rax':
        return 64

    if opnd.endswith('32') or opnd == 'eax':
        return 32

    if opnd.endswith('16') or opnd == 'ax':
        return 16

    if opnd.endswith('8') or opnd == 'al' or opnd == 'cl':
        return 8

    raise Exception("unknown operand " + opnd)


# Get the encoding flags for an operand
def opndFlags(opnd):

    if opnd==1:
        return 'X86Enc.CST1'
    if opnd=='al' or opnd=='ax' or opnd=='eax' or opnd=='rax':
        return 'X86Enc.REGA'
    if opnd=='cl':
        return 'X86Enc.REGC'

    if opnd.startswith('imm'):
        return 'X86Enc.IMM'
    if opnd.startswith('moffs'):
        return 'X86Enc.MOFFS'
    if opnd.startswith('rel'):
        return 'X86Enc.REL'

    if opnd.startswith('r/m'):
        return 'X86Enc.R_OR_M'
    if opnd.startswith('xmm/m'):
        return 'X86Enc.XMM_OR_M'

    if opnd.startswith('r'):
        return 'X86Enc.R'
    if opnd.startswith('xmm'):
        return 'X86Enc.XMM'
    if opnd.startswith('m'):
        return 'X86Enc.M'

    raise Exception("unknown operand " + opnd)

# For each opcode in the instruction table
for op in instrTable:

    # For each possible encoding of this opcode
    for enc in op.encs:

        if len(enc.opcode) == 0 or len(enc.opcode) > 3:
            raise Exception('invalid opcode length')

        if enc.opExt != None and not (enc.opExt >= 0 and enc.opExt <= 7):
            raise Exception('invalid opcode extension')

        # Try to infer the operand size from operands if necessary
        if enc.opndSize == None:
            if len(enc.opnds) > 1 and enc.opnds[0] == 'xmm':
                enc.opndSize = opndSize(enc.opnds[1])
            elif len(enc.opnds) > 0:
                enc.opndSize = opndSize(enc.opnds[0])
            else:
                enc.opndSize = 32

        # Determine necessity of szPref, rexW
        enc.szPref = (enc.szPref == None and enc.opndSize == 16)
        enc.rexW   = (enc.rexW == None and enc.opndSize == 64)

    # Sort encodings by decreasing operand size
    op.encs.sort(key=lambda e: -e.opndSize)

# Open the output file for writing
DFile = open(D_OUT_FILE, 'w')

comment =                                                               \
'//\n' +                                                                \
'// Code auto-generated from "' + sys.argv[0] + '". Do not modify.\n' + \
'//\n' +                                                                \
'\n'

DFile.write(comment)

DFile.write('module jit.encodings;\n');
DFile.write('import jit.x86;\n');
DFile.write('\n');

# For each opcode in the instruction table
for op in instrTable:

    encStrs = []

    # For each possible encoding of this opcode
    for enc in op.encs:

        encStr = ''

        # Add the operand types
        encStr += '[' + ', '.join(map(opndFlags, enc.opnds)) + '], '

        # Add the operand sizes
        encStr += '[' + ', '.join(map(str, map(opndSize, enc.opnds))) + '], '

        # Add the prefix and opcode
        encStr += '[' + ', '.join(map(str, enc.prefix)) + '], '
        encStr += '[' + ', '.join(map(str, enc.opcode)) + '], '

        if enc.opExt == None:
            encStr += '0xFF, '
        else:
            encStr += str(enc.opExt) + ', ' 

        encStr += str(enc.opndSize) + ', '

        if enc.szPref:
            encStr += 'true, '
        else:
            encStr += 'false, '

        if enc.rexW:
            encStr += 'true'
        else:
            encStr += 'false'

        # Add the encoding string to the list
        encStrs = encStrs + [encStr]

    DFile.write('immutable X86Op %s = {\n' % (op.mnem))
    DFile.write('    "%s",\n' % (op.mnem))
    DFile.write('    [\n')
    DFile.write(',\n'.join(map(lambda s: '        { %s }' % (s), encStrs)) + '\n')
    DFile.write('    ]\n')
    DFile.write('};\n')

    # Immutable opcode pointer
    DFile.write('immutable X86OpPtr %s = &%s;\n' % (op.mnem.upper(), op.mnem));

DFile.close()

