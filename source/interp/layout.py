import string
from copy import deepcopy

D_OUT_FILE = 'interp/layout.d'
JS_OUT_FILE = 'interp/layout.py'

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
}

# Layout declarations
layouts = [

    # String layout
    {
        'name':'str',
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
        'fields':
        [
            # Capacity, number of property slots
            { 'name':"cap" , 'type':"uint32" },

            # Class reference
            { 'name':"class", 'type':"refptr" },

            # Next object reference
            { 'name':"next", 'type':"refptr", 'init':"null" },

            # Prototype reference
            { 'name':"proto", 'type':"refptr" },

            # Property words
            { 'name':"word", 'type':"uint64", 'szField':"cap" },

            # Property types
            { 'name':"type", 'type':"uint8", 'szField':"cap" }
        ]
    },

    # Function/closure layout (extends object)
    {
        'name':'clos',
        'extends':'obj',
        'fields':
        [
            # Function code pointer
            { 'name':"fptr", 'type':"rawptr" },

            # Number of closure cells
            { 'name':"num_cells" , 'type':"uint32" },

            # Closure cell pointers
            { 'name':"cell", 'type':"refptr", 'szField':"num_cells" },
        ]
    },

    # Array layout (extends object)
    {
        'name':'arr',
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
        'fields':
        [
            # Array capacity
            { 'name':"cap" , 'type':"uint32" },

            # Element words
            { 'name':"word", 'type':"uint64", 'szField':"cap" },

            # Element types
            { 'name':"type", 'type':"uint8", 'szField':"cap" },
        ]
    },

    # Class layout
    {
        'name':'class',
        'fields':
        [
            # Class id / source origin location
            { 'name':"id", 'type':"uint32" },

            # Capacity, total number of property slots
            { 'name':"cap", 'type':"uint32" },

            # Number of properties in class
            { 'name':"num_props", 'type':"uint32", 'init':"0" },

            # Next class version reference
            # Used if class is reallocated
            { 'name':"next", 'type':"refptr", 'init':"null" },

            # Array element type
            { 'name':"arr_type", 'type':"rawptr", 'init':"null" },

            # Property names
            { 'name':"prop_name", 'type':"refptr", 'szField':"cap", 'init':"null" },

            # Property types
            # Pointers to host type descriptor objects
            { 'name':"prop_type", 'type':"rawptr", 'szField':"cap", 'init':"null" },

            # Property indices
            { 'name':"prop_idx", 'type':"uint32", 'szField':"cap" },
        ]
    },
]




# TODO: Generate functions....
# Use some kind of AST? Does Python have instanceof?
#   isinstance(obj, MyClass)
# Can have methods, genJS, genD
#
# Function: params, stmts
# ReturnStmt
# AddExpr
# MulExpr
# CallExpr
# ForLoop: idxVar


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

class IntCst:

    def __init__(self, val):
        self.val = val

    def genJS(self):
        return str(self.val)

    def genD(self):
        return str(self.val)

class ConstDef:

    def __init__(self, type, name, val):
        self.type = type
        self.name = name
        self.val = val

    def genJS(self):
        return 'var ' + self.name + ' = ' + str(self.val) + ';'

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
        out += 'function ' + self.name + '('
        out += sepList(map(lambda v:v.genJS(), self.params))
        out += ')\n'
        out += '{'
        stmts = ''
        for stmt in self.stmts:
            stmts += '\n' + stmt.genJS()
        out += indent(stmts)
        out += '\n}'
        return out

    def genD(self):
        out  = self.type + ' ' + self.name + '('
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

    def __init__(self, expr):
        self.expr = expr

    def genJS(self):
        return 'return ' + self.expr.genJS() + ';'

    def genD(self):
        return 'return ' + self.expr.genD() + ';'

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

class LoadExpr:

    def __init__(self, type, ptr, ofs):
        self.type = type
        self.ptr = ptr
        self.ofs = ofs

    def genJS(self):
        return '$ir_load_' + typeShortName[self.type] + '(' + self.ptr.genJS() + ', ' + self.ofs.genJS() + ')'

    def genD(self):
        return '*cast(' + self.type + ')(' + self.ptr.genD() + ' + ' + self.ofs.genD() + ')'

class StoreExpr:

    def __init__(self, type, ptr, ofs, val):
        self.type = type
        self.ptr = ptr
        self.ofs = ofs
        self.val = val

    def genJS(self):
        return '$ir_store_' + typeShortName[self.type] + '(' + self.ptr.genJS() + ', ' + self.ofs.genJS() + ', ' + self.val.genJS() + ')'

    def genD(self):
        return '*cast(' + self.type + ')(' + self.ptr.genD() + ' + ' + self.ofs.genD() + ') = ' + self.val.genD()

class CallExpr:

    def __init__(self, fName, args):
        self.fName = fName
        self.args = args

    def genJS(self):
        out = self.fName + '('
        out += sepList(map(lambda v:v.genJS(), self.args))
        out += ')'
        return out

    def genD(self):
        return self.genJS()

# TODO
class ForLoop:
    pass






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

# Assign layout ids and add the type field
nextLayoutId = 0
for layout in layouts:

    layoutId = nextLayoutId
    layout['typeId'] = layoutId
    nextLayoutId += 1

    typeField = [{ 'name':'type', 'type':'uint32', 'init':str(layoutId) }]
    layout['fields'] = typeField + layout['fields']

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
                    layout['szFields'] += prev
                break

        # If the size field was not found, raise an exception
        if field['szField'] == None:
            raise Exception('size field "%s" of "%s" not found' % (szName, field['name']))

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

        sumExpr = IntCst(0)

        for prev in layout['fields']:

            termExpr = IntCst(typeSize[prev['type']])

            if 'szField' in prev:
                szCall = CallExpr(getPref + prev['szField']['name'], [fun.params[0]])
                termExpr = MulExpr(termExpr, szCall)

            sumExpr = AddExpr(sumExpr, termExpr)

        if 'szField' in field:
            fieldSize = IntCst(typeSize[field['type']])
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

        # TODO: ExprStmt
        #fun.stmts += [ExprStmt(StoreExpr(field['type'], fun.params[0], ofsCall))]

        decls += [fun]







#TODO: auto-generated from sys.argv[0]

#file = open("datafile.txt", "w")
#file.write(newLine)
#file.close()

#D_OUT_FILE
#JS_OUT_FILE



# TODO: output D and JS code, write to file
for decl in decls:

    print(decl.genJS())

    print(decl.genD())






