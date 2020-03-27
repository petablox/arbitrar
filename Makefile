.PHONY: all

all: build

setup:
	pip3 install wllvm mypy flake8 autopep8 pytest scikit-learn
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
	autopep8 --in-place --recursive --aggressive .

.PHONY: format-ml

format-ml:
	make -C src/analyzer format
