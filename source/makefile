DC = dmd
ifndef PYTHON
	PYTHON = python
endif
# compiler options
UNAME := $(shell uname)
ifneq (, $(findstring BSD, $(UNAME)))
# BSD
	LIBS :=
else
# Linux, Darwin, etc
	LIBS := -L-ldl
endif

COPTS := -m64 -O -J./ -dip25
TESTOPTS := -m64 -O -J./ -unittest -debug -dip25
DBGOPTS := -m64 -O  -J./ -gc -debug -dip25
RELOPTS := -m64 -O -J./ -release -inline -boundscheck=off -version=release -dip25
PROFOPTS := -m64 -O -J./ -release -inline -boundscheck=off -profile -dip25

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
ir/analysis.d       \
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
ffi/os.d            \
ffi/tests.d         \

all: layout
	$(DC) $(LIBS) $(COPTS) -of$(BIN_NAME) $(SRC)

ffidev:
	$(DC) $(LIBS) $(COPTS) -of$(BIN_NAME_TEST) $(SRC) -gc -version=FFIdev

test: layout
	$(DC) $(LIBS) $(TESTOPTS) -of$(BIN_NAME_TEST) $(SRC)
	./$(BIN_NAME_TEST) test-runner.js
	rm $(BIN_NAME_TEST)

prof: layout
	$(DC) $(LIBS) $(PROFOPTS) -of$(BIN_NAME_PROF) $(SRC)

debug: layout
	$(DC) $(LIBS) $(DBGOPTS) -of$(BIN_NAME_DEBUG) $(SRC)

release: layout
	printf $(LIB_DIR) > ./libdir.txt;
	$(DC) $(LIBS) $(RELOPTS) -of$(BIN_NAME) $(SRC)

layout:
	$(PYTHON) runtime/layout.py

clean:
	rm -f $(BIN_NAME) $(BIN_NAME_TEST) $(BIN_NAME_DEBUG) *.o

install: release
	@if [ ! -d $(LIB_DIR) ] ; then echo "mkdir $(LIB_DIR)" ; mkdir $(LIB_DIR) ; fi
	@if [ ! -d $(LIB_DIR)/runtime ] ; then echo "mkdir $(LIB_DIR)/runtime" ; mkdir $(LIB_DIR)/runtime ; fi
	@if [ ! -d $(LIB_DIR)/stdlib ] ; then echo "mkdir $(LIB_DIR)/stdlib" ; mkdir $(LIB_DIR)/stdlib ; fi
	@if [ ! -d $(LIB_DIR)/lib ] ; then echo "mkdir $(LIB_DIR)/lib" ; mkdir $(LIB_DIR)/lib ; fi
	cp ./runtime/*.js $(LIB_DIR)/runtime
	cp ./stdlib/*.js $(LIB_DIR)/stdlib
	cp -R ./lib/* $(LIB_DIR)/lib
	cp $(BIN_NAME) $(BIN_DIR)

install-dev: release
	@if [ ! -d $(LIB_DIR) ] ; then echo "mkdir $(LIB_DIR)" ; mkdir $(LIB_DIR) ; fi
	ln -s -f "$(CURDIR)/runtime/" $(LIB_DIR)
	ln -s -f "$(CURDIR)/stdlib/" $(LIB_DIR)
	ln -s -f "$(CURDIR)/lib/" $(LIB_DIR)
	ln -s -f "$(CURDIR)/$(BIN_NAME)" $(BIN_DIR)

