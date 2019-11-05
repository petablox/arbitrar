OCAMLBUILD = @ ocamlbuild
RM = @ rm -rf
MV = @ mv

DIRECTORIES = -Is core,ast,parser,compiler,runner,util
LLVM_FLAGS = -package llvm -package llvm.analysis -package llvm.executionengine
MENHIR_FLAGS = -use-menhir
FLAGS = $(MENHIR_FLAGS) $(LLVM_FLAGS) $(DIRECTORIES)

menhera: src/*.ml
	$(OCAMLBUILD) $(FLAGS) llanalyzer.native
	$(MV) llanalyzer.native llanalyzer

clean:
	$(OCAMLBUILD) -clean