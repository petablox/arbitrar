from argparse import ArgumentParser
import json
import os
import shutil
import pathlib

from src.database import Database, Pkg, PkgSrc, PkgSrcType, Build, BuildType, BuildResult, mkdir

from .fetch import fetch_pkg
from .compile import compile_pkg


def input_is_json(args):
  return ".json" in args.packages


def input_is_bc(args):
  return ".bc" in args.packages


def input_is_dir(args):
  return os.path.isdir(args.packages)


def load_json_input(args):
  with open(f"{args.cwd}/{args.packages}") as f:
    pkgs_json = json.load(f)
    return [Pkg.from_json(j) for j in pkgs_json]
  return None


def load_bc_input(args):
  db = args.db
  bc_dir = os.path.abspath(args.packages)

  if not os.path.exists(bc_dir):
    raise Exception(f"{args.packages} does not exist")

  if not os.path.isfile(bc_dir):
    raise Exception(".bc file input has to be a file")

  filename = os.path.basename(args.packages)
  name = filename[:-3]

  # Create package directory
  package_dir = f"{db.packages_dir()}/{name}"
  mkdir(package_dir)

  # Setup source directory
  package_source_dir = f"{package_dir}/source"
  mkdir(package_source_dir)

  # Copy the bc file and setup libs
  libs = [name]
  shutil.copy(bc_dir, package_source_dir)

  # Create index file
  index_json_dir = f"{package_dir}/index.json"
  if os.path.isfile(index_json_dir):
    os.remove(index_json_dir)

  # Setup package meta information
  pkg_src_type = PkgSrcType("precompiled")
  pkg_src = PkgSrc(pkg_src_type)
  build = Build(BuildType("unknown"), "", BuildResult("success"), libs=libs)
  pkg = Pkg(name, pkg_src, True, package_dir, build)

  # Dump the meta information to the index file
  with open(index_json_dir, "w") as f:
    json.dump(Pkg.to_json(pkg), f)


def load_folder_input(args):
  db = args.db

  # Get input directory and a name
  input_dir = os.path.abspath(args.packages)
  name = os.path.basename(os.path.normpath(input_dir))

  # Get and create package directory
  package_dir = f"{db.packages_dir()}/{name}"
  mkdir(package_dir)

  # Copy the whole folder into the `source` directory
  package_source_dir = f"{package_dir}/source"
  if os.path.exists(package_source_dir):
    shutil.rmtree(package_source_dir)
  shutil.copytree(input_dir, package_source_dir)

  # Create libs array
  package_source_path = pathlib.Path(package_source_dir)
  libs = []
  for root, dirs, files in os.walk(package_source_dir):
    for file_dir in files:
      if "final_to_check.bc" == file_dir:
        file_path = pathlib.Path(f"{root}/{file_dir}")
        rel_path = file_path.relative_to(package_source_path)
        new_path = "_".join(list(rel_path.parts[:-2]))
        shutil.copy(file_path, f"{package_source_dir}/{new_path}.bc")
        libs.append(new_path)

  # Dump the index json file
  index_json_dir = f"{package_dir}/index.json"
  if os.path.isfile(index_json_dir):
    shutil.remove(index_json_dir)
  pkg_src_type = PkgSrcType("precompiled")
  pkg_src = PkgSrc(pkg_src_type)
  build = Build(BuildType("unknown"), "", BuildResult("success"), libs=libs)
  pkg = Pkg(name, pkg_src, True, package_dir, build)
  with open(index_json_dir, "w") as f:
    json.dump(Pkg.to_json(pkg), f)


def process_pkg(db: Database, pkg: Pkg):
  if not db.has_package(pkg.name):
    fetch_pkg(db, pkg)
    db.add_package(pkg)  # Save the temporary result
    compile_pkg(db, pkg)
    db.add_package(pkg)
  else:
    stored_pkg = db.get_package(pkg.name)
    if not stored_pkg.is_fetched():
      fetch_pkg(db, stored_pkg)
      db.add_package(stored_pkg)
    if not stored_pkg.is_built():
      compile_pkg(db, stored_pkg)
      db.add_package(stored_pkg)


def setup_parser(parser: ArgumentParser):
  parser.add_argument('packages', type=str, help='Input JSON file/directory')


def main(args):
  db: Database = args.db
  if input_is_json(args):
    pkgs: List[Pkg] = load_json_input(args)
    for pkg in pkgs:
      process_pkg(db, pkg)
  elif input_is_bc(args):
    load_bc_input(args)
  elif input_is_dir(args):
    load_folder_input(args)
