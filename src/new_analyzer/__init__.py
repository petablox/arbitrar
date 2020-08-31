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
  parser.add_argument('-b', '--bc', type=str, default="", help='The .bc file to analyze')
  parser.add_argument('-d', '--slice-depth', type=int, default=1, help='Slice depth')
  # parser.add_argument('-r', '--redo', action='store_true', help='Redo all analysis')
  # parser.add_argument('-i', '--input', type=str, help="Given an input bc file")
  # parser.add_argument('-v', '--verbose', type=int, help="Verbose level")
  parser.add_argument('--entry-location', type=str)
  parser.add_argument('--output-trace', action="store_true", help="Output trace json")
  parser.add_argument('--min-freq', type=int, default=1, help='Threshold of #occurrence of function to be included')
  parser.add_argument('--no-reduction', action='store_true', help='Don\'t reduce trace def-use graph')
  parser.add_argument('--no-path-constraint', action='store_true')
  parser.add_argument('--include-fn', type=str, help='Only include functions')
  parser.add_argument('--regex', action='store_true')
  parser.add_argument('--serial', action='store_true', help='Execute in serial mode')
  parser.add_argument('--redo-feature', action='store_true', help='Only do feature extraction')
  parser.add_argument('--redo-occurrence', action='store_true', help='Only do occurrence extraction')
  parser.add_argument('--pretty-json', action='store_true', help='Prettify JSON')
  parser.add_argument('--causality-dict-size', type=int, default=5)
  parser.add_argument('--commit', action='store_true', help='Commit the analysis data to the database')
  parser.add_argument('--no-reduce-slice', action='store_true')
  parser.add_argument('--use-batch', action='store_true')
  parser.add_argument('--batch-size', type=int)
  parser.add_argument('--random-worklist', action='store_true')
  parser.add_argument('--sample-slice', action='store_true')
  parser.add_argument('--seed', type=int)


def main(args):
  db = args.db
  for bc_file in db.bc_files():
    if args.bc == '' or args.bc in bc_file:
      try:
        run_analyzer(db, bc_file, args)
      except Exception as e:
        print(e)


def get_analyzer_args(db, bc_file, args):
  bc_name = ntpath.basename(bc_file)

  base_args = [
    bc_file,
    db.analysis_dir(),
    '--subfolder', bc_name,
    '--slice-depth', str(args.slice_depth),
  ]

  if args.include_fn:
    print(1)
    base_args += ['--include-target', args.include_fn]

  if args.entry_location:
    print(2)
    base_args += ['--entry-location', args.entry_location]

  if args.regex:
    print(3)
    base_args += ['--use-regex-filter']

  if args.serial:
    print(5)
    base_args += ['--serial']

  if args.causality_dict_size != None:
    print("Cause Dict", args.causality_dict_size)
    base_args += ['--causality-dictionary-size', str(args.causality_dict_size)]

  if args.no_reduce_slice:
    print(8)
    base_args += ['--no-reduce-slice']

  if args.use_batch:
    print(9)
    base_args += ['--use-batch']

  if args.batch_size:
    print(10)
    base_args += ['--batch-size', str(args.batch_size)]

  return base_args


def run_analyzer(db, bc_file, args):
  analyzer = "target/release/analyzer"
  analyzer_args = get_analyzer_args(db, bc_file, args)
  cmd = [analyzer] + analyzer_args
  print(cmd)
  run = subprocess.run(cmd, cwd=this_path)
