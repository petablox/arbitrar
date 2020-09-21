import subprocess
import os
import ntpath
import json
import shutil
import re
import string

this_path = os.path.dirname(os.path.realpath(__file__))

exclude_fn = r'^llvm\|^load\|^_tr_\|^_\.\|^OPENSSL_cleanse'

def setup_parser(parser):
  parser.add_argument('--bc', type=str, default="", help='The .bc file to analyze')
  parser.add_argument('--slice-depth', type=int, default=1, help='Slice depth')
  parser.add_argument('--include-fn', type=str, help='Only include functions')
  parser.add_argument('--entry-location', type=str)
  parser.add_argument('--seed', type=int)
  parser.add_argument('--no-reduction', action='store_true', help='Don\'t reduce trace def-use graph')
  parser.add_argument('--no-path-constraint', action='store_true')
  parser.add_argument('--no-reduce-slice', action='store_true')
  parser.add_argument('--feature-only', action='store_true')
  parser.add_argument('--serial', action='store_true', help='Execute in serial mode')
  parser.add_argument('--regex', action='store_true')
  parser.add_argument('--causality-dict-size', type=int, default=5)
  parser.add_argument('--use-batch', action='store_true')
  parser.add_argument('--batch-size', type=int)
  parser.add_argument('--no-random-work', action='store_true')

  # parser.add_argument('--commit', action='store_true', help='Commit the analysis data to the database')
  # parser.add_argument('--pretty-json', action='store_true', help='Prettify JSON')
  # parser.add_argument('--redo-occurrence', action='store_true', help='Only do occurrence extraction')
  # parser.add_argument('--redo-feature', action='store_true', help='Only do feature extraction')
  # parser.add_argument('--sample-slice', action='store_true')
  # parser.add_argument('--min-freq', type=int, default=1, help='Threshold of #occurrence of function to be included')


def main(args):
  db = args.db
  packages_functions = {}
  for bc_file in db.bc_files():
    if args.bc == '' or args.bc in bc_file:
      try:
        functions = run_analyzer(db, bc_file, args)
        packages_functions[bc_file] = functions
      except Exception as e:
        print(e)
  run_feature_extractor(db, packages_functions, args)


def get_analyzer_args(db, bc_file, args):
  bc_name = ntpath.basename(bc_file)

  base_args = [
    bc_file,
    db.analysis_dir(),
    '--subfolder', bc_name,
    '--slice-depth', str(args.slice_depth),
    '--no-feature',
    '--target-num-slices-map-file', f'temp/{bc_name}.json'
  ]

  if args.include_fn:
    base_args += ['--include-target', args.include_fn]

  if args.entry_location:
    base_args += ['--entry-location', args.entry_location]

  if args.regex:
    base_args += ['--use-regex-filter']

  if args.serial:
    base_args += ['--serial']

  if args.causality_dict_size != None:
    base_args += ['--causality-dictionary-size', str(args.causality_dict_size)]

  if args.no_reduce_slice:
    base_args += ['--no-reduce-slice']

  if args.use_batch:
    base_args += ['--use-batch']

  if args.batch_size:
    base_args += ['--batch-size', str(args.batch_size)]

  if args.seed != None:
    base_args += ['--seed', str(args.seed)]

  if args.no_random_work:
    base_args += ['--no-random-work']

  if args.feature_only:
    base_args += ['--feature-only']

  return base_args


def run_analyzer(db, bc_file, args):
  print(f"Running analyzer on {os.path.basename(bc_file)}")
  analyzer = "target/release/analyzer"
  analyzer_args = get_analyzer_args(db, bc_file, args)
  cmd = [analyzer] + analyzer_args
  run = subprocess.run(cmd, cwd=this_path)


def run_feature_extractor(db, packages_functions, args):
  pass
