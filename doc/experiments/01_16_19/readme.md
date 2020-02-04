```
./llextractor -n 1 -min-freq 10 ../unsup_laboratory/openssl/llvm_objs/libcrypto.so.3.bc -exclude "OPENSSL_cleanse|llvm\.|load_" -outdir /data1/liby99/ll_extractor_result/01_16_20/libcrypto_min_freq_10_n_1
```