# 11/25/2019 Experiment

We have Analyzer and Extractor (with Control Flow Edges) ready. So it's probably time for us to do some study!

## How to run

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

Now go back to your project directory and run our tool! First build our tool:

```
$ make
```

Then run it!

```
$ ./llexecutor -fn CRYPTO_zalloc -n 1 -max-traces 50 YOUR/PATH/TO/openssl_buggy/llvm_objs/libcrypto.so.3.bc -outdir OUTPUT/PATH/libcrypto_buggy_CRYPTO_zalloc_n_1
```

Here, `-fn CRYPTO_zalloc` means we only slice the program around the function calls to `CRYPTO_zalloc`. `-n 1` means the slicing depth, and it determines the size of each slice. `-max-traces` is needed to restrict the number of traces for each slice. Here we specify it to be 50, which should be enough for analysis. We also specify an `-outdir`. This directory is also useful for later analysis.

For our case we need to do symbolic execution on 815 slices. It can take quite a while to do so.

Finally we use our analyzer tool to find if there's bug inside the traces we collected. Do

```
$ ./llexecutor analyze OUTPUT/PATH/libcrypto_buggy_CRYPTO_zalloc_n_1
```

Here the only argument to analyzer is the `-outdir` of our previous step. During the run you might find it spending lots of the time just loading json files, but after that it should be finishing running in a few seconds.

Now if you go to the target directory and do `ls`, you'll see

```
$ cd OUTPUT/PATH/libcrypto_buggy_CRYPTO_zalloc_n_1
$ ls -l
total 1680
drwxr-sr-x 3 liby99 liby99     36 Nov 25 16:07 analysis/
drwxr-sr-x 2 liby99 liby99 806912 Nov 25 12:34 dugraphs/
-rw-r--r-- 1 liby99 liby99  10481 Nov 25 12:34 log.txt
-rw-r--r-- 1 liby99 liby99 671756 Nov 25 12:34 slices.json
drwxr-sr-x 2 liby99 liby99     10 Nov 25 12:34 traces/
```

Notice that there's an `analysis` folder popping up. Going into that, you'll see

```
$ cd analysis
$ ls -l
total 0
drwxr-sr-x 2 liby99 liby99 88 Nov 25 19:01 retval_checker/
```

There's only a single folder called `retval_checker`. That's because we only have a single checker ran by now. Going into that again, you can see

```
$ cd retval_checker
$ ls -l
total 1604
-rw-rw-r-- 1 liby99 liby99   23164 Nov 25 19:01 bugs.csv
-rw-rw-r-- 1 liby99 liby99     462 Nov 25 19:01 CRYPTO_zalloc-stats.csv
-rw-rw-r-- 1 liby99 liby99 1613438 Nov 25 19:01 results.csv
```

There will be a file `bugs.csv` containing the bug report. There are also stats that we can do analysis further. All files are in `.csv` format so that we can easily do further manipulation in spreadsheet applications like Google Sheet or Excel.

So that's the end of the running part! Next we are going to take a deeper look at the generated data themselves.

## Bugs inspection

There are lots of bugs there in `bugs.csv`:

```
Slice Id,Trace Id,Entry,Function,Location,Score,Result
73,27,BIO_new_PKCS7,CRYPTO_zalloc,crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16,0.993731,NoCheck,,
73,28,BIO_new_PKCS7,CRYPTO_zalloc,crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16,0.993731,NoCheck,,
74,27,BIO_new_CMS,CRYPTO_zalloc,crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16,0.993731,NoCheck,,
74,28,BIO_new_CMS,CRYPTO_zalloc,crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16,0.993731,NoCheck,,
75,43,i2d_ASN1_bio_stream,CRYPTO_zalloc,crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16,0.993731,NoCheck,,
75,44,i2d_ASN1_bio_stream,CRYPTO_zalloc,crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16,0.993731,NoCheck,,
75,45,i2d_ASN1_bio_stream,CRYPTO_zalloc,crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16,0.993731,NoCheck,,
... (and a lot more)
```

We process it to get only unique locations:

```
crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16
crypto/async/async_wait.c:ASYNC_WAIT_CTX_new:17:12
crypto/evp/digest.c:EVP_MD_CTX_new:75:12
crypto/evp/evp_enc.c:EVP_CIPHER_CTX_new:63:12
crypto/evp/exchange.c:evp_keyexch_new:21:29
crypto/evp/keymgmt_lib.c:allocate_params_space:80:12
crypto/evp/keymgmt_lib.c:paramdefs_to_params:26:14
crypto/evp/pmeth_fn.c:evp_signature_new:21:32
crypto/mem_sec.c:CRYPTO_secure_zalloc:141:12
crypto/o_str.c:OPENSSL_buf2hexstr:242:16
crypto/sparse_array.c:OPENSSL_SA_new:65:23
providers/implementations/digests/blake2_prov.c:blake2b512_newctx:40:1
providers/implementations/digests/blake2_prov.c:blake2s256_newctx:35:1
providers/implementations/digests/md5_prov.c:md5_newctx:16:1
providers/implementations/digests/md5_sha1_prov.c:md5_sha1_newctx:48:1
providers/implementations/digests/sha2_prov.c:sha1_newctx:49:1
providers/implementations/digests/sha2_prov.c:sha224_newctx:55:1
providers/implementations/digests/sha2_prov.c:sha256_newctx:61:1
providers/implementations/digests/sha2_prov.c:sha384_newctx:67:1
providers/implementations/digests/sha2_prov.c:sha512_224_newctx:79:1
providers/implementations/digests/sha2_prov.c:sha512_256_newctx:85:1
providers/implementations/digests/sha2_prov.c:sha512_newctx:73:1
providers/implementations/digests/sm3_prov.c:sm3_newctx:16:1
providers/implementations/exchange/dh_exch.c:dh_newctx:40:12
```

