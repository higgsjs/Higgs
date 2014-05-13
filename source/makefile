DC = dmd
# compilter options
UNAME := $(shell uname)
ifneq (, $(findstring BSD, $(UNAME)))
# BSD
	LIBS :=
else
# Linux, Darwin, etc
	LIBS := -L-ldl -J./
endif

COPTS := -m64 -O -J./
TESTOPTS := -m64 -O -J./ -unittest -debug
DBGOPTS := -m64 -O  -J./ -gc -debug
RELOPTS := -m64 -O -J./ -release -inline -noboundscheck -version=release
PROFOPTS := -m64 -O -J./ -release -inline -noboundscheck -profile

BIN_NAME = higgs
BIN_NAME_TEST = higgs-test
BIN_NAME_PROF = higgs-prof
BIN_NAME_DEBUG = higgs-dbg

BIN_DIR = /usr/bin
LIB_DIR = /etc/higgs


# Source files
SRC =               \
util/error.d        \
util/id.d           \
util/string.d       \
util/misc.d         \
util/bitset.d       \
util/os.d           \
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
ir/typeprop.d       \
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
runtime/tests.d     \
runtime/ffitests.d

all: layout
	$(DC) $(LIBS) $(COPTS) -of$(BIN_NAME) $(SRC)

ffidev:
	$(DC) $(LIBS) $(COPTS) -of$(BIN_NAME_TEST) $(SRC) -gc -version=FFIdev

test: layout
	$(DC) $(LIBS) $(TESTOPTS) -of$(BIN_NAME_TEST) $(SRC)
	time ./$(BIN_NAME_TEST) test-runner.js
	rm $(BIN_NAME_TEST)

prof: layout
	$(DC) $(LIBS) $(PROFOPTS) -of$(BIN_NAME_PROF) $(SRC)

debug: layout
	$(DC) $(LIBS) $(DBGOPTS) -of$(BIN_NAME_DEBUG) $(SRC)

release: layout
	printf $(LIB_DIR) > ./libdir.txt;
	$(DC) $(LIBS) $(RELOPTS) -of$(BIN_NAME) $(SRC)

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

