from meta import PkgSrcType, Pkg, Repo

import json
import sys
import os.path
import subprocess

from optparse import OptionParser
from optparse import Values


options = Values()  # type: Values


def fetch_github(pkg: Pkg):
    run = subprocess.run(['git', 'clone', pkg.pkg_src.link, pkg.name], stdout=subprocess.PIPE, cwd=options.dir)
    # Better for use to create some exception common to all processing and throw that
    # one level up so we don't handle multiple times
    if run.returncode != 0:
        print("error: could not fetch {}".format(pkg.name))
        return None
    return pkg.name


def fetch_pkg(pkg: Pkg):
    t = pkg.pkg_src.src_type
    path = None
    if t == PkgSrcType.github:
        path = fetch_github(pkg)
    elif t == PkgSrcType.aptget:
        pass
    elif t == PkgSrcType.direct:
        pass
    else:
        print("warning: unrecognized package source {}".format(t))

    if path is not None:
        pkg.fetched = True
        pkg.pkg_dir = path


def fetch_repo(repo: Repo):
    for _, p in repo.pkgs.items():
        print("fetching {} using {}".format(p.name, p.pkg_src.src_type))
        fetch_pkg(p)


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

    (options, args) = parser.parse_args()

    if len(args) < 1:
        print("error: supply package-json")
        sys.exit(1)

    if not os.path.exists(options.dir):
        os.mkdir(options.dir)

    repo = Repo(options.dir)
    read_package_json(repo, args[0])

    fetch_repo(repo)

    if not repo.save():
        sys.exit(1)

    # Clean exit code so other scripts can check for success
    sys.exit(0)
