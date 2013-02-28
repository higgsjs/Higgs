DC = dmd
COPTS = -m64 -O

BIN_NAME = higgs
BIN_NAME_TEST = test-higgs

# Source files
SRC =               \
util/id.d           \
util/string.d       \
util/misc.d         \
analysis/typeset.d  \
parser/lexer.d      \
parser/ast.d        \
parser/vars.d       \
parser/parser.d     \
ir/ir.d             \
ir/ast.d            \
interp/interp.d     \
interp/ops.d        \
interp/layout.d     \
interp/string.d     \
interp/object.d     \
interp/gc.d         \
jit/x86.d           \
jit/encodings.d     \
jit/codeblock.d     \
jit/assembler.d     \
jit/jit.d           \
jit/tests.d         \
parser/tests.d      \
interp/tests.d      \
repl.d              \
options.d           \
main.d

all: layout encodings
	$(DC) $(COPTS) -of$(BIN_NAME) $(SRC)

test: layout encodings
	$(DC) $(COPTS) -unittest -of$(BIN_NAME_TEST) $(SRC)
	time ./$(BIN_NAME_TEST) --test

encodings:
	python jit/encodings.py

layout:
	python interp/layout.py

clean:
	rm $(BIN_NAME) $(BIN_NAME_TEST) *.o

