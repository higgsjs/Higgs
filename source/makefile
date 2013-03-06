DC = dmd
COPTS = -m64 -O

BIN_NAME = higgs
BIN_NAME_TEST = test-higgs

BIN_DIR = .

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
	@if [ ! -d $(BIN_DIR) ] ; then echo "mkdir $(BIN_DIR)" ; mkdir $(BIN_DIR) ; fi
	@if [ ! -d $(BIN_DIR)/interp ] ; then echo "mkdir $(BIN_DIR)/interp" ; mkdir $(BIN_DIR)/interp ; fi
	@if [ ! -d $(BIN_DIR)/stdlib ] ; then echo "mkdir $(BIN_DIR)/stdlib" ; mkdir $(BIN_DIR)/stdlib ; fi
	@if [ "`readlink -f $(BIN_DIR)`" != "$(PWD)" ] ; then\
		echo "cp ./interp/*.js $(BIN_DIR)/interp/" ;\
		cp ./interp/*.js $(BIN_DIR)/interp ;\
		echo "cp ./stdlib/*.js $(BIN_DIR)/stdlib" ;\
		cp ./stdlib/*.js $(BIN_DIR)/stdlib ;\
	 fi
	$(DC) $(COPTS) -of$(BIN_DIR)/$(BIN_NAME) $(SRC)

test: layout encodings
	$(DC) $(COPTS) -unittest -of$(BIN_DIR)/$(BIN_NAME_TEST) $(SRC)
	time $(BIN_DIR)/$(BIN_NAME_TEST) --test

encodings:
	python jit/encodings.py

layout:
	python interp/layout.py

clean:
	@if [ "`readlink -f $(BIN_DIR)`" != "$(PWD)" ] ; then\
		echo "rm -rf interp stdlib" ;\
		cd $(BIN_DIR)/ && rm -rf interp stdlib ;\
	 fi
	cd $(BIN_DIR)/ && rm -f $(BIN_NAME) $(BIN_NAME_TEST) $(BIN_NAME).o $(BIN_NAME_TEST).o