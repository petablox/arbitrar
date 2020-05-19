from . import utils
from .actions import *

action_executors = {
    'generate-dot': GenerateDotAction,
    'label': LabelAction
}


def setup_parser(parser):
  subparsers = parser.add_subparsers(dest="query")
  for key, executor in action_executors.items():
    query_parser = subparsers.add_parser(key)
    executor.setup_parser(query_parser)


def main(args):
  if args.query in action_executors:
    action_executors[args.query].execute(args)
  else:
    print(f"Unknown query {args.query}")
