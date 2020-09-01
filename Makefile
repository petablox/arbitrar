.PHONY: all

all: build

install:
	ln -s ./misapi $(HOME)/.local/bin/misapi
	ln -s ./scripts/a2bc $(HOME)/.local/bin/a2bc

setup:
	pip3 install mypy yapf pytest python-magic termcolor
	pip3 install graphviz scikit-learn matplotlib pandas
	pip3 install wllvm
	opam install ocamlbuild ocamlformat merlin parmap
	opam install ocamlgraph yojson ppx_compare ppx_deriving ppx_deriving_yojson
	opam install llvm ctypes ctypes-foreign z3

.PHONY: build

build: build-ml build-rs

build-ml:
	make -C src/analyzer

build-rs:
	cd src/new_analyzer ; cargo build --release

clean:
	make clean -C src/analyzer

.PHONY: format

format: format-py format-ml format-rs

.PHONY: format-py

format-py:
	yapf -i --recursive misapi src/

.PHONY: format-ml

format-ml:
	make -C src/analyzer format

format-rs:
	cd src/new_analyzer ; cargo fmt
