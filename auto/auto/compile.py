from .meta import Repo, Pkg, PkgSrcType, Build, BuildType, BuildResult

from typing import List, Optional

from optparse import OptionParser
from optparse import Values

import sys
import os
import subprocess
import traceback

options = Values()  # type: Values


class BuildException(Exception):
    pass


class BuildEnv:
    def __init__(self):
        self.env = os.environ.copy()
        self.env["LLVM_COMPILER"] = "clang"
        self.env["CC"] = "wllvm"
        self.env["CXX"] = "wllvm++"
        self.env["CFLAGS"] = "-g -O1"


def exists(path: str, files: List[str]) -> Optional[str]:
    for f in files:
        if os.path.exists(os.path.join(path, f)):
            return f
    return None


def find_build(repo: Repo, pkg: Pkg):
    print(repo.pkg_path(pkg))
    if exists(repo.pkg_path(pkg), ["configure", "config"]) is not None:
        pkg.build = Build(BuildType.config)
    elif os.path.exists(os.path.join(repo.pkg_path(pkg), "Makefile")):
        pkg.build = Build(BuildType.makeonly)
    elif pkg.pkg_src.src_type == PkgSrcType.aptget:
        pkg.build = Build(BuildType.dpkg)
    else:
        pkg.build = Build(BuildType.unknown)


def run_make(repo: Repo, pkg: Pkg):
    # Try a re-fetch and clean build with make
    print("building {} with configure/make".format(pkg.name))

    env = BuildEnv()

    # TODO: Incorporate this into BuildTypes enum
    config_file = exists(repo.pkg_path(pkg), ["configure", "config"])
    if config_file is None:
        raise BuildException("should never happen")

    if pkg.build.build_type == BuildType.config:
        run = subprocess.run(["./" + config_file],
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.STDOUT,
                             cwd=repo.pkg_path(pkg),
                             env=env.env)
        if run.returncode != 0:
            raise BuildException("configure failed")

    run = subprocess.run(['make', '-j32'],
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.STDOUT,
                         cwd=repo.pkg_path(pkg),
                         env=env.env)
    if run.returncode != 0:
        raise BuildException("configure failed")


def build_pkg(repo: Repo, pkg: Pkg):
    if pkg.build.build_type == BuildType.config or pkg.build.build_type == BuildType.makeonly:
        run_make(repo, pkg)
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
        bcs.append(l.decode('utf-8'))
    return bcs


def extract_bc(repo: Repo, pkg: Pkg):
    libs = find_libs(repo.pkg_path(pkg))
    if len(libs) == 0:
        pkg.build.result = BuildResult.nolibs
        raise BuildException("nolibs")
    for l in libs:
        # l is full path, fix
        so = l.split("/")[-1]

        run = subprocess.run(["extract-bc", so],
                             stderr=subprocess.STDOUT,
                             cwd=repo.pkg_path(pkg))
        if run.returncode != 0:
            pkg.build.result = BuildResult.nobc
            raise BuildException("nobc")
    bcs = find_bc(repo.pkg_path(pkg))
    if len(bcs) == 0:
        pkg.build.result = BuildResult.nobc
        raise BuildException("nobc")

    pkg.build.bc_files = bcs
    pkg.build.result = BuildResult.success


def build_repo(repo: Repo) -> bool:
    ec = True
    for _, p in repo.pkgs.items():
        try:
            find_build(repo, p)
            build_pkg(repo, p)
            extract_bc(repo, p)
        except BuildException as e:
            print(e)
            traceback.print_exc()
            ec = False
    return ec
