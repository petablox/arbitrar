from .meta import PkgSrcType, Pkg, Repo

import json
import sys
import os.path
import subprocess

from optparse import OptionParser
from optparse import Values


def fetch_github(repo: Repo, pkg: Pkg):
    run = subprocess.run(['git', 'clone', pkg.pkg_src.link, pkg.name], stdout=subprocess.PIPE, cwd=repo.main_dir)
    # Better for use to create some exception common to all processing and throw that
    # one level up so we don't handle multiple times
    if run.returncode != 0:
        print("error: could not fetch {}".format(pkg.name))
        return None
    return pkg.name


def fetch_pkg(repo: Repo, pkg: Pkg):
    t = pkg.pkg_src.src_type
    path = None
    if t == PkgSrcType.github:
        path = fetch_github(repo, pkg)
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
        fetch_pkg(repo, p)


def read_package_json(repo: Repo, path: str):
    with open(path) as f:
        for l in f:
            j = json.loads(l)
            pkg = Pkg.from_json(j)
            repo.add(pkg) 
