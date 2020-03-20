from typing import List

import json
import subprocess

from ..database import *

def load_input(args):
    with open(f"{args.cwd}/{args.packages}") as f:
        pkgs_json = json.load(f)
        return [Pkg.from_json(j) for j in pkgs_json]
    return None

def fetch_github_repo(db: Database, pkg: Pkg):
    pkg_dir = db.package_dir(pkg)
    run = subprocess.run(
        ['git', 'clone', pkg.pkg_src.link, "source"],
        stdout=subprocess.PIPE,
        cwd=pkg_dir)

    # Better for use to create some exception common to all processing and throw that
    # one level up so we don't handle multiple times
    if run.returncode != 0:
        print("error: could not fetch {}".format(pkg.name))
        return None

    return pkg_dir

def fetch_pkg(db: Database, pkg: Pkg):
    print(f"Fetching {pkg.name}")
    t = pkg.pkg_src.src_type
    path = None
    if t == PkgSrcType.github:
        path = fetch_github_repo(db, pkg)
    elif t == PkgSrcType.aptget:
        print("warning: aptget unimplemented")
        pass
    elif t == PkgSrcType.direct:
        print("warning: direct unimplemented")
        pass
    else:
        print("warning: unrecognized package source {}".format(t))

    if path is not None:
        pkg.fetched = True
        pkg.pkg_dir = path

def compile_pkg(db: Database, pkg: Pkg):
    print(f"Compiling {pkg.name}")

def process_pkg(db: Database, pkg: Pkg):
    if not db.contains_package(pkg.name):
        fetch_pkg(db, pkg)
        compile_pkg(db, pkg)
        db.add_package(pkg)
    else:
        stored_pkg = db.get_package(pkg.name)
        if not stored_pkg.is_fetched():
            fetch_pkg(db, pkg)
        else:
            print(f"Skipping fetching step of {pkg.name}")
        if not stored_pkg.is_built():
            compile_pkg(db, pkg)
        else:
            print(f"Skipping building step of {pkg.name}")
        db.add_package(pkg)

def main(args):
    db : Database = args.db
    pkgs : List[Pkg] = load_input(args)
    for pkg in pkgs:
        process_pkg(db, pkg)