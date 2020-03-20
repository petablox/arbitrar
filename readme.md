# Unsupervised API Misuse

TODO: Intros here

## How to use

``` bash
./misapi collect <repo.json>       # Fetch & Compile & Analyze
./misapi add <repo.json>           # Collect & Analyze repo
./misapi analyze <repo_name>       # Analyze <repo_name>
./misapi info -f <func_name>       # Get the information of <func_name>
./misapi info -r <repo_name>       # Get the information of <repo_name>
./misapi unsup <func_name>         # Do unsupervised learning on <func_name>
```

## Requirements

```
$ make setup
```

## Build & Install

```
$ make build
```