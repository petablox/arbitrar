.PHONY: all

all:

setup:
	pip3 install wllvm mypy flake8 autopep8 pytest
	opam install ocamlbuild ocamlformat merlin
	opam install llvm.8.0.0 ctypes ctypes-foreign
	opam install ocamlgraph
	opam install yojson ppx_compare ppx_deriving ppx_deriving_yojson

build:
	make -C src/analyzer

.PHONY: format

format: format-py format-ml

.PHONY: format-py

format-py:
	autopep8 --in-place --recursive --aggressive .

.PHONY: format-ml

format-ml:
	ls src/*.ml | xargs -I '{}' ocamlformat '{}' --output '{}'