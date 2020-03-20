import json

from .. import *

from .fetch import fetch_pkg
from .compile import compile_pkg


def load_input(args):
    with open(f"{args.cwd}/{args.packages}") as f:
        pkgs_json = json.load(f)
        return [Pkg.from_json(j) for j in pkgs_json]
    return None


def process_pkg(db: Database, pkg: Pkg):
    if not db.contains_package(pkg.name):
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


def main(args):
    db: Database = args.db
    pkgs: List[Pkg] = load_input(args)
    for pkg in pkgs:
        process_pkg(db, pkg)
