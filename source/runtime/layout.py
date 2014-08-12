import sys
import string
from copy import deepcopy

D_OUT_FILE = 'runtime/layout.d'
JS_OUT_FILE = 'runtime/layout.js'

JS_DEF_PREFIX = '$rt_'

# Type sizes in bytes
typeSize = {
    'uint8':1,
    'uint16':2,
    'uint32':4,
    'uint64':8,
    'int8':1,
    'int16':2,
    'int32':4,
    'int64':8,
    'float64':8,
    'rawptr':8,
    'refptr':8,
    'funptr':8,
    'shapeptr':8,
}

typeShortName = {
    'uint8':'u8',
    'uint16':'u16',
    'uint32':'u32',
    'uint64':'u64',
    'int8':'i8',
    'int16':'i16',
    'int32':'i32',
    'int64':'i64',
    'float64':'f64',
    'rawptr':'rawptr',
    'refptr':'refptr',
    'funptr':'funptr',
    'shapeptr':'shapeptr',
}

# Layout declarations
layouts = [

    # String layout
    {
        'name':'str',
        'tag':'string',
        'fields':
        [
            # String length
            { 'name': "len" , 'type':'uint32' },

            # Hash code
            { 'name': 'hash', 'type':'uint32' },

            # UTF-16 character data
            { 'name': 'data', 'type':'uint16', 'szField':'len' }
        ]
    },

    # String table layout (for hash consing)
    {
        'name':'strtbl',
        'tag':'refptr',
        'fields': 
        [
            # Capacity, total number of slots
            { 'name':'cap', 'type':'uint32' },

            # Number of strings
            { 'name':'num_strs', 'type':'uint32', 'init':"0" },

            # Array of strings
            { 'name':'str', 'type':'refptr', 'szField':'cap', 'init':'null' },
        ]
    },

    # Object layout
    {
        'name':'obj',
        'tag':'object',
        'fields':
        [
            # Capacity, number of property slots
            { 'name':"cap" , 'type':"uint32" },

            # Shape pointer
            { 'name':"shape", 'type':"shapeptr" },

            # Property words
            { 'name':"word", 'type':"uint64", 'szField':"cap", 'tpField':'type' },

            # Property types
            { 'name':"type", 'type':"uint8", 'szField':"cap" }
        ]
    },

    # Function/closure layout (extends object)
    {
        'name':'clos',
        'tag':'closure',
        'extends':'obj',
        'fields':
        [
            # Note: the function pointer is stored in the first object slot

            # Number of closure cells
            { 'name':"num_cells" , 'type':"uint32" },

            # Closure cell pointers
            { 'name':"cell", 'type':"refptr", 'szField':"num_cells", 'init':"null"  },
        ]
    },

    # Closure cell
    {
        'name':'cell',
        'tag':'refptr',
        'fields':
        [
            # Value word
            { 'name':"word", 'type':"uint64", 'init':'undef_word', 'tpField':'type' },

            # Value type
            { 'name':"type", 'type':"uint8", 'init':'undef_type' },
        ]
    },

    # Array layout (extends object)
    {
        'name':'arr',
        'tag':'array',
        'extends':'obj',
        'fields':
        [
            # Array table reference
            { 'name':"tbl", 'type':"refptr" },

            # Number of elements contained
            { 'name':"len", 'type':"uint32" },
        ]
    },

    # Array table layout (contains array elements)
    {
        'name':'arrtbl',
        'tag':'refptr',
        'fields':
        [
            # Array capacity
            { 'name':"cap" , 'type':"uint32" },

            # Element words
            { 'name':"word", 'type':"uint64", 'init':'undef_word', 'szField':"cap", 'tpField':'type' },

            # Element types
            { 'name':"type", 'type':"uint8", 'init':'undef_type', 'szField':"cap" },
        ]
    },
]

