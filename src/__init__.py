from argparse import ArgumentParser
import os

from . import collector
from . import database
from . import analyzer


def init_parser():
    parser = ArgumentParser()
    setup_parser(parser)
    return parser


def setup_unsup_parser(parser: ArgumentParser):
    parser.add_argument('function', type=str, help='Function to train on')


def setup_parser(parser: ArgumentParser):
    parser.add_argument('-d', '--db', type=str, default="data", help='Operating Database')

    # Subparsers
    subparsers = parser.add_subparsers(dest="cmd")

    # Collect Parser
    collect_parser = subparsers.add_parser("collect")
    collector.setup_parser(collect_parser)

    # Analyze Parser
    analyze_parser = subparsers.add_parser("analyze")
    analyzer.setup_parser(analyze_parser)

    # Info Parser
    db_parser = subparsers.add_parser("db")
    database.setup_parser(db_parser)

    # Unsup Parser
    unsup_parser = subparsers.add_parser("unsup")
    setup_unsup_parser(unsup_parser)


def main():
    parser = init_parser()
    args = parser.parse_args()

    cwd = os.getcwd()
    args.cwd = cwd

    db = database.Database(f"{cwd}/{args.db}")
    args.db = db

    if args.cmd == 'collect':
        collector.main(args)
    elif args.cmd == 'db':
        database.main(args)
    elif args.cmd == 'analyze':
        analyzer.main(args)