#!/bin/bash

from enum import Enum

class PkgSrcType(Enum):
    github="github"
    aptget="aptget"
    direct="direct"

class PkgSrc:
    def from_json(j):
        pkg_src_type = PkgSrcType(j["src_type"])
        return PkgSrc(pkg_src_type, j["link"])

    def __init__(self, src_type: PkgSrcType, link: str):
        self.src_type = src_type
        self.link = link 

class BuildType(Enum):
    config=1 # Standard config/make
    dpkg=2 # dpkg-buildpackage, used by a lot of debian source packages

class Pkg:
    def from_json(j):
        pkg_src = PkgSrc.from_json(j["pkg_src"])
        return Pkg(j["name"], pkg_src)

    def __init__(self, name: str, pkg_src: PkgSrc):
        self.name = name
        self.pkg_src = pkg_src 
        self.fetched = False
        self.dir = None

class Repo:
    def __init__(self):
        self.pkgs = {}

    def add(self, pkg: Pkg):
        self.pkgs[pkg.name] = pkg 
