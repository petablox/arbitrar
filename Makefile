.PHONY: all

all: build

install:
	ln -s $(HOME)/ll_analyzer/misapi $(HOME)/.local/bin/misapi

setup:
	pip3 install mypy yapf pytest python-magic termcolor
	pip3 install graphviz scikit-learn matplotlib pandas
	pip3 install wllvm
	opam install ocamlbuild ocamlformat merlin parmap
	opam install ocamlgraph yojson ppx_compare ppx_deriving ppx_deriving_yojson
	opam install llvm ctypes ctypes-foreign z3

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