# Indent a text string
def indent(input, indentStr = '    '):

    output = ''

    if len(input) > 0:
        output += '    '

    for i in range(len(input)):

        ch = input[i]
        output += ch

        if ch == '\n' and i != len(input)-1:
            output += indentStr

    return output

def sepList(lst, sep = ', '):
    if len(lst) == 0:
        return ''
    return reduce(lambda x,y: x + sep + y, lst)

class Var:

    def __init__(self, type, name):
        self.type = type
        self.name = name

    def genJS(self):
        return self.name

    def genD(self):
        return self.name

    def genDeclD(self):
        return self.type + ' ' + self.name

class Cst:

    def __init__(self, val):
        self.val = val

    def genJS(self):

        if self.val == 'undef_word':
            return '$ir_get_word($undef)'
        if self.val == 'undef_type':
            return '$ir_get_type($undef)'

        return str(self.val)

    def genD(self):

        if self.val == 'undef_word':
            return 'UNDEF.word.uint8Val'
        if self.val == 'undef_type':
            return 'Type.CONST'

        return str(self.val)

class ConstDef:

    def __init__(self, type, name, val):
        self.type = type
        self.name = name
        self.val = val

    def genJS(self):
        return 'var ' + JS_DEF_PREFIX + self.name + ' = ' + str(self.val) + ';'

    def genD(self):
        return 'const ' + self.type + ' ' + self.name + ' = ' + str(self.val) + ';'

class Function:

    def __init__(self, type, name, params):
        self.type = type
        self.name = name
        self.params = params
        self.stmts = []

    def genJS(self):
        out = ''
        out += 'function ' + JS_DEF_PREFIX + self.name + '('
        params = self.params
        if len(params) >= 1 and params[0].name == 'vm':
            params = params[1:]
        out += sepList(map(lambda v:v.genJS(), params))
        out += ')\n'
        out += '{'
        stmts = ''
        for stmt in self.stmts:
            stmts += '\n' + stmt.genJS()
        out += indent(stmts)
        out += '\n}'
        return out

    def genD(self):
        out = ''
        out += 'extern (C) ' + self.type + ' ' + self.name + '('
        out += sepList(map(lambda v:v.genDeclD(), self.params))
        out += ')\n'
        out += '{'
        stmts = ''
        for stmt in self.stmts:
            stmts += '\n' + stmt.genD()
        out += indent(stmts)
        out += '\n}'
        return out

class RetStmt:

    def __init__(self, expr = None):
        self.expr = expr

    def genJS(self):
        if self.expr:
            return 'return ' + self.expr.genJS() + ';'
        else:
            return 'return;'

    def genD(self):
        if self.expr:
            return 'return ' + self.expr.genD() + ';'
        else:
            return 'return;'

class ExprStmt:

    def __init__(self, expr):
        self.expr = expr

    def genJS(self):
        return self.expr.genJS() + ';'

    def genD(self):
        return self.expr.genD() + ';'

class DeclStmt:

    def __init__(self, var, val):
        self.type = type
        self.var = var
        self.val = val

    def genJS(self):
        return 'var ' + self.var.genJS() + ' = ' + self.val.genJS() + ';'

    def genD(self):
        return 'auto ' + self.var.genD() + ' = ' + self.val.genD() + ';'

class IfStmt:

    def __init__(self, expr, trueStmts, falseStmts = None):
        self.expr = expr
        self.trueStmts = trueStmts
        self.falseStmts = falseStmts

    def genJS(self):
        out = 'if (' + self.expr.genJS() + ')\n'
        out += '{'
        stmts = ''
        for stmt in self.trueStmts:
            stmts += '\n' + stmt.genJS()
        out += indent(stmts)
        out += '\n}'
        if self.falseStmts:
            out += 'else'
            out += '{'
            stmts = ''
            for stmt in self.falseStmts:
                stmts += '\n' + stmt.genJS()
            out += indent(stmts)
            out += '\n}'
        return out

    def genD(self):
        out = 'if (' + self.expr.genD() + ')\n'
        out += '{'
        stmts = ''
        for stmt in self.trueStmts:
            stmts += '\n' + stmt.genD()
        out += indent(stmts)
        out += '\n}'
        if self.falseStmts:
            out += 'else'
            out += '{'
            stmts = ''
            for stmt in self.falseStmts:
                stmts += '\n' + stmt.genD()
            out += indent(stmts)
            out += '\n}'
        return out

