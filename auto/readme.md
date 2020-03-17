# Running

# driver

See data/github.json for input into the fetch step. The following will pull down openssl from github, and create a repo in `out`. The driver will also
attempt to build the repository, but in the future I will make it easier to split these.

```
PYTHONPATH=. bin/driver -d out -p data/github.json
```

Inside our repo, you will see a repo.json. This will contain complete information out everything in our automation (think repository of built source files etc.)


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

# tester

The tester helps test each individual module. I will continue to split this out to better make sure everything works, but for now, run the following (which is a little
redudent as a fetch is required for a compile.)

```
PYTHONPATH=. pytest test/
```
