import subprocess
import shutil

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


def fetch_debian_repo(db: Database, pkg: Pkg):
    pkg_dir = db.package_dir(pkg)

    run = subprocess.run(['apt-get', 'source', pkg.pkg_src.link], stderr=subprocess.STDOUT, cwd=pkg_dir)

    # Better for use to create some exception common to all processing and throw that
    # one level up so we don't handle multiple times
    if run.returncode != 0:
        print("error: could not fetch {}".format(pkg.name))
        return None

    extracted_dir = ""
    for p in os.listdir(pkg_dir):
        if os.path.isdir(os.path.join(pkg_dir, p)):
            extracted_dir = p
            break

    if extracted_dir == "":
        print("error: could not find extracted directory in {}".format(deb_dir))
        return None

    os.rename(f"{pkg_dir}/{extracted_dir}", f"{pkg_dir}/source")

    return pkg_dir


def fetch_pkg(db: Database, pkg: Pkg):
    print(f"Fetching {pkg.name}")
    t = pkg.pkg_src.src_type
    path = None
    if t == PkgSrcType.github:
        path = fetch_github_repo(db, pkg)
    elif t == PkgSrcType.debian:
        path = fetch_debian_repo(db, pkg)
    elif t == PkgSrcType.direct:
        print("Warning: direct unimplemented")
        pass
    else:
        print(f"Warning: unrecognized package source {t}")

    if path is not None:
        pkg.fetched = True
        pkg.pkg_dir = path