class AddExpr:

    def __init__(self, lExpr, rExpr):
        self.lExpr = lExpr
        self.rExpr = rExpr

    def genJS(self):
        return '$ir_add_i32(' + self.lExpr.genJS() + ', ' + self.rExpr.genJS() + ')'

    def genD(self):
        return '(' + self.lExpr.genD() + ' + ' + self.rExpr.genD() + ')'

class MulExpr:

    def __init__(self, lExpr, rExpr):
        self.lExpr = lExpr
        self.rExpr = rExpr

    def genJS(self):
        return '$ir_mul_i32(' + self.lExpr.genJS() + ', ' + self.rExpr.genJS() + ')'

    def genD(self):
        return '(' + self.lExpr.genD() + ' * ' + self.rExpr.genD() + ')'

class AndExpr:

    def __init__(self, lExpr, rExpr):
        self.lExpr = lExpr
        self.rExpr = rExpr

    def genJS(self):
        return '$ir_and_i32(' + self.lExpr.genJS() + ', ' + self.rExpr.genJS() + ')'

    def genD(self):
        return '(' + self.lExpr.genD() + ' & ' + self.rExpr.genD() + ')'

class EqExpr:

    def __init__(self, lExpr, rExpr):
        self.lExpr = lExpr
        self.rExpr = rExpr

    def genJS(self):
        return '$ir_eq_i32(' + self.lExpr.genJS() + ', ' + self.rExpr.genJS() + ')'

    def genD(self):
        return '(' + self.lExpr.genD() + ' == ' + self.rExpr.genD() + ')'

class LoadExpr:

    def __init__(self, type, ptr, ofs):
        self.type = type
        self.ptr = ptr
        self.ofs = ofs

    def genJS(self):
        return '$ir_load_' + typeShortName[self.type] + '(' + self.ptr.genJS() + ', ' + self.ofs.genJS() + ')'

    def genD(self):
        return '*cast(' + self.type + '*)(' + self.ptr.genD() + ' + ' + self.ofs.genD() + ')'

class StoreExpr:

    def __init__(self, type, ptr, ofs, val):
        self.type = type
        self.ptr = ptr
        self.ofs = ofs
        self.val = val

    def genJS(self):
        return '$ir_store_' + typeShortName[self.type] + '(' + self.ptr.genJS() + ', ' + self.ofs.genJS() + ', ' + self.val.genJS() + ')'

    def genD(self):
        return '*cast(' + self.type + '*)(' + self.ptr.genD() + ' + ' + self.ofs.genD() + ') = ' + self.val.genD()

class AllocExpr:

    def __init__(self, size, tag):
        self.size = size
        self.tag = tag

    def genJS(self):
        return '$ir_alloc_' + self.tag + '(' + self.size.genJS() + ')'

    def genD(self):
        return 'vm.heapAlloc(' + self.size.genD() + ')'

class CallExpr:

    def __init__(self, fName, args):
        self.fName = fName
        self.args = args

    def genJS(self):
        out = JS_DEF_PREFIX + self.fName + '('
        out += sepList(map(lambda v:v.genJS(), self.args))
        out += ')'
        return out

    def genD(self):
        out = self.fName + '('
        out += sepList(map(lambda v:v.genD(), self.args))
        out += ')'
        return out

