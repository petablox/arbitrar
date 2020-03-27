from enum import Enum
from typing import List

import os
import json
import subprocess

from .package import *
from .analysis import *
from .utils import *

class Database:
    directory: str
    packages: List[Pkg]

    def __init__(self, directory: str):
        self.directory = directory
        self.setup_file_system()
        self.setup_indices()

    def setup_file_system(self):
        # Create the directory if not existed
        mkdir(self.directory)

        # Create the packages directory
        self.setup_packages_file_system()

        # Create the analysis directory
        self.setup_analysis_file_system()

        # Create temporary directory
        self.setup_temporary_file_system()

    def setup_packages_file_system(self):
        mkdir(self.packages_dir())

    def setup_analysis_file_system(self):
        mkdir(self.analysis_dir())
        mkdir(self.slices_dir())
        mkdir(self.dugraphs_dir())
        mkdir(self.features_dir())

    def setup_temporary_file_system(self):
        mkdir(self.temp_dir())

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

    def analysis_dir(self) -> str:
        return f"{self.directory}/analysis"

    def slices_dir(self) -> str:
        return f"{self.analysis_dir()}/slices"

    def func_slices_dir(self, func: str) -> str:
        return mkdir(f"{self.slices_dir()}/{func}")

    def func_bc_slices_dir(self, func: str, bc_name: str) -> str:
        return mkdir(f"{self.func_slices_dir(func)}/{bc_name}")

    def dugraphs_dir(self) -> str:
        return f"{self.analysis_dir()}/dugraphs"

    def func_dugraphs_dir(self, func: str) -> str:
        return mkdir(f"{self.dugraphs_dir()}/{func}")

    def func_bc_dugraphs_dir(self, func: str, bc_name: str) -> str:
        return mkdir(f"{self.func_dugraphs_dir(func)}/{bc_name}")

    def func_bc_slice_dugraphs_dir(self, func: str, bc_name: str, slice_id: int) -> str:
        return mkdir(f"{self.func_bc_dugraphs_dir(func, bc_name)}/{slice_id}")

    def features_dir(self) -> str:
        return f"{self.analysis_dir()}/features"

    def func_features_dir(self, func: str) -> str:
        return mkdir(f"{self.features_dir()}/{func}")

    def func_bc_features_dir(self, func: str, bc_name: str) -> str:
        return mkdir(f"{self.func_features_dir(func)}/{bc_name}")

    def func_bc_slice_features_dir(self, func: str, bc_name: str, slice_id: int) -> str:
        return mkdir(f"{self.func_bc_features_dir(func, bc_name)}/{slice_id}")

    def temp_dir(self) -> str:
        return f"{self.directory}/temp"

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

    def bc_files(self) -> List[str]:
        return [bc_file for pkg in self.packages for bc_file in pkg.bc_files()]

    def clear_analysis_of_bc(self, bc_file):
        subprocess.run(['rm', '-rf', f"{self.analysis_dir()}/**/{bc_file}/*"])