# Dec 20, 2019 Experiment Result

## Process

As in the experiment [here](11_25_19_libcrypto.md), we first need to generate the traces using our Extractor. To simplify the process in that document, we do the following. Assuming you have the library `OPENSSL` compiled using `wllvm`,

```
$ ./llextractor -fn CRYPTO_zalloc -n 1 /PATH/TO/OPENSSL/LIB/libcrypto.so.3.bc -outdir /data1/liby99/ll_extractor_result/12_15_19/libcrypto_CRYPTO_zalloc_n_1
```

With the data of `libcrypto_CRYPTO_zalloc_n_1` from our `llextractor`, we have run the machine learning model with simple GNN and OC-SVM. We used following parameters:

- `--lambd`: 0.01
- `--n_epochs`: 500

To run the model, go to https://github.com/petablox/api-misuse, setup the repo (please use Anaconda), and run the following commands to setup the data directories. Note that we are using `ln -s` to create softlinks instead of copying the whole thing.

``` bash
$ mkdir data
$ pushd data
$ ln -s /data1/liby99/ll_extractor_result/12_15_19/libcrypto_CRYPTO_zalloc_n_1 libcrypto_CRYPTO_zalloc_n_1
$ popd
```

To train and eval the model, do this:

```
$ python train.py --data_folder libcrypto_CRYPTO_zalloc_n_1 --n_epochs 500 --lambd 0.01
$ python eval.py --n_outliers 30 --data_folder libcrypto_CRYPTO_zalloc_n_1
```

## Result

After that you should be able to see the following result.

```
root        : INFO     Initializing graphnn: embed_dim=16
root        : INFO     Initializing w: shape=torch.Size([16])
root        : INFO     Initializing r: shape=torch.Size([])
root        : INFO     Node feature input: dimension=47
root        : INFO     [Outlier 0] [score: -0.084019] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-5-dugraph.json: 0]
root        : INFO     [Outlier 1] [score: -0.084019] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-3-dugraph.json: 0]
root        : INFO     [Outlier 2] [score: -0.077550] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-513-dugraph.json: 49]
root        : INFO     [Outlier 3] [score: 0.000000] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-859-dugraph.json: 20]
root        : INFO     [Outlier 4] [score: 0.000000] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-876-dugraph.json: 1]
root        : INFO     [Outlier 5] [score: 0.000000] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-894-dugraph.json: 49]
root        : INFO     [Outlier 6] [score: 0.000000] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-892-dugraph.json: 49]
root        : INFO     [Outlier 7] [score: 0.000000] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-873-dugraph.json: 1]
root        : INFO     [Outlier 8] [score: 0.016224] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-873-dugraph.json: 0]
root        : INFO     [Outlier 9] [score: 0.028182] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-400-dugraph.json: 49]
root        : INFO     [Outlier 10] [score: 0.030285] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-797-dugraph.json: 22]
root        : INFO     [Outlier 11] [score: 0.030285] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-798-dugraph.json: 22]
root        : INFO     [Outlier 12] [score: 0.044473] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-681-dugraph.json: 48]
root        : INFO     [Outlier 13] [score: 0.048202] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-872-dugraph.json: 48]
root        : INFO     [Outlier 14] [score: 0.048202] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-887-dugraph.json: 48]
root        : INFO     [Outlier 15] [score: 0.051584] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-358-dugraph.json: 44]
root        : INFO     [Outlier 16] [score: 0.053152] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-858-dugraph.json: 48]
root        : INFO     [Outlier 17] [score: 0.053167] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-89-dugraph.json: 2]
root        : INFO     [Outlier 18] [score: 0.053167] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-91-dugraph.json: 2]
root        : INFO     [Outlier 19] [score: 0.053167] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-90-dugraph.json: 2]
root        : INFO     [Outlier 20] [score: 0.053167] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-88-dugraph.json: 2]
root        : INFO     [Outlier 21] [score: 0.053167] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-92-dugraph.json: 2]
root        : INFO     [Outlier 22] [score: 0.053167] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-87-dugraph.json: 2]
root        : INFO     [Outlier 23] [score: 0.053402] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-681-dugraph.json: 49]
root        : INFO     [Outlier 24] [score: 0.053407] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-877-dugraph.json: 48]
root        : INFO     [Outlier 25] [score: 0.053578] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-399-dugraph.json: 49]
root        : INFO     [Outlier 26] [score: 0.054287] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-495-dugraph.json: 48]
root        : INFO     [Outlier 27] [score: 0.055368] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-876-dugraph.json: 0]
root        : INFO     [Outlier 28] [score: 0.055982] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-886-dugraph.json: 48]
root        : INFO     [Outlier 29] [score: 0.058220] [location: ./data/libcrypto_CRYPTO_zalloc_n_1/dugraphs/CRYPTO_zalloc-523-dugraph.json: 48]
```

## Observation

1. How to interpret the result?

There are 30 rows here because we tell the evaluator to give us 30 outliers. The evaluator will
generate scores for outliers and it will give us the lowest ones.

Each row represents the evaluation result of a single Trace. Note that a trace can be identified
using "Slice ID" and "Trace ID". That is represented in the later part of each row. The number
inside the `location` (e.g. `...CRYPTO_zalloc-5-dugraph.json`) represent the `slice_id`. And the
last number of each row represents the `trace_id`.

Score: The lower the score is, the more likely it will be a bug. It's sometimes rare for a "trace"
to have negative score but there might be. If so then it is a strong signal that it is being
detected as an outlier.

2. Given the following Ground Truth Label of bugs within this dataset, our ML model detected 2 bugs
   with strong signals

``` csv
Slice Id,Entry,Function,Location,Score,Result
3,siphash_new,CRYPTO_zalloc,siphash_new:0:0,0.996314,"NoCheck"
5,poly1305_new,CRYPTO_zalloc,poly1305_new:0:0,0.996314,"NoCheck"
308,i2v_AUTHORITY_KEYID,CRYPTO_zalloc,../crypto/o_str.c:OPENSSL_buf2hexstr:242:16,0.996314,"NoCheck"
309,ERR_print_errors_cb,CRYPTO_zalloc,../crypto/o_str.c:OPENSSL_buf2hexstr:242:16,0.996314,"NoCheck"
355,evp_signature_from_dispatch,CRYPTO_zalloc,../crypto/evp/pmeth_fn.c:evp_signature_new:21:32,0.996314,"NoCheck"
380,evp_keyexch_from_dispatch,CRYPTO_zalloc,../crypto/evp/exchange.c:evp_keyexch_new:21:29,0.996314,"NoCheck"
```

These are the bugs we detected using our Analyzer. We observe that slices `3` and `5` are both 
appeared in the ML prediction.

3. None of the other bugs in our Ground Truth set appears in the top 30 predictions

We still need to figure out what actually causes the ML model to detect slices 3 and 5.
