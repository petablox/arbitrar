# LibCrypto - CRYPTO_zalloc

This document documents how we are doing experiments on LibCrypto CRYPTO_zalloc

## Stats

- Number of slices: 98
- Number of traces: 209
- Average #trace/#slice: 2.13

## How to compile

``` bash
$ cd /home/liby99/projects/unsup_laboratory/
$ git clone https://github.com/openssl/openssl
$ cd openssl
$ mkdir llvm_objs
$ set -Ux CC wllvm
$ set -Ux CXX wllvm++
$ set -Ux CFLAGS "-O1 -g"
$ ../config
$ make -j32
$ extract-bc libssl.so.3
```

Side notes:

1. We use flag `"-O1 -g"`.
  - `O1` is to disable optimization
  - `-g` enabling debug information
2. There are two libraries being compiled: `libssl.so.3` and `libcrypto.so.3`. We
  wanted to use `libcrypto` since it's more direct. But unfortunately our code is
  stuck on that library. We can perform good in `libssl` though. This is worth
  investigating

TODO:

1. Find an earlier version of `openssl` from Github so that Kihong's posted bug
  still exhibits in the code.

## How to run

``` bash
$ cd /home/liby99/projects/ll_analyzer
$ ./llextractor -n 5 -fn CRYPTO_zalloc -outdir data/libssl_crypto_zalloc_n_5 ../unsup_laboratory/openssl/llvm_objs/libssl.so.3.bc
```

Output:

```
Slicing complete in 0.559377 sec
98/98 slices processing
Symbolic Execution complete in 154.589123 sec
```

The output currently resides in

```
fir03:/home/liby99/data/libssl_crypto_zalloc_n_5
```

Side notes:

1. We are targeting to find the `OPENSSL_zalloc` function. But it's actually a macro
  which is using the real function `CRYPTO_zalloc`. Hence we specify we only care
  about this function in our extractor argument: `-fn CRYPTO_zalloc`
2. In this case, we use slicing depth 5 around the function, by specifying argument
  `-n 5`