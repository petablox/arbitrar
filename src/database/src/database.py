from enum import Enum
from typing import List

import os
import json

from .package import *


class Database:
    directory: str
    packages: List[Pkg]

    def __init__(self, directory: str):
        self.directory = directory
        self.setup_file_system()
        self.setup_indices()

    def setup_file_system(self):
        # Create the directory if not existed
        if not os.path.exists(self.directory):
            os.mkdir(self.directory)

        # Create the packages directory
        self.setup_packages_file_system()

    def setup_packages_file_system(self):
        d = self.packages_dir()
        if not os.path.exists(d):
            os.mkdir(d)

    def setup_indices(self):
        self.setup_packages_indices()

    def setup_packages_indices(self):
        packages_dir = self.packages_dir()
        self.packages = []
        for d in os.listdir(packages_dir):
            pkg_dir = f"{packages_dir}/{d}"
            pkg_json_dir = f"{pkg_dir}/index.json"
            if os.path.exists(pkg_json_dir):
                with open(pkg_json_dir) as f:
                    j = json.load(f)
                    self.packages.append(Pkg.from_json(j))

    def packages_dir(self) -> str:
        return f"{self.directory}/packages"

    def contains_package(self, package_name: str) -> bool:
        for pkg in self.packages:
            if pkg.name == package_name:
                return True
        return False

    def get_package(self, package_name: str) -> Pkg:
        for pkg in self.packages:
            if pkg.name == package_name:
                return pkg
        return None

    def add_package(self, pkg: Pkg):
        with open(self.package_index_json_dir(pkg), 'w') as f:
            f.write(json.dumps(Pkg.to_json(pkg)))
        for i in range(len(self.packages)):
            if self.packages[i].name == pkg.name:
                self.packages[i] = pkg
                return
        self.packages.append(pkg)

    def package_dir(self, pkg: Pkg) -> str:
        d = f"{self.packages_dir()}/{pkg.name}"
        if not os.path.exists(d):
            os.mkdir(d)
        return d

    def package_source_dir(self, pkg: Pkg) -> str:
        pkg_dir = self.package_dir(pkg)
        d = f"{pkg_dir}/source"
        return d

    def package_index_json_dir(self, pkg: Pkg) -> str:
        return f"{self.package_dir(pkg)}/index.json"
