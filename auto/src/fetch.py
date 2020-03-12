from meta import *

import json
import sys
import os.path

from optparse import OptionParser

options = {} # type: ignore

def read_package_json(repo: Repo, path: str):
    with open(path) as f:
        for l in f:
            j = json.loads(l)
            pkg = Pkg.from_json(j)
            repo.add(pkg)

if __name__ == "__main__":
    usage = "usage: %prog [options] package-json"
    parser = OptionParser(usage=usage)
    parser.add_option('-d', '--dir', dest='dir', default='out', help='use DIR as working output directory', metavar='DIR')

    (options, args) = parser.parse_args() # type: ignore

    if len(args) < 1:
        print("error: supply package-json")
        sys.exit(1)

    repo = Repo()
    read_package_json(repo, args[0]) 
