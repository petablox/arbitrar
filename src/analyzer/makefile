OCAMLBUILD = @ ocamlbuild -use-ocamlfind
WLLVM = @ wllvm
RM = @ rm -rf
MV = @ mv

TEST_C_FILES = $(shell find tests/ -type f -name '*.c')
TEST_BC_FILES = $(patsubst tests/%.c, tests/%.bc, $(TEST_C_FILES))

all:
	$(OCAMLBUILD) src/main.native
	$(MV) main.native analyzer

tests: $(TEST_BC_FILES)

tests/%.bc: tests/%.c
	$(WLLVM) -g -c "$<"
	$(RM) "./a.out" ".$(*F).o" "$(*F).o"
	$(MV) ".$(*F).o.bc" "$@"

clean:
	$(OCAMLBUILD) -clean

clean-tests:
	$(RM) tests/*.bc
