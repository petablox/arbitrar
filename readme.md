# LLVM (Toy) Analyzer

First build examples:

```
$ make examples
```

Then try to build the project:

```
$ make
```

Finally you can see the compiled executable. To run it, type

```
$ ./llanalyzer examples/example_1.bc
```

You should see the example 1 llvm module being dumped onto the terminal. Note that `llanalyzer` need to take in an LLVM ByteCode-format file.

## Setup

### Mac setup

To run it on **mac**, you need `clang`, `python3` and `ocaml` as prerequisites. Along with `ocaml` you might also need `ocaml-findlib` and so on. After you have these, please

1. Install `llvm`

```
$ brew install llvm@9
```

> We are using the latest version of llvm to reduce the level of burden going with opam

2. Install ocaml binding of `llvm`

```
$ opam install ctypes
$ opam install ctypes-foreign
$ opam install llvm
```

3. Install `wllvm`

```
$ pip3 install wllvm
```

## Results

Currently you will see it spitting out

```
(f -> malloc); (f -> g); (f -> h); (main -> f);
```

This is the call graph appearing in the file `example_1.c`. It means,

- Function `f` calls `malloc`;
- Function `f` calls `g`;
- Function `f` calls `h`;
- Function `main` calls `f`;

## Notes

- `make examples` will execute `wllvm` on every `.c` file in `exmples` folder

## TODOS

- [ ] Check whether OpenSSL can be compiled
- [ ] Write crawler for getting all C/C++ related repositories
  - [ ] URL first
  - [ ] Repo (in long run)
- [ ] Setting up `ocamlformat` in commit hook
- [ ] Get the slice related to a given function call
- [ ] Add more command line arguments