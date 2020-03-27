from .src.database import Database
from .src.package import *

def main(args):
    if args.info_cmd == 'bc-files':
        print(args.db.bc_files())