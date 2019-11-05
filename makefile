OCAMLBUILD = @ ocamlbuild
WLLVM = @ wllvm
RM = @ rm -rf
MV = @ mv

DIRECTORIES = -Is core,ast,parser,compiler,runner,util
LLVM_FLAGS = -package llvm -package llvm.analysis -package llvm.executionengine
MENHIR_FLAGS = -use-menhir
FLAGS = $(MENHIR_FLAGS) $(LLVM_FLAGS) $(DIRECTORIES)

EXAMPLE_C_FILES = $(shell find examples/ -type f -name '*.c')
EXAMPLE_BC_FILES = $(patsubst examples/%.c, examples/%.bc, $(EXAMPLE_C_FILES))

analyzer: src/*.ml
	$(OCAMLBUILD) $(FLAGS) llanalyzer.native
	$(MV) llanalyzer.native llanalyzer

examples: $(EXAMPLE_BC_FILES)

examples/%.bc: examples/%.c
	$(WLLVM) "$<"
	$(RM) "./a.out" ".$(*F).o"
	$(MV) ".$(*F).o.bc" "examples/$(*F).bc"

clean:
	$(OCAMLBUILD) -clean