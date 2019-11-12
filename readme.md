# LLVM (Toy) Analyzer

First bulid the examples:

``` bash
$ make examples
```

Then make the project:

``` bash
$ make
```

Then you will be able to run the slicer:

``` bash
$ ./llextractor slice examples/example_4.bc
```

The result will be like this:

```
Slice [ Entry: main, Functions: main, x2, x1, Call: (main -> x2), Instr:   %2 = call i32 @x2() ]
Slice [ Entry: main, Functions: main, x2, x1, Call: (main -> x1), Instr:   %1 = call i32 @x1() ]
Slice [ Entry: main, Functions: main, x2, y1, x1, Call: (x2 -> y1), Instr:   %2 = call i32 @y1() ]
Slice [ Entry: main, Functions: main, x2, y1, x1, Call: (x1 -> y1), Instr:   %2 = call i32 @y1() ]
Slice [ Entry: x1, Functions: x1, y1, z1, Call: (y1 -> z1), Instr:   %2 = call i32 @z1() ]
Slice [ Entry: x2, Functions: x2, y1, z1, Call: (y1 -> z1), Instr:   %2 = call i32 @z1() ]
Slice [ Entry: y1, Functions: y1, z1, printf, Call: (z1 -> printf), Instr:   %2 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([13 x i8], [13 x i8]* @.str, i64 0, i64 0)) ]
```

It gives you slices around each function call.

You can also run the symbolic executor:

``` bash
$ ./llextractor execute examples/example_1.bc
```

## Setup

Please run

``` bash
$ ./setup.sh
```

To setup the whole project. If you want, you can also setup a pre-commit hook:

``` bash
$ ./scripts/setup-pre-commit.sh
```

This hook will run `ocamlformat` everytime you do a commit. So it will keep all of your code in best condition!

## Behind the hood

We use `wllvm` to compile the `.c` files into `.bc` byte codes in the examples folder. Our tools directly run on LLVM byte code and does static analyze and symbolic execution to get core traces around each function call.