class ForLoop:

    def __init__(self, loopVar, endVar, stmts):
        self.loopVar = loopVar
        self.endVar = endVar
        self.stmts = stmts

    def genJS(self):
        loopV = self.loopVar.genJS()
        endV = self.endVar.genJS()
        out = ''
        out += 'for (var %s = 0; $ir_lt_i32(%s, %s); %s = $ir_add_i32(%s, 1))\n' % (loopV, loopV, endV, loopV, loopV)
        out += '{'
        stmts = ''
        for stmt in self.stmts:
            stmts += '\n' + stmt.genJS()
        out += indent(stmts)
        out += '\n}'
        return out

    def genD(self):
        out = ''
        out += 'for (' + self.loopVar.type + ' ' + self.loopVar.genD() + ' = 0; ' + self.loopVar.genD() + ' < '
        out += self.endVar.genD() + '; ++' + self.loopVar.genD() + ')\n'
        out += '{'
        stmts = ''
        for stmt in self.stmts:
            stmts += '\n' + stmt.genD()
        out += indent(stmts)
        out += '\n}'
        return out

# Perform basic validation
for layout in layouts:

    # Check for duplicate field names
    for fieldIdx, field in enumerate(layout['fields']):
        for prev in layout['fields'][:fieldIdx]:
            if prev['name'] == field['name']:
                raise Exception('duplicate field name ' + field['name'])


# Perform layout extensions
for layoutIdx, layout in enumerate(layouts):

    # If this layout does not extend another, skip it
    if 'extends' not in layout:
        continue

    # Find the parent layout
    parent = None
    for prev in layouts[:layoutIdx]:
        if prev['name'] == layout['extends']:
            parent = prev
            break
    if parent == None:
        raise Exception("parent not found")

    # Add the parent fields (except type) to this layout
    fieldCopies = []
    for field in parent['fields']:
        fieldCopies += [deepcopy(field)]
    layout['fields'] = fieldCopies + layout['fields']

# Assign layout ids, add the next and header fields
nextLayoutId = 0
for layout in layouts:

    layoutId = nextLayoutId
    layout['typeId'] = layoutId
    nextLayoutId += 1

    nextField = [{ 'name':'next', 'type':'refptr', 'init':"null" }]
    typeField = [{ 'name':'header', 'type':'uint32', 'init':str(layoutId) }]
    layout['fields'] = nextField + typeField + layout['fields']

# Find/resolve size fields
for layout in layouts:

    # List of size fields for this layout
    layout['szFields'] = []

    for fieldIdx, field in enumerate(layout['fields']):

        # If this field has no size field, skip it
        if 'szField' not in field:
            continue

        # Find the size field and add it to the size field list
        szName = field['szField']
        field['szField'] = None
        for prev in layout['fields'][:fieldIdx]:
            if prev['name'] == szName:
                field['szField'] = prev
                # Add the field to the size field list
                if prev not in layout['szFields']:
                    layout['szFields'] += [prev]
                break

        # If the size field was not found, raise an exception
        if field['szField'] == None:
            raise Exception('size field "%s" of "%s" not found' % (szName, field['name']))

# Find/resolve word type fields
for layout in layouts:

    for field in layout['fields']:

        # If this field has no type field, skip it
        if 'tpField' not in field:
            continue

        # Find the type field
        tpName = field['tpField']
        field['tpField'] = None
        for prev in layout['fields']:
            if prev['name'] == tpName:
                field['tpField'] = prev

        # If the type field was not found, raise an exception
        if field['tpField'] == None:
            raise Exception('type field "%s" of "%s" not found' % (tpName, field['name']))

# Compute field alignment requirements
for layout in layouts:

    #print('');
    #print(layout['name'])

    # Current offset since last dynamic alignment
    curOfs = 0

    # For each field of this layout
    for fieldIdx, field in enumerate(layout['fields']):

        # Field type size
        fSize = typeSize[field['type']]

        # If the previous field was dynamically sized and of smaller type size
        if fieldIdx > 0 and 'szField' in layout['fields'][fieldIdx-1] and \
           typeSize[layout['fields'][fieldIdx-1]['type']] < fSize:

            # This field will be dynamically aligned
            field['dynAlign'] = True
            field['alignPad'] = 0

            # Reset the current offset
            curOfs = 0

        else:

            # Compute the padding required for alignment
            alignRem = curOfs % fSize
            if alignRem != 0:
                alignPad = fSize - alignRem
            else:
                alignPad = 0

            field['dynAlign'] = False
            field['alignPad'] = alignPad

            # Update the current offset
            curOfs += alignPad + fSize

        #print(field['name'])
        #print('  fSize: ' + str(fSize))
        #print('  align: ' + str(field['alignPad']))

