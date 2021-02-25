.PHONY: all install build format

all: build

install:
	ln -s ./arbitrar $(HOME)/.local/bin/arbitrar
	ln -s ./scripts/a2bc $(HOME)/.local/bin/a2bc

setup:
	pip3 install mypy yapf pytest python-magic termcolor
	pip3 install graphviz scikit-learn matplotlib pandas
	pip3 install wllvm
	opam install ocamlbuild ocamlformat merlin parmap
	opam install ocamlgraph yojson ppx_compare ppx_deriving ppx_deriving_yojson
	opam install llvm ctypes ctypes-foreign z3

build: build-rs

# build-ml:
# 	make -C src/old_analyzer

build-rs:
	cd src/analyzer ; cargo build --release

clean:
	make clean -C src/analyzer

format: format-py format-rs

format-py:
	yapf -i --recursive arbitrar src/

# format-ml:
# 	make -C src/old_analyzer format

format-rs:
	cd src/analyzer ; cargo fmt
