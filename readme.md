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
%8 = call i8* @malloc(i64 %7)
%13 = call i32 @g(i32* %12)
%16 = call i32 @h(i32* %15)
%6 = call i32 @f(i32 %5)
```

This is all of the call instructions appearing in the file `example_1.c`.

## Notes

- `make examples` will execute `wllvm` on every `.c` file in `exmples` folder