# List of generated functions and declarations
decls = []

# For each layout
for layout in layouts:

    ofsPref = layout['name'] + '_ofs_';
    setPref = layout['name'] + '_set_';
    getPref = layout['name'] + '_get_';

    # Define the layout type constant
    decls += [ConstDef(
        'uint32', 
        'LAYOUT_' + layout['name'].upper(), 
        layout['typeId']
    )]

    # Generate offset computation functions
    for fieldIdx, field in enumerate(layout['fields']):

        fun = Function('uint32', ofsPref + field['name'], [Var('refptr', 'o')])
        if 'szField' in field:
            fun.params += [Var('uint32', 'i')]

        sumExpr = Cst(0)

        for prev in layout['fields'][:fieldIdx]:

            # If this field must be dymamically aligned
            if prev['dynAlign']:
                ptrSize = typeSize['rawptr']
                sumExpr = AndExpr(AddExpr(sumExpr, Cst(ptrSize - 1)), Cst(-ptrSize))
            elif prev['alignPad'] > 0:
                sumExpr = AddExpr(sumExpr, Cst(prev['alignPad']))

            # Compute the previous field size
            termExpr = Cst(typeSize[prev['type']])
            if 'szField' in prev:
                szCall = CallExpr(getPref + prev['szField']['name'], [fun.params[0]])
                termExpr = MulExpr(termExpr, szCall)
            sumExpr = AddExpr(sumExpr, termExpr)

        # If this field must be dymamically aligned
        if field['dynAlign']:
            ptrSize = typeSize['rawptr']
            sumExpr = AndExpr(AddExpr(sumExpr, Cst(ptrSize - 1)), Cst(-ptrSize))
        elif field['alignPad'] > 0:
            sumExpr = AddExpr(sumExpr, Cst(field['alignPad']))

        # Compute the index into the last field
        if 'szField' in field:
            fieldSize = Cst(typeSize[field['type']])
            sumExpr = AddExpr(sumExpr, MulExpr(fieldSize , fun.params[1]))

        fun.stmts += [RetStmt(sumExpr)]

        decls += [fun]

    # Generate getter methods
    for fieldIdx, field in enumerate(layout['fields']):

        fun = Function(field['type'], getPref + field['name'], [Var('refptr', 'o')])
        if 'szField' in field:
            fun.params += [Var('uint32', 'i')]

        ofsCall = CallExpr(ofsPref + field['name'], [fun.params[0]])
        if 'szField' in field:
            ofsCall.args += [fun.params[1]]

        fun.stmts += [RetStmt(LoadExpr(field['type'], fun.params[0], ofsCall))]

        decls += [fun]

    # Generate setter methods
    for fieldIdx, field in enumerate(layout['fields']):

        fun = Function('void', setPref + field['name'], [Var('refptr', 'o')])
        if 'szField' in field:
            fun.params += [Var('uint32', 'i')]
        fun.params += [Var(field['type'], 'v')]

        ofsCall = CallExpr(ofsPref + field['name'], [fun.params[0]])
        if 'szField' in field:
            ofsCall.args += [fun.params[1]]

        fun.stmts += [ExprStmt(StoreExpr(field['type'], fun.params[0], ofsCall, fun.params[-1]))]

        decls += [fun]

    # Generate the layout size computation function
    fun = Function('uint32', layout['name'] + '_comp_size', [])
    szVars = {}
    for szField in layout['szFields']:
        szVar = Var(szField['type'], szField['name'])
        szVars[szVar.name] = szVar
        fun.params += [szVar]

    szSum = Cst(0)

    for field in layout['fields']:

        # If this field must be dymamically aligned
        if field['dynAlign']:
            ptrSize = typeSize['rawptr']
            szSum = AndExpr(AddExpr(szSum, Cst(ptrSize - 1)), Cst(-ptrSize))
        elif field['alignPad'] > 0:
            szSum = AddExpr(szSum, Cst(field['alignPad']))

        szTerm = Cst(typeSize[field['type']])
        if 'szField' in field:
            szTerm = MulExpr(szTerm, szVars[field['szField']['name']])
        szSum = AddExpr(szSum, szTerm)

    fun.stmts += [RetStmt(szSum)]
    decls += [fun]

    # Generate the sizeof method
    fun = Function('uint32', layout['name'] + '_sizeof', [Var('refptr', 'o')])

    callExpr = CallExpr(layout['name'] + '_comp_size', [])
    for szField in layout['szFields']:
        getCall = CallExpr(getPref + szField['name'], [fun.params[0]])
        callExpr.args += [getCall]
    fun.stmts += [RetStmt(callExpr)]

    decls += [fun]

    # Generate the allocation function
    fun = Function('refptr', layout['name'] + '_alloc', [Var('VM', 'vm')])
    szVars = {}
    for szField in layout['szFields']:
        szVar = Var(szField['type'], szField['name'])
        szVars[szVar.name] = szVar
        fun.params += [szVar]

    szCall = CallExpr(layout['name'] + '_comp_size', [])
    for szField in layout['szFields']:
        szCall.args += [szVars[szField['name']]]
    objVar = Var('refptr', 'o')
    fun.stmts += [DeclStmt(objVar, AllocExpr(szCall, layout['tag']))]

    for szField in layout['szFields']:
        setCall = CallExpr(setPref + szField['name'], [objVar, szVars[szField['name']]])
        fun.stmts += [ExprStmt(setCall)]

    for field in layout['fields']:

        if 'init' not in field:
            continue

        initVal = field['init']

        # Some init values map to zero and do not need to be written
        if initVal == '0':
            continue
        if initVal == 'null':
            continue
        if initVal == 'undef_type':
            continue

        if 'szField' in field:
            loopVar = Var('uint32', 'i')
            szVar = szVars[field['szField']['name']]
            setCall = CallExpr(setPref + field['name'], [objVar, loopVar, Cst(field['init'])])
            fun.stmts += [ForLoop(loopVar, szVar, [ExprStmt(setCall)])]
        else:
            setCall = CallExpr(setPref + field['name'], [objVar, Cst(field['init'])])
            fun.stmts += [ExprStmt(setCall)]

    fun.stmts += [RetStmt(objVar)]
    decls += [fun]

    # Generate the GC visit function
    fun = Function('void', layout['name'] + '_visit_gc', [Var('VM', 'vm'), Var('refptr', 'o')])
    vmVar = fun.params[0]
    objVar = fun.params[1]

    for field in layout['fields']:

        # If this is not a heap reference field, skip it
        if field['type'] != 'refptr' and (not 'tpField' in field):
            continue

        # If this is a variable-size field
        if 'szField' in field:

            szVar = Var('uint32', field['szField']['name'])
            szStmt = DeclStmt(szVar, CallExpr(getPref + field['szField']['name'], [objVar]))
            fun.stmts += [szStmt]

            loopVar = Var('uint32', 'i')

            # If this is a word/type pair
            if 'tpField' in field:
                getWCall = CallExpr(getPref + field['name'], [objVar, loopVar])
                getTCall = CallExpr(getPref + field['tpField']['name'], [objVar, loopVar])
                fwdCall = CallExpr('gcForward', [vmVar, getWCall, getTCall])
            else:
                getCall = CallExpr(getPref + field['name'], [objVar, loopVar])
                fwdCall = CallExpr('gcForward', [vmVar, getCall])

            setCall = CallExpr(setPref + field['name'], [objVar, loopVar, fwdCall])
            fun.stmts += [ForLoop(loopVar, szVar, [ExprStmt(setCall)])]

        else:

            # If this is a word/type pair
            if 'tpField' in field:
                getWCall = CallExpr(getPref + field['name'], [objVar])
                getTCall = CallExpr(getPref + field['tpField']['name'], [objVar])
                fwdCall = CallExpr('gcForward', [vmVar, getWCall, getTCall])
            else:
                getCall = CallExpr(getPref + field['name'], [objVar])
                fwdCall = CallExpr('gcForward', [vmVar, getCall])

            setCall = CallExpr(setPref + field['name'], [objVar, fwdCall])
            fun.stmts += [ExprStmt(setCall)]

    decls += [fun]

