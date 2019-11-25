# 11/25/2019 Experiment

We have Analyzer and Extractor (with Control Flow Edges) ready. So it's probably time for us to do some study!

## How to run

First we get a buggy version of OpenSSL (sha: `0a4d6c67480a4d2fce514e08d3efe571f2ee99c9`)

```
$ git clone https://github.com/openssl/openssl openssl_buggy
$ cd openssl_buggy
$ git checkout 0a4d6c67480a4d2fce514e08d3efe571f2ee99c9
```

Then we compile it

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
$ extract-bc libcrypto.so.3
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

Now go back to your project directory and run our tool! First build our tool:

```
$ make
```

Then run it!

```
$ ./llexecutor -fn CRYPTO_zalloc -n 1 YOUR/PATH/TO/openssl_buggy/llvm_objs/libcrypto.so.3.bc -outdir OUTPUT/PATH/libcrypto_buggy_CRYPTO_zalloc_n_1
```

Here, `-fn CRYPTO_zalloc` means we only slice the program around the function calls to `CRYPTO_zalloc`. `-n 1` means the slicing depth, and it determines the size of each slice. We also specify an `-outdir`. This directory is also useful for later analysis.

For our case we need to do symbolic execution on 815 slices. It can take quite a while to do so. For us it takes 22 minutes.

Finally we use our analyzer tool to find if there's bug inside the traces we collected. Do

```
$ ./llexecutor analyze OUTPUT/PATH/libcrypto_buggy_CRYPTO_zalloc_n_1
```

Here the only argument to analyzer is the `-outdir` of our previous step.