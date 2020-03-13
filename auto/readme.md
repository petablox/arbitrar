# Running

## Fetch

See test/test.json for input into the fetch step. The following will pull down openssl from github, and create a repo in `out`.

```
python src/fetch.py -d out test/test.json
```

Inside our repo, you will see a repo.json. This will contain complete information out everything in our automation (think repository of built source files etc.)

## Compile

Run a compile on a repo.json. This will attempt to figure out how to build packages in the repo, build them, and then extract bitcode.

```
python src/compile out/repo.json
```

Let the code actually load the json into our datastructures to manipulate (see src/meta.py) but expect json to look like the following:

```
{
  "main_dir": "out", 
  "pkgs": [
   {
      "name": "opensll", 
      "pkg_src": 
      {
        "src_type": "github", 
        "link": "https://github.com/openssl/openssl.git"
      }, 
      "fetched": true, 
      "pkg_dir": "opensll", 
      "build": 
      {
        "build_type": "config", 
        "build_dir": "", 
        "result": "success", 
        "bc_files": ["out/opensll/engines/.capi-dso-e_capi.o.bc", ...]
      }
  }
}
```