# Generate the sizeof dispatch method
fun = Function('uint32', 'layout_sizeof', [Var('refptr', 'o')])

typeVar = Var('uint32', 't')
fun.stmts += [DeclStmt(typeVar, CallExpr('obj_get_header', [fun.params[0]]))]

for layout in layouts:
    cmpExpr = EqExpr(typeVar, Var('uint32', 'LAYOUT_' + layout['name'].upper()))
    retStmt = RetStmt(CallExpr(layout['name'] + '_sizeof', [fun.params[0]]))
    fun.stmts += [IfStmt(cmpExpr, [retStmt])]

fun.stmts += [ExprStmt(CallExpr('assert', [Cst('false'), Cst('"invalid layout in layout_sizeof"')]))]

decls += [fun]

# Generate the GC visit dispatch method
fun = Function('void', 'layout_visit_gc', [Var('VM', 'vm'), Var('refptr', 'o')])

typeVar = Var('uint32', 't')
fun.stmts += [DeclStmt(typeVar, CallExpr('obj_get_header', [fun.params[1]]))]

for layout in layouts:
    cmpExpr = EqExpr(typeVar, Var('uint32', 'LAYOUT_' + layout['name'].upper()))
    callStmt = ExprStmt(CallExpr(layout['name'] + '_visit_gc', [fun.params[0], fun.params[1]]))
    retStmt = RetStmt()
    fun.stmts += [IfStmt(cmpExpr, [callStmt, retStmt])]

