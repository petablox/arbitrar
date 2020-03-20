from typing import List, Optional

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

def exists(path: str, files: List[str]) -> Optional[str]:
    for f in files:
        if os.path.exists(os.path.join(path, f)):
            return f
    return None

def find_build(db: Database, pkg: Pkg):
    src_dir = db.package_source_dir(pkg)
    if exists(src_dir, ["configure", "config"]) is not None:
        pkg.build = Build(BuildType.config)
    elif exists(src_dir, ["Makefile", "makefile"]) is not None:
        pkg.build = Build(BuildType.makeonly)
    elif pkg.pkg_src.src_type == PkgSrcType.aptget:
        pkg.build = Build(BuildType.dpkg)
    else:
        pkg.build = Build(BuildType.unknown)

class BuildException(Exception):
    pass


class BuildEnv:
    def __init__(self):
        self.env = os.environ.copy()
        self.env["LLVM_COMPILER"] = "clang"
        self.env["CC"] = "wllvm"
        self.env["CXX"] = "wllvm++"
        self.env["CFLAGS"] = "-g -O1"

def get_soname(path):
    objdump = subprocess.Popen(['objdump', '-p', path], stdout=subprocess.PIPE)
    out = subprocess.run(['grep', 'SONAME'], stdout=subprocess.PIPE, stdin=objdump.stdout)
    if len(out.stdout) == 0:
        return None
    return out.stdout.strip().split()[-1].decode()


def soname_lib(libpath):
    soname = get_soname(libpath)
    if soname is None:
        soname = libpath.split("/")[-1]
    return soname


def run_make(db: Database, pkg: Pkg):
    src_dir = db.package_source_dir(pkg)

    # Try a re-fetch and clean build with make
    print("building {} with configure/make".format(pkg.name))

    env = BuildEnv()

    # TODO: Incorporate this into BuildTypes enum
    config_file = exists(src_dir, ["configure", "config"])
    if config_file is None:
        raise BuildException("should never happen")

    if pkg.build.build_type == BuildType.config:
        run = subprocess.run(["./" + config_file],
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.STDOUT,
                             cwd=src_dir,
                             env=env.env)
        if run.returncode != 0:
            raise BuildException("configure failed")

    run = subprocess.run(['make', '-j32'],
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.STDOUT,
                         cwd=src_dir,
                         env=env.env)
    if run.returncode != 0:
        raise BuildException("configure failed")


def build_pkg(db: Database, pkg: Pkg):
    if pkg.build.build_type == BuildType.config or pkg.build.build_type == BuildType.makeonly:
        run_make(db, pkg)
    else:
        raise BuildException("not yet implemented")
    pkg.build.result = BuildResult.compiled


def find_libs(path: str) -> List[str]:
    out = subprocess.run(['find', path, '-name', 'lib*.so*'], stdout=subprocess.PIPE)
    libs = []
    for l in out.stdout.splitlines():
        libs.append(l.decode('utf-8'))
    return libs


def find_bc(path: str) -> List[str]:
    out = subprocess.run(['find', path, '-name', '*.bc'], stdout=subprocess.PIPE)
    bcs = []
    for l in out.stdout.splitlines():
        bcs.append(l.decode())
    return bcs


def extract_bc(db: Database, pkg: Pkg):
    src_dir = db.package_source_dir(pkg)
    libs = find_libs(src_dir)
    if len(libs) == 0:
        pkg.build.result = BuildResult.nolibs
        raise BuildException("nolibs")

    sonames = set()
    for l in libs:
        sonames.add(get_soname(l))
    if len(sonames) == 0:
        pkg.build.result = BuildResult.nolibs
        raise BuildException("nolibs")
    pkg.build.libs = [soname for soname in list(sonames) if soname]

    for l in pkg.build.libs:
        if not os.path.exists(f"{src_dir}/{l}.bc"):
            run = subprocess.run(["extract-bc", l],
                                stderr=subprocess.STDOUT,
                                cwd=src_dir)
            if run.returncode != 0:
                pkg.build.result = BuildResult.nobc
                raise BuildException("nobc")
    bcs = find_bc(src_dir)
    if len(bcs) == 0:
        pkg.build.result = BuildResult.nobc
        raise BuildException("nobc")

    pkg.build.bc_files = bcs
    pkg.build.result = BuildResult.success

def compile_pkg(db: Database, pkg: Pkg):
    find_build(db, pkg)
    build_pkg(db, pkg)
    extract_bc(db, pkg)

def process_pkg(db: Database, pkg: Pkg):
    if not db.contains_package(pkg.name):
        fetch_pkg(db, pkg)
        compile_pkg(db, pkg)
        db.add_package(pkg)
    else:
        stored_pkg = db.get_package(pkg.name)
        if not stored_pkg.is_fetched():
            fetch_pkg(db, stored_pkg)
        if not stored_pkg.is_built():
            compile_pkg(db, stored_pkg)
        db.add_package(stored_pkg)

def main(args):
    db : Database = args.db
    pkgs : List[Pkg] = load_input(args)
    for pkg in pkgs:
        process_pkg(db, pkg)