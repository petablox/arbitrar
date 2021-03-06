from argparse import ArgumentParser
import os

from . import collector
from . import database
from . import analyzer
from . import old_analyzer
from . import learning

modules = {
    'init': database.init,
    'collect': collector,
    'analyze': analyzer.analyzer,
    'occurrence': analyzer.occurrence,
    'analyze-old': old_analyzer,
    'query': database.query,
    'action': database.action,
    'learn': learning
}


def new_arg_parser():
  parser = ArgumentParser()
  parser.add_argument('-d', '--db', type=str, help='Operating Database')
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

  # Get the database folder
  if args.db:
    db_path = os.path.abspath(args.db)
  elif "ARBITRAR_DB" in os.environ:
    db_path = os.environ["ARBITRAR_DB"]
  else:
    db_path = cwd

  # When init, create the init file
  if args.cmd == "init":
    database.Database.init(db_path)
    print(f"Arbitrar database initialized at {db_path}")
    return

  # Otherwise, create the database
  db = database.Database(db_path)
  args.db = db

  # Execute the main function of that module
  if args.cmd:
    modules[args.cmd].main(args)
  else:
    parser.print_help()
