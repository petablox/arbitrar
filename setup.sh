#!/bin/bash

pip3 install wllvm

opam install ocamlbuild llvm.8.0.0 ctypes ctypes-foreign yojson ocamlgraph ocamlformat merlin
