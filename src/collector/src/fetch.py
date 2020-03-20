import subprocess

from .. import *


def fetch_github_repo(db: Database, pkg: Pkg):
    pkg_dir = db.package_dir(pkg)
    run = subprocess.run(
        ['git', 'clone', pkg.pkg_src.link, "source", "--depth", "1"],
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
