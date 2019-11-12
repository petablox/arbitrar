OCAMLBUILD = @ ocamlbuild
WLLVM = @ wllvm
RM = @ rm -rf
MV = @ mv

OCAML_FLAGS = -package llvm -package llvm.analysis -package llvm.bitreader -package llvm.executionengine -package yojson -package str -package ocamlgraph
FLAGS = $(OCAML_FLAGS) $(DIRECTORIES)

EXAMPLE_C_FILES = $(shell find examples/ -type f -name '*.c')
EXAMPLE_BC_FILES = $(patsubst examples/%.c, examples/%.bc, $(EXAMPLE_C_FILES))

all:
	$(OCAMLBUILD) $(FLAGS) src/main.native
	$(MV) main.native llextractor

examples: $(EXAMPLE_BC_FILES)

examples/%.bc: examples/%.c
	$(WLLVM) "$<"
	$(RM) "./a.out" ".$(*F).o"
	$(MV) ".$(*F).o.bc" "examples/$(*F).bc"

clean:
	$(OCAMLBUILD) -clean
