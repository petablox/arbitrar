from enum import Enum
from typing import List, Optional

import os
import json
import ntpath
import subprocess
import datetime

from .package import *
from .analysis import *
from .utils import *


class Database:
  directory: str
  packages: List[Pkg]

  def __init__(self, directory: str):
    self.directory = directory
    if Database.has_init_file(directory):
      self.setup_file_system()
      self.setup_indices()
    else:
      raise Exception("Not a misapi database. Please run 'misapi init' first.")

  @staticmethod
  def init_file_dir(directory: str) -> str:
    return f"{directory}/.misapi"

  @staticmethod
  def init(directory: str):
    file_dir = Database.init_file_dir(directory)
    open(file_dir, "a").close()

  @staticmethod
  def has_init_file(directory: str) -> bool:
    file_dir = Database.init_file_dir(directory)
    return os.path.exists(file_dir)

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
    mkdir(self.occurrence_dir())

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

  def occurrence_dir(self) -> str:
    return f"{self.analysis_dir()}/occurrence"

  def slices_dir(self) -> str:
    return f"{self.analysis_dir()}/slices"

  def func_slices_dir(self, func: str, create=False) -> str:
    d = f"{self.slices_dir()}/{func}"
    return mkdir(d) if create else d

  def func_bc_slices_dir(self, func: str, bc_name: str, create=False) -> str:
    d = f"{self.func_slices_dir(func, create=create)}/{bc_name}"
    return mkdir(d) if create else d

  def slice_dir(self, func: str, bc_name: str, slice_id: int) -> str:
    return f"{self.func_bc_slices_dir(func, bc_name)}/{slice_id}.json"

  def dugraphs_dir(self) -> str:
    return f"{self.analysis_dir()}/dugraphs"

  def func_dugraphs_dir(self, func: str, create=False) -> str:
    d = f"{self.dugraphs_dir()}/{func}"
    return mkdir(d) if create else d

  def func_bc_dugraphs_dir(self, func: str, bc_name: str, create=False) -> str:
    d = f"{self.func_dugraphs_dir(func, create=create)}/{bc_name}"
    return mkdir(d) if create else d

  def func_bc_slice_dugraphs_dir(self, func: str, bc_name: str, slice_id: int, create=False) -> str:
    d = f"{self.func_bc_dugraphs_dir(func, bc_name, create=create)}/{slice_id}"
    return mkdir(d) if create else d

  def dugraph_dir(self, func: str, bc_name: str, slice_id: int, trace_id: int, create=False) -> str:
    return f"{self.func_bc_slice_dugraphs_dir(func, bc_name, slice_id, create=create)}/{trace_id}.json"

  def features_dir(self) -> str:
    return f"{self.analysis_dir()}/features"

  def func_features_dir(self, func: str, create=False) -> str:
    d = f"{self.features_dir()}/{func}"
    return mkdir(d) if create else d

  def func_bc_features_dir(self, func: str, bc_name: str, create=False) -> str:
    d = f"{self.func_features_dir(func, create=create)}/{bc_name}"
    return mkdir(d) if create else d

  def func_bc_slice_features_dir(self, func: str, bc_name: str, slice_id: int, create=False) -> str:
    d = f"{self.func_bc_features_dir(func, bc_name, create=create)}/{slice_id}"
    return mkdir(d) if create else d

  def feature_dir(self, func: str, bc_name: str, slice_id: int, trace_id: int) -> str:
    return f"{self.func_bc_slice_features_dir(func, bc_name, slice_id)}/{trace_id}.json"

  def dots_dir(self, create=False) -> str:
    d = f"{self.analysis_dir()}/dots"
    return mkdir(d) if create else d

  def func_dots_dir(self, func: str, create=False) -> str:
    d = f"{self.dots_dir(create=create)}/{func}"
    return mkdir(d) if create else d

  def func_bc_dots_dir(self, func: str, bc_name: str, create=False) -> str:
    d = f"{self.func_dots_dir(func, create=create)}/{bc_name}"
    return mkdir(d) if create else d

  def func_bc_slice_dots_dir(self, func: str, bc_name: str, slice_id: int, create=False) -> str:
    d = f"{self.func_bc_dots_dir(func, bc_name, create=create)}/{slice_id}"
    return mkdir(d) if create else d

  def dot_dir(self, func: str, bc_name: str, slice_id: int, trace_id: int) -> str:
    return f"{self.func_bc_slice_dots_dir(func, bc_name, slice_id)}/{trace_id}.dot"

  def learning_dir(self, create=False) -> str:
    d = f"{self.directory}/learning"
    return mkdir(d) if create else d

  def new_learning_dir(self, label) -> str:
    dt = datetime.datetime.now()
    prefix = f"{dt.month}-{dt.day}-{dt.year}-{dt.hour}-{dt.minute}-{dt.second}"
    d = f"{self.learning_dir(create=True)}/{prefix}-{label}"
    return mkdir(d)

  def temp_dir(self, create=False) -> str:
    d = f"{self.directory}/temp"
    return mkdir(d) if create else d

  def has_package(self, package_name: str) -> bool:
    for pkg in self.packages:
      if pkg.name == package_name:
        return True
    return False

  def get_package(self, package_name: str) -> Optional[Pkg]:
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

  def bc_files(self, package=None, full=True):
    if package:
      if not self.has_package(package):
        raise Exception(f"Unknown package {package}")

    for pkg in self.packages:
      if package == None or pkg.name == package:
        for bc_file in pkg.bc_files(full=full):
          yield bc_file

  def find_bc_name(self, s) -> Optional[str]:
    for pkg in self.packages:
      for bc_file in pkg.bc_files(full=False):
        if s in bc_file:
          return bc_file
    return None

  def occurrence_json_dir(self, bc_file):
    return f"{self.occurrence_dir()}/{bc_file}.json"

  def occurrence(self, bc_file):
    d = self.occurrence_json_dir(bc_file)
    if os.path.exists(d):
      with open(d) as f:
        return json.load(f)
    else:
      return None

  def occurrences(self, package=None, bc_file=None):
    if bc_file:
      occurrence = self.occurrence(bc_file)
      if occurrence:
        yield bc_file, occurrence
    else:
      for bc_file in self.bc_files(package=package, full=False):
        occurrence = self.occurrence(bc_file)
        if occurrence:
          yield bc_file, occurrence

  def clear_analysis_of_bc(self, bc_file):
    subprocess.run(['rm', '-rf', f"{self.analysis_dir()}/**/{bc_file}/*"])

  def num_slices(self, func_name=None, bc=None) -> int:
    if func_name != None and bc != None:
      count = 0
      for root, dirs, files in os.walk(self.func_bc_slices_dir(func_name, bc)):
        for f in files:
          count += 1
      return count
    elif func_name != None:
      count = 0
      for root, dirs, files in os.walk(self.func_slices_dir(func_name)):
        for f in files:
          count += 1
      return count
    elif bc != None:
      count = 0
      for root, dirs, files in os.walk(self.slices_dir()):
        if len(files) != 0:
          bc_name = ntpath.basename(root)
          if bc in bc_name:
            count += len(files)
      return count
    else:
      count = 0
      for root, _, files in os.walk(self.slices_dir()):
        count += len(files)
      return count

  def slice(self, func_name, bc, slice_id):
    slice_file_dir = self.slice_dir(func_name, bc, slice_id)
    if os.path.exists(slice_file_dir):
      with open(slice_file_dir) as f:
        return json.load(f)
    else:
      return None

  def num_traces(self, func_name=None, bc=None):
    if func_name != None and bc != None:
      count = 0
      for root, dirs, files in os.walk(self.func_bc_dugraphs_dir(func_name, bc)):
        count += len(files)
      return count
    elif func_name != None:
      count = 0
      for root, dirs, files in os.walk(self.func_dugraphs_dir(func_name)):
        for f in files:
          count += 1
      return count
    elif bc != None:
      count = 0
      for root, dirs, files in os.walk(self.dugraphs_dir()):
        if len(files) != 0:
          bc_name = ntpath.basename(root)
          if bc in bc_name:
            count += len(files)
      return count
    else:
      count = 0
      for root, _, files in os.walk(self.dugraphs_dir()):
        count += len(files)
      return count

  def num_traces_of_slice(self, func: str, bc: str, slice_id: int):
    count = 0
    for _, _, files in os.walk(self.func_bc_slice_dugraphs_dir(func, bc, slice_id)):
      count += len(files)
    return count

  def dugraph(self, func_name, bc, slice_id, trace_id):
    with open(self.dugraph_dir(func_name, bc, slice_id, trace_id)) as f:
      return json.load(f)

  def feature(self, func_name, bc, slice_id, trace_id):
    with open(self.feature_dir(func_name, bc, slice_id, trace_id)) as f:
      return json.load(f)

  def datapoint(self, func_name, bc, slice_id, trace_id):
    return DataPoint(self, func_name, bc, slice_id, trace_id)

  def function_slices(self, func_name: str):
    # Check if the function is there
    func_slices_dir = self.func_slices_dir(func_name, create=False)
    if not os.path.exists(func_slices_dir):
      raise Exception(f"No function {func_name} in database")

    for bc in os.listdir(func_slices_dir):
      bc_dir = self.func_bc_slices_dir(func_name, bc)
      for slice_name in os.listdir(bc_dir):
        slice_id = int(os.path.splitext(slice_name)[0])
        yield slice_id, self.slice(func_name, bc, slice_id)

  def function_datapoints(self, func_name: str):
    # Check if the function is there
    func_slices_dir = self.func_slices_dir(func_name, create=False)
    if not os.path.exists(func_slices_dir):
      raise Exception(f"No function {func_name} in database")

    # List the directory
    for bc in os.listdir(func_slices_dir):
      bc_dir = self.func_bc_slices_dir(func_name, bc)
      for slice_name in os.listdir(bc_dir):
        slice_id = int(os.path.splitext(slice_name)[0])
        slice = self.slice(func_name, bc, slice_id)
        trace_dir = self.func_bc_slice_dugraphs_dir(func_name, bc, slice_id)
        for trace_name in os.listdir(trace_dir):
          trace_id = int(os.path.splitext(trace_name)[0])
          yield DataPoint(self, func_name, bc, slice_id, trace_id, slice=slice)
