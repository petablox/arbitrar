# Analyzer Output

Analyzer will take a directory as input. That directory should contain

```
/slices.json
/dugraphs/<FUNCTION>-<N>-dugraph.json
```

Analyzer will first read the `slices.json` and determine which file it should look into
in the `/dugraphs` folder.

Analyzer will create a directory in the input directory, and output these files:

```
/analysis/log.txt
/analysis/<CHECKER>/<FUNCTION>-results.csv
/analysis/<CHECKER>/stats.txt
/analysis/<CHECKER>/bugs.txt
```

### `log.txt`

In `log.txt`, there will contain the logs and output from the analyzer

### `<CHECKER>/stats.txt`

In `stats.txt`, there will be format like this

```
Function CRYPTO_zalloc:
Total: 850
Checked eq      0       828
Checked eq      45      1
Checked ugt     32      15
Checked slt     1       6
Function malloc:
Total: 3
Checked eq      0       3
```

containing all the function informations

### `<CHECKER>/bugs.txt`