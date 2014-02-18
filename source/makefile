DC = dmd
COPTS = -m64 -O -L-ldl -J./
TESTOPTS = -m64 -O -L-ldl -J./ -unittest -debug
DBGOPTS = -m64 -O -L-ldl -J./ -gc -debug
RELOPTS = -m64 -O -L-ldl -J./ -release -inline -noboundscheck

BIN_NAME = higgs
BIN_NAME_TEST = test-higgs
BIN_NAME_DEBUG = dbg-higgs

BIN_DIR = /usr/bin
LIB_DIR = /etc/higgs

# Source files
SRC =               \
util/error.d        \
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
runtime/vm.d        \
runtime/layout.d    \
runtime/string.d    \
runtime/object.d    \
runtime/gc.d        \
jit/x86.d           \
jit/codeblock.d     \
jit/util.d          \
jit/moves.d         \
jit/ops.d           \
jit/jit.d           \
repl.d              \
options.d           \
stats.d             \
main.d              \
jit/tests.d         \
parser/tests.d      \
runtime/tests.d

all: layout
	$(DC) $(COPTS) -of$(BIN_NAME) $(SRC)

test: layout
	$(DC) $(TESTOPTS) -of$(BIN_NAME_TEST) $(SRC)
	time ./$(BIN_NAME_TEST) test-runner.js

debug: layout
	$(DC) $(DBGOPTS) -of$(BIN_NAME_DEBUG) $(SRC)

release: layout
	printf $(LIB_DIR) > ./libdir.txt;
	$(DC) $(RELOPTS) -of$(BIN_NAME) $(SRC)

layout:
	python runtime/layout.py

clean:
	rm -f $(BIN_NAME) $(BIN_NAME_TEST) $(BIN_NAME_DEBUG) *.o

install: release
	@if [ ! -d $(LIB_DIR) ] ; then echo "mkdir $(LIB_DIR)" ; mkdir $(LIB_DIR) ; fi
	@if [ ! -d $(LIB_DIR)/runtime ] ; then echo "mkdir $(LIB_DIR)/runtime" ; mkdir $(LIB_DIR)/runtime ; fi
	@if [ ! -d $(LIB_DIR)/stdlib ] ; then echo "mkdir $(LIB_DIR)/stdlib" ; mkdir $(LIB_DIR)/stdlib ; fi
	@if [ ! -d $(LIB_DIR)/lib ] ; then echo "mkdir $(LIB_DIR)/lib" ; mkdir $(LIB_DIR)/lib ; fi
	cp ./runtime/*.js $(LIB_DIR)/runtime
	cp ./stdlib/*.js $(LIB_DIR)/stdlib
	cp ./lib/*.js $(LIB_DIR)/lib
	cp $(BIN_NAME) $(BIN_DIR)