There must be false positives among these bug alarms, so we manually go into them.

| Location | Link | Is True Bug? |
|----------|------|--------------|
| crypto/asn1/bio_ndef.c:BIO_new_NDEF:64:16 |	[link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/asn1/bio_ndef.c#L64) | False |
| crypto/async/async_wait.c:ASYNC_WAIT_CTX_new:17:12 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/async/async_wait.c#L17) | False |
| crypto/evp/digest.c:EVP_MD_CTX_new:75:12 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/evp/digest.c#L75) | False |
| crypto/evp/evp_enc.c:EVP_CIPHER_CTX_new:63:12 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/evp/evp_enc.c#L63) | False |
| crypto/evp/exchange.c:evp_keyexch_new:21:29 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/evp/exchange.c#L21) | True |
| crypto/evp/keymgmt_lib.c:allocate_params_space:80:12 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/evp/keymgmt_lib.c#L80) | True |
| crypto/evp/keymgmt_lib.c:paramdefs_to_params:26:14 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/evp/keymgmt_lib.c#L26) | True |
| crypto/evp/pmeth_fn.c:evp_signature_new:21:32 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/evp/pmeth_fn.c#L21) | True |
| crypto/mem_sec.c:CRYPTO_secure_zalloc:141:12 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/mem_sec.c#L141) | ??? |
| crypto/o_str.c:OPENSSL_buf2hexstr:242:16 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/o_str.c#L242) | True |
| crypto/sparse_array.c:OPENSSL_SA_new:65:23 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/crypto/sparse_array.c#L65) | False (because function is not used) |
| providers/implementations/digests/blake2_prov.c:blake2b512_newctx:40:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/blake2_prov.c#L40) | Unknown |
| providers/implementations/digests/blake2_prov.c:blake2s256_newctx:35:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/blake2_prov.c#L35) | Unknown |
| providers/implementations/digests/md5_prov.c:md5_newctx:16:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/md5_prov.c#L16) | Unknown |
| providers/implementations/digests/md5_sha1_prov.c:md5_sha1_newctx:48:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/md5_sha1_prov.c#L48) | Unknown |
| providers/implementations/digests/sha2_prov.c:sha1_newctx:49:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sha2_prov.c#L49) | Unknown |
| providers/implementations/digests/sha2_prov.c:sha224_newctx:55:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sha2_prov.c#L55) | Unknown |
| providers/implementations/digests/sha2_prov.c:sha256_newctx:61:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sha2_prov.c#L61) | Unknown |
| providers/implementations/digests/sha2_prov.c:sha384_newctx:67:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sha2_prov.c#L67) | Unknown |
| providers/implementations/digests/sha2_prov.c:sha512_224_newctx:79:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sha2_prov.c#L79) | Unknown |
| providers/implementations/digests/sha2_prov.c:sha512_256_newctx:85:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sha2_prov.c#L85) | Unknown |
| providers/implementations/digests/sha2_prov.c:sha512_newctx:73:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sha2_prov.c#L73) | Unknown |
| providers/implementations/digests/sm3_prov.c:sm3_newctx:16:1 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/digests/sm3_prov.c#L16) | Unknown |
| providers/implementations/exchange/dh_exch.c:dh_newctx:40:12 | [link](https://github.com/openssl/openssl/blob/0a4d6c67480a4d2fce514e08d3efe571f2ee99c9/providers/implementations/exchange/dh_exch.c#L40) | False (because function is not used) |

Here's some more explanation about the last column "Is True Bug":

- True: That means this is a true bug. If you click into the link, you will see that the return value of `CRYPTO_zalloc` (or `OPENSSL_zalloc`, since this is just a macro) is not checked before it's used.
- False: That means this bug alarm is a false positive. There are several possibilities
  - The caller function is not called by something else. That means when we trace back the entry function, there's empty. As an example,
    ``` c
    char *OBJ_new() {
      return (char *) CRYPTO_zalloc(sizeof(char) * 10);
    }
    ```
    and let's suppose that this `OBJ_new` function is not called by anything else, the entry function of the current slice will be `OBJ_new`. And therefore, of course, the result of `CRYPTO_zalloc` is not checked, resulting in a false positive
  - The check is "too" far from the call-site. As an example,
    ``` c
    void entry() {
      // ...
      p = CRYPTO_zalloc(sizeof(char) * 10);
      some_function();
      if (p == 0) {
        // ...
      }
    }
    ```
    Here, inbetween `p = CRYPTO_zalloc(...)` and `if (p == 0)` there is a `some_function()`. Our symbolic executor will need to go into that `some_function` and if there are too many instructions inside that `some_function`, we will stop the symbolic execution. In that case, we are not able to see the `if (p == 0)` part, hence result in a false positive.
- Unknown: The implementation detail is hidden inside a macro. Therefore we are unable to confirm the bug. Whether it is a false positive is unknown.

## Conclusion

Our analyzer with only "return value checker" can detect bugs of `CRYPTO_zalloc` in OpenSSL. Although our testing version of OpenSSL is a little old (Oct 08, 2019), some of the bugs are still presenting today. We submitted issues for OpenSSL: [here](https://github.com/openssl/openssl/issues/10525) and [here](https://github.com/openssl/openssl/issues/10283). That concludes our study today!