from argparse import ArgumentParser
import os

from . import collector


def init_parser():
    parser = ArgumentParser()
    setup_parser(parser)
    return parser


def setup_collect_parser(parser: ArgumentParser):
    parser.add_argument('repos', type=str, help='Input JSON file')


def setup_analyze_parser(parser: ArgumentParser):
    pass


def setup_info_parser(parser: ArgumentParser):
    pass


def setup_unsup_parser(parser: ArgumentParser):
    pass


def setup_parser(parser: ArgumentParser):
    parser.add_argument('-d', '--db', type=str, default="data/", help='Operating Database')

    # Subparsers
    subparsers = parser.add_subparsers(dest="cmd")

    # Collect Parser
    collect_parser = subparsers.add_parser("collect")
    setup_collect_parser(collect_parser)

    # Analyze Parser
    analyze_parser = subparsers.add_parser("analyze")
    setup_analyze_parser(analyze_parser)

    # Info Parser
    info_parser = subparsers.add_parser("info")
    setup_info_parser(info_parser)

    # Unsup Parser
    unsup_parser = subparsers.add_parser("unsup")
    setup_unsup_parser(unsup_parser)


def main():
    parser = init_parser()
    args = parser.parse_args()
    args.cwd = os.getcwd()
    if args.cmd == 'collect':
        collector.main(args)
