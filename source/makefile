DC = dmd
COPTS = -m64 -O

BIN_NAME = higgs

# Source files
SRC =               \
util/id.d           \
util/string.d       \
util/misc.d         \
parser/lexer.d      \
parser/ast.d        \
parser/vars.d       \
parser/parser.d     \
parser/tests.d      \
ir/ir.d             \
ir/ast.d            \
interp/interp.d     \
interp/ops.d        \
interp/layout.d     \
interp/string.d     \
interp/tests.d      \
repl.d              \
main.d

all: layout
	$(DC) $(COPTS) -of$(BIN_NAME) $(SRC)

test: layout
	$(DC) $(COPTS) -unittest -of$(BIN_NAME) $(SRC)
	time ./$(BIN_NAME) --test

layout:
	python interp/layout.py

clean:
	rm $(BIN_NAME) *.o

