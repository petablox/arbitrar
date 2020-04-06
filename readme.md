# API Misuse Detection

This project aims to do data driven API Misuse Detection, tackling the problem in both learning and
synthesis perspective, with purely unsupervised or semi-supervised setting. This project is divided
into several parts:

1. Data Collection - fetching real-life projects and compile
2. Static Analysis - using traditional PL technique to do slicing and symbolic execution
3. Learning - use machine learning methods to detect API Misuses
4. Synthesis (TODO)

## Build

### Docker

The Data Collection framework of this project requires Linux/Ubuntu environment and the user needs
to have root access. Therefore it's the best if we can use Docker Image. We prepared the docker
image for you to play with:

```
cd docker/
docker build -f Dockerfile.bionic.x11forwarding -t petablox/api-misuse .
docker run -p 2020:22 -v ~/.ssh:/home/aspire/.ssh -d --name apimisuse petablox/api-misuse
docker exec -it apimisuse bash
```

The default user is `aspire` and the password is `ai4code`.

When you first run the docker container, please be sure to execute the following scripts:

```
# Inside user aspire's home directory
./install-ll-analyzer.sh
./install-llvm.sh
./setup-wllvm.sh
```

For more detailed instruction on how to do Docker please refer to
[docker/README.md](docker/README.md).

### Build

The project contains OCaml part and Python part. We have to do compilation for OCaml code. It is
done as simple as

```
make
```

## How to use

The project is currently divided into data collection, analysis and learning parts. The data
collection part can build a project database. Then the analyzer will come to fill the database with
analyzed results (slices, traces, etc.) And finally the learning algorithm will kick in with all the
analyzed data we get in the previous stages.

### Data Collection

The file [sample/repos.json](sample/repos.json) contains some predefined packages that is used in
our work. You'll see something like this:

``` json
[{
  "name": "openssl",
  "pkg_src": {
    "src_type": "github",
    "link": "https://github.com/openssl/openssl.git"
  }
}, {
  "name": "libcurl",
  "pkg_src": {
    "src_type": "debian",
    "link": "libcurl4"
  }
}]
```

With this file in hand, we can run

```
./misapi collect sample/repos.json
```

This is telling our API Misuse Detector to collect all the projects listed in the `repos.json`, in
the above case, it will collect the two projects: `openssl` and `libcurl`. Notice that the project
`openssl` comes from a github link while the second `libcurl` comes from Debian package repository.
After fetch, our system will automatically detect which method to use to compile these packages.

The following will happen:

- OpenSSL: The program will pull OpenSSL from the github link, and since configure and makefile are
  detected, it will use configure and make to build the package.
- libcurl: The program will use apt-get to fetch the package, and Debian build system to compile
  the library. It's very likely that you will need to type the password (`ai4code`) to progress,
  since the Debian build system will require root priviledge.

The output directory will be by default `data/` folder in the folder you run the above command. So
you should be seeing some folder structure like the following. The package source code will be
inside the `source/` folder under each project.

```
data/
- analysis/
  - ...
- packages/
  - libcurl/
    - source/
    - index.json
    - ...
  - openssl/
    - source/
    - index.json
    - ...
- ...
```

If the execution succeeded, you can type the following command to see the status of the
packages:

```
./misapi query packages
```

You should be seeing this output as a result:

```
Name            Fetch Status    Build Status
openssl         fetched         success
libcurl         fetched         success
```

If we check the output of the compilation process, it should produce multiple `.bc` files which are
LLVM byte codes. You can checkout the `.bc` files using the following command:

```
./misapi query bc-files
```

You should be seeing the following:

```
/home/aspire/ll_analyzer/data/packages/openssl/source/libcrypto.so.3.bc
/home/aspire/ll_analyzer/data/packages/openssl/source/libssl.so.3.bc
/home/aspire/ll_analyzer/data/packages/libcurl/source/libcurl.so.4.bc
```

`libcrypto.so.3.bc` and `libssl.so.3.bc` come from the package `OpenSSL` and the `libcurl.so.4.bc`
comes from the package `libcurl`. In the next step (analyzing) we will rely on these files to do the
analysis.

### Static Analysis

To analyze all the packages in the database, we can do it with the following command:

```
./misapi analyze
```

Analysis is done in a per `.bc` file basis. And the progress is saved along the way. For each `.bc`
file it encounters, it will do the analysis on that file. Within a single file, the progress
contains

1. Occurrence Extraction
2. Slicing/Symbolic Execution
3. Feature Extraction

When each of these finished, the progress will be saved. There are more command line arguments that
could be associated with the command `analyze`.

The output will be a folder structured like the following:

```
data/
- analysis/
  - occurrence/
    - <bc_file>.json
  - slices/
    - <function>/
      - <bc_file>/
        - <slice_id>.json
  - dugraphs/
    - <function>/
      - <bc_file>/
        - <slice_id>/
          - <trace_id>.json
  - features/
    - <function>/
      - <bc_file>/
        - <slice_id>/
          - <trace_id>.json
- ...
```

#### Specify `.bc` file

Analysis is done in a per `.bc` file basis. We can do

```
./misapi analyze --bc libcrypto
```

This command will analyze all the `.bc` files with `"libcrypto"` inside of it. In our case it's that
`libcrypto.so.3.bc` from OpenSSL.

#### `--min-freq`

It might also be better if we can have a filter of functions. Because most projects contain utility
functions that are only used once. We shouldn't be analyzing these functions since there are too few
of their usages. Here's a criteria called "min frequency". If it is set to 10, then a function will
only be analyzed if it occurred more than 10 static times in a package.

You can use this argument like this:

```
./misapi analyze --bc libssl --min-freq 10
```

#### `--redo`

The analysis will save progress as things go. If the analysis is already done, we will skip the
analysis next time to save time. If you want to change the analysis hyper-parameters, or you've
changed the code of analyzer, you need to completely redo the whole analysis. In that case, please
add this `--redo` argument to redo the analysis.

```
./misapi analyze --bc libssl --redo
```

#### `--redo-feature`

Sometimes you only want to redo the feature extraction step. In this case, you can

```
./misapi analyze --bc libssl --redo-feature
```

### Learning

The learning algorithm will perform in a per-function basis. Ideally we should generate a checker
for each API function. The learning will go to all the traces generated from that function, and try
to find outliers. This can be done within this simple command

```
./misapi learn openssl_fopen
```

The above command will learn the usages of function `openssl_fopen`, and report to you the anomaly
usages of it.
