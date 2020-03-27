from argparse import ArgumentParser
import os

from . import collector
from . import database
from . import analyzer
from . import learning

modules = {
    'collect': collector,
    'analyze': analyzer,
    'db': database,
    'learn': learning
}


def new_arg_parser():
    parser = ArgumentParser()
    parser.add_argument('-d', '--db', type=str, default="data", help='Operating Database')
    subparsers = parser.add_subparsers(dest="cmd")
    for (key, module) in modules.items():
        subparser = subparsers.add_parser(key)
        module.setup_parser(subparser)
    return parser


def main():

    # Initialize the parser and command line arguments
    parser = new_arg_parser()
    args = parser.parse_args()
    cwd = os.getcwd()
    args.cwd = cwd
    db = database.Database(f"{cwd}/{args.db}")
    args.db = db

    # Execute the main function of that module
    if args.cmd:
        modules[args.cmd].main(args)
    else:
        parser.print_help()
