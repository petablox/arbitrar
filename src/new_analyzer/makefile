WLLVM = @ wllvm
LLVM_DIS = @ llvm-dis
RM = @ rm -rf
MV = @ mv

TEST_C_FILES = $(shell find tests/ -type f -name '*.c')
TEST_BC_FILES = $(patsubst tests/%.c, tests/%.bc, $(TEST_C_FILES))

all: tests

tests: $(TEST_BC_FILES)

tests/%.bc: tests/%.c
	$(WLLVM) -g -c "$<"
	$(RM) "./a.out" ".$(*F).o" "$(*F).o"
	$(MV) ".$(*F).o.bc" "$@"
	$(LLVM_DIS) "$@"

clean: clean-tests

clean-tests:
	$(RM) tests/c_files/**/*.bc tests/c_files/**/*.ll
