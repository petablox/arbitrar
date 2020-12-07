import subprocess
import os
import ntpath
import json
import shutil
import re
import string

this_path = os.path.dirname(os.path.realpath(__file__))


def setup_parser(parser):
  parser.add_argument('--bc', type=str, default="", help='The .bc file to analyze')
  parser.add_argument('--location', type=str, help='Location')
  parser.add_argument('--pointer-only', action="store_true")


def main(args):
  db = args.db
  for bc_file in db.bc_files():
    if args.bc == '' or args.bc in bc_file:
      try:
        run_occurrence(db, bc_file, args)
      except Exception as e:
        print(e)


def get_occurrence_args(db, bc_file, args):
  print(bc_file, db.analysis_dir())
  bc_name = ntpath.basename(bc_file)
  base_args = [bc_file, db.analysis_dir()]

  if args.location:
    base_args += ['--location', args.location]

  return base_args


def run_occurrence(db, bc_file, args):
  occurrence = "target/release/occurrence"
  occurrence_args = get_occurrence_args(db, bc_file, args)
  cmd = [occurrence] + occurrence_args
  run = subprocess.run(cmd, cwd=this_path)
