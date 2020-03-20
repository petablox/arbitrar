from typing import List

import json

from ..database import *

def load_input(args):
    with open(f"{args.cwd}/{args.packages}") as f:
        pkgs_json = json.load(f)
        return [Pkg.from_json(j) for j in pkgs_json]
    return None

def fetch_pkg(db: Database, pkg: Pkg):
    print(f"Fetching {pkg.name}")

def compile_pkg(db: Database, pkg: Pkg):
    print(f"Compiling {pkg.name}")

def main(args):
    db : Database = args.db
    pkgs : List[Pkg] = load_input(args)
    for pkg in pkgs:
        if not db.contains_package(pkg.name):
            fetch_pkg(db, pkg)
            compile_pkg(db, pkg)
            db.add_package(pkg)
        else:
            stored_pkg = db.get_package(pkg.name)
            if not stored_pkg.is_fetched():
                fetch_pkg(db, pkg)
            if not stored_pkg.is_built():
                compile_pkg(db, pkg)
            db.add_package(pkg)