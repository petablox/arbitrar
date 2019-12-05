OCAMLBUILD = @ ocamlbuild -use-ocamlfind
WLLVM = @ wllvm
RM = @ rm -rf
MV = @ mv

EXAMPLE_C_FILES = $(shell find examples/ -type f -name '*.c')
EXAMPLE_BC_FILES = $(patsubst examples/%.c, examples/%.bc, $(EXAMPLE_C_FILES))

all:
	$(OCAMLBUILD) src/main.native
	$(MV) main.native llextractor

examples: $(EXAMPLE_BC_FILES)

examples/%.bc: examples/%.c
	$(WLLVM) "$<"
	$(RM) "./a.out" ".$(*F).o"
	$(MV) ".$(*F).o.bc" "examples/$(*F).bc"

format:
	ls src/*.ml | xargs -I '{}' ocamlformat '{}' --output '{}'

clean:
	$(OCAMLBUILD) -clean
