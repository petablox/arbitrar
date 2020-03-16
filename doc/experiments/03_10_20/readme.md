# Experiment with OpenSSL

This tutorial will be divided into several parts:

1. Compile a specific version of OpenSSL that can be read by our system
2. Run our slicer/executor on this OpenSSL
3. Run analyzer on our generated data
4. Inspect results

## Compile OpenSSL

First we get a buggy version of OpenSSL (sha: `0a4d6c67480a4d2fce514e08d3efe571f2ee99c9`)

```
$ git clone https://github.com/openssl/openssl openssl_buggy
$ cd openssl_buggy
$ git checkout 0a4d6c67480a4d2fce514e08d3efe571f2ee99c9
```

Then we compile it using `wllvm`. We use `-g` for debug information, `-O1` to disable optimization.

```
$ mkdir llvm_objs
$ cd llvm_objs
$ LLVM_COMPILER=clang CC=wllvm CXX=wllvm++ CFLAGS="-g -O1" ../config
$ make
```

> For the last step we used `make -j32` because we have that many cores!

Now if you `ls` your current `llvm_objs` directory, you will find

```
$ ls -l
...something else
-rwxrwxr-x  1 liby99 liby99  9029280 Nov 25 15:01 libcrypto.so.3*
-rwxrwxr-x  1 liby99 liby99  1921160 Nov 25 15:01 libssl.so.3*
```

We need to then use `extract-bc` on them

```
$ extract-bc libcrypto.so.3
$ extract-bc libssl.so.3
```

After this you will see two `.bc` files:

```
$ ls -l
...something else
-rw-rw-r--  1 liby99 liby99 13344904 Nov 25 15:01 libcrypto.so.3.bc
-rw-rw-r--  1 liby99 liby99  3089820 Nov 25 15:01 libssl.so.3.bc
```

These are the two libraries we are going to do study on. Actually, the bug inside that
specific commit actually only comes from `libcrypto`. So we only need to run that.

## Run our slicer/executor

Go to the root folder of our repo, simply type

``` sh
make
```

This will give you an executable called `llextractor` in the current folder.

Let's first generate slices/traces data on only the `openssl_fopen` function:

``` sh
./llextractor \
  -n 1 \
  -include-fn openssl_fopen \
  -output-dot -output-trace -pretty-json \
  -outdir data/libcrypto_openssl_fopen \
  <PATH_TO_YOUR_OPENSSL_REPO>/llvm_objs/libcrypto.so.3.bc
```

Let's look at the parameters one by one

- `-n 1`: decides the size of slice. Usually just `1` is enough
- `-include-fn openssl_fopen`: Since we only want to check the `openssl_fopen` function.
- `-output-dot`: Output dot files
- `-output-trace`: Output trace files
- `-pretty-json`: Prettify `.json` file
- `-outdir data/libcrypto_openssl_fopen`: Output to `data/libcrypto_openssl_fopen` folder

The last argument is the input file, in our case `libcrypto.so.3.bc`.

The whole execution will last for several seconds. You should see the following output:

```
Running extractor on /home/liby99/projects/api-misuse/ll_analyzer/../unsup_laboratory/openssl_buggy/llvm_objs/libcrypto.so.3.bc...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/dugraphs
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/dots
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/traces
Slicing program...
Slicing edge #37665...
Done creating edge entries map
Processing slice #13...
Slicer done creating 14 slices
Dumping slices into json...
Slicing complete in 0.447907 sec
14/14 slices processing
Symbolic Execution complete in 8.210409 sec
Filtering /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen...
Loading traces...
Labeling filter result...
Analyzing /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis
Running checker #0: retval...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/retval
14 slices loaded (trace_id: 49)
Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/retval/functions
Dumping results and bug reports...
14 slices loaded (trace_id: 49)
Labeling bugs in-place...
Running checker #1: argrel...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argrel
14 slices loaded (trace_id: 49)
Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argrel/functions
Dumping results and bug reports...
14 slices loaded (trace_id: 49)
Labeling bugs in-place...
Running checker #2: argval-0...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-0
14 slices loaded (trace_id: 49)
Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-0/functions
Dumping results and bug reports...
14 slices loaded (trace_id: 49)
Labeling bugs in-place...
Running checker #3: argval-1...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-1
14 slices loaded (trace_id: 49)
Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-1/functions
Dumping results and bug reports...
14 slices loaded (trace_id: 49)
Labeling bugs in-place...
Running checker #4: argval-2...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-2

Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-2/functions
Dumping results and bug reports...

Labeling bugs in-place...
Running checker #5: argval-3...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-3

Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/argval-3/functions
Dumping results and bug reports...

Labeling bugs in-place...
Running checker #6: causality...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/causality
14 slices loaded (trace_id: 49)
Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/causality/functions
Dumping results and bug reports...
14 slices loaded (trace_id: 49)
Labeling bugs in-place...
Running checker #7: fopen...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/fopen
14 slices loaded (trace_id: 49)
Dumping statistics...
Creating directory /home/liby99/projects/api-misuse/ll_analyzer/data/libcrypto_openssl_fopen/analysis/fopen/functions
Dumping results and bug reports...
14 slices loaded (trace_id: 49)
Labeling bugs in-place...
```

## Inspecting Slices, DUGraph, Trace & Dot Files

### Slices

In the slicing step of our execution, we slice the

### DUGraph

The primary