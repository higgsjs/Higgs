DC = dmd
COPTS = -m64 -O -L-ldl
TESTOPTS = -m64 -O -L-ldl -unittest -debug
DBGOPTS = -m64 -O -L-ldl -gc -debug

BIN_NAME = higgs
BIN_NAME_TEST = test-higgs
BIN_NAME_DEBUG = dbg-higgs

BIN_DIR = /usr/bin
LIB_DIR = /etc/higgs

# Source files
SRC =               \
util/id.d           \
util/string.d       \
util/misc.d         \
util/bitset.d       \
analysis/typeset.d  \
parser/lexer.d      \
parser/ast.d        \
parser/vars.d       \
parser/parser.d     \
ir/ir.d             \
ir/ops.d            \
ir/iir.d            \
ir/ast.d            \
ir/peephole.d       \
ir/slotalloc.d      \
ir/livevars.d       \
ir/inlining.d       \
interp/interp.d     \
interp/ops.d        \
interp/layout.d     \
interp/string.d     \
interp/object.d     \
interp/gc.d         \
interp/ffi.d        \
jit/x86.d           \
jit/encodings.d     \
jit/codeblock.d     \
jit/assembler.d     \
jit/moves.d         \
jit/regalloc.d      \
jit/jit.d           \
jit/ops.d           \
jit/peephole.d      \
repl.d              \
options.d           \
stats.d             \
main.d              \
jit/tests.d         \
parser/tests.d      \
interp/tests.d

all: layout encodings
	$(DC) $(COPTS) -of$(BIN_NAME) $(SRC)

test: layout encodings
	$(DC) $(TESTOPTS) -of$(BIN_NAME_TEST) $(SRC)
	time ./$(BIN_NAME_TEST)

debug: layout encodings
	$(DC) $(DBGOPTS) -of$(BIN_NAME_DEBUG) $(SRC)

encodings:
	python jit/encodings.py

layout:
	python interp/layout.py

clean:
	rm $(BIN_NAME) $(BIN_NAME_TEST) *.o

install:
	@if [ ! -d $(LIB_DIR) ] ; then echo "mkdir $(LIB_DIR)" ; mkdir $(LIB_DIR) ; fi
	@if [ ! -d $(LIB_DIR)/interp ] ; then echo "mkdir $(LIB_DIR)/interp" ; mkdir $(LIB_DIR)/interp ; fi
	@if [ ! -d $(LIB_DIR)/stdlib ] ; then echo "mkdir $(LIB_DIR)/stdlib" ; mkdir $(LIB_DIR)/stdlib ; fi
	@if [ ! -d $(LIB_DIR)/lib ] ; then echo "mkdir $(LIB_DIR)/lib" ; mkdir $(LIB_DIR)/lib ; fi
	cp ./interp/*.js $(LIB_DIR)/interp
	cp ./stdlib/*.js $(LIB_DIR)/stdlib
	cp ./lib/*.js $(LIB_DIR)/lib
	cp $(BIN_NAME) $(BIN_DIR)

