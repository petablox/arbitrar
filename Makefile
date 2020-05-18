.PHONY: all

all: build

setup:
	pip3 install mypy yapf pytest python-magic # Utilities
	pip3 install wllvm graphviz z3 # PL
	pip3 install scikit-learn matplotlib # ML
	pip3 install pandas termcolor
	opam install ocamlbuild ocamlformat merlin
	opam install llvm ctypes ctypes-foreign
	opam install ocamlgraph
	opam install yojson ppx_compare ppx_deriving ppx_deriving_yojson

.PHONY: build

build:
	make -C src/analyzer

clean:
	make clean -C src/analyzer

.PHONY: format

format: format-py format-ml

.PHONY: format-py

format-py:
	yapf -i --recursive misapi src/

.PHONY: format-ml

format-ml:
	make -C src/analyzer format
