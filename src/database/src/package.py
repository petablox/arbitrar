from enum import Enum
from typing import Dict, List

class PkgSrcType(Enum):
    github = "github"
    aptget = "aptget"
    direct = "direct"


class PkgSrc:
    @staticmethod
    def from_json(j):
        pkg_src_type = PkgSrcType(j["src_type"])
        return PkgSrc(pkg_src_type, j["link"])

    @staticmethod
    def to_json(p):
        return {"src_type": p.src_type.value, "link": p.link}

    def __init__(self, src_type: PkgSrcType, link: str):
        self.src_type = src_type
        self.link = link


class BuildType(Enum):
    config = "config"       # Standard config/make
    makeonly = "makeonly"   # Some make builds dont have config
    dpkg = "dpkg"           # dpkg-buildpackage, used by a lot of debian source packages
    unknown = "unknown"     # we dont kknow


class BuildResult(Enum):
    notbuilt = "notbuilt"   # Haven't built yet
    failed = "failed"       # Build fails
    compiled = "compiled"   # Compiled, but nothing else checked
    nolibs = "nolibs"       # Build succeeds, but not librarys found for analysis
    nobc = "nobc"           # Build succeeds, but can't generate LLVM bitcode
    success = "success"     # Complete succes


class Build:
    @staticmethod
    def from_json(j):
        build_type = BuildType(j["build_type"])
        build_dir = j["build_dir"] if "build_dir" in j else ""
        result = BuildResult(j["result"]) if "result" in j else BuildResult.notbuilt
        libs = j["libs"] if "libs" in j else []
        bc_files = j["bc_files"] if "bc_files" in j else []
        return Build(build_type, build_dir, result, libs, bc_files)

    @staticmethod
    def to_json(b):
        return {"build_type": b.build_type.value, "build_dir": b.build_dir, "result": b.result.value, "libs": b.libs, "bc_files": b.bc_files}

    def __init__(self, build_type: BuildType, build_dir: str = "", result: BuildResult = BuildResult.notbuilt, libs: List[str] = [], bc_files: List[str] = []):
        self.build_type = build_type
        self.build_dir = build_dir
        self.result = result
        self.libs = libs
        self.bc_files = bc_files


class Pkg:
    @staticmethod
    def from_json(j):
        pkg_src = PkgSrc.from_json(j["pkg_src"])
        fetched = j["fetched"] if "fetched" in j else False
        pkg_dir = j["pkg_dir"] if "pkg_dir" in j else None
        build = Build.from_json(j["build"]) if "build" in j else Build(BuildType.unknown)
        return Pkg(j["name"], pkg_src, fetched, pkg_dir, build)

    @staticmethod
    def to_json(p):
        return {
            "name": p.name,
            "pkg_src": PkgSrc.to_json(p.pkg_src),
            "fetched": p.fetched,
            "pkg_dir": p.pkg_dir,
            "build": Build.to_json(p.build)
        }

    def __init__(self, name: str, pkg_src: PkgSrc, fetched: bool, pkg_dir: str, build: Build):
        self.name = name
        self.pkg_src = pkg_src
        self.fetched = fetched
        self.pkg_dir = pkg_dir
        self.build = build

    def is_fetched(self) -> bool:
        return self.fetched

    def is_built(self) -> bool:
        return self.build.result == BuildResult.success
