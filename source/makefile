DC = dmd
BIN_NAME = higgs

# Source files
SRC =           \
util/id.d       \
util/string.d   \
parser/lexer.d  \
parser/ast.d    \
parser/vars.d   \
parser/parser.d \
ir/ir.d         \
ir/ast.d        \
repl.d          \
main.d

all:
	$(DC) $(SRC) -of$(BIN_NAME)

test:
	$(DC) $(SRC) -unittest -of$(BIN_NAME)
	time ./$(BIN_NAME) --test

clean:
	rm $(BIN_NAME) *.o