fun.stmts += [ExprStmt(CallExpr('assert', [Cst('false'), Cst('"invalid layout in layout_visit_gc"')]))]

decls += [fun]

# Open the output files for writing
DFile = open(D_OUT_FILE, 'w')
JSFile = open(JS_OUT_FILE, 'w')

comment =                                                               \
'//\n' +                                                                \
'// Code auto-generated from "' + sys.argv[0] + '". Do not modify.\n' + \
'//\n\n'

DFile.write(comment)
JSFile.write(comment)

DFile.write('module runtime.layout;\n')
DFile.write('\n');
DFile.write('import runtime.vm;\n')
DFile.write('import runtime.gc;\n')
DFile.write('\n');

DFile.write('alias ubyte* funptr;\n');
DFile.write('alias ubyte* shapeptr;\n');
DFile.write('alias ubyte* rawptr;\n');
DFile.write('alias ubyte* refptr;\n');
DFile.write('alias byte   int8;\n');
DFile.write('alias short  int16;\n');
DFile.write('alias int    int32;\n');
DFile.write('alias long   int64;\n');
DFile.write('alias ubyte  uint8;\n');
DFile.write('alias ushort uint16;\n');
DFile.write('alias uint   uint32;\n');
DFile.write('alias ulong  uint64;\n');
DFile.write('alias double float64;\n');
DFile.write('\n');

# Output D and JS code, write to file
for decl in decls:

    JSFile.write(decl.genJS() + '\n\n')
    DFile.write(decl.genD() + '\n\n')

DFile.close()
JSFile.close()

