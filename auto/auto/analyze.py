from .meta import Repo, Pkg, PkgSrcType, Build, BuildType, BuildResult, Analysis

from typing import List, Optional

from optparse import OptionParser
from optparse import Values

import sys
import os
import subprocess
import traceback

options = Values()  # type: Values


class AnalyzeException(Exception):
    pass


def llextractor_cmd(bc, outdir):
    return ["llextractor", "-n", "1", "-include-fn", "malloc", "-output-dot", "-output-trace", "-pretty-json", "-outdir", outdir, bc]


def analyze_pkg(repo: Repo, pkg: Pkg):
    if pkg.build.result != BuildResult.success:
        raise AnalyzeException("attempting to analyze package " + pkg.name + " which did not build correctly")
    # TODO: I am assuming we only want to analyze the bc from shared libs. We will change this if necessary
    for l in pkg.build.libs:
        bc = os.path.join(repo.pkg_path(pkg), l + ".bc")
        if not os.path.exists(bc):
            raise AnalyzeException("no bc file for shared library {} at {}".format(l, bc))
        outdir = os.path.join(repo.data_path(pkg), l.split(".")[0])
        os.makedirs(outdir, exist_ok=True)
        run = subprocess.run(llextractor_cmd(bc, outdir),
                             stderr=subprocess.STDOUT)
        if run.returncode != 0:
            raise AnalyzeException("could not analyze " + pkg.name + " " + l)
        pkg.analysis.append(Analysis(l, outdir))
        

def analyze_repo(repo: Repo) -> bool:
    ec = True
    for _, p in repo.pkgs.items():
        try:
            analyze_pkg(repo, p)
        except AnalyzeException as e:
            print(e)
            traceback.print_exc()
            ec = False
    return ec
