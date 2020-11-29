import subprocess
import os
import ntpath
import json
import shutil
import re
import random
import string

this_path = os.path.dirname(os.path.realpath(__file__))

exclude_fn = r'^llvm\|^load\|^_tr_\|^_\.\|^OPENSSL_cleanse'

analyzer = "target/release/analyzer"


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
  parser.add_argument('--print-call-graph', action='store_true')
  parser.add_argument('--print-options', action='store_true')
  parser.add_argument('--exec-only-slice-fn-name', type=str)
  parser.add_argument('--exec-only-slice-id', type=int)


def generate_temp_folder_name():
  length = 6
  letters = string.ascii_lowercase
  return ''.join(random.choice(letters) for i in range(length))


def main(args):
  db = args.db

  # Check the bc_files to run
  bc_files_to_run = [bc_file for bc_file in db.bc_files() if args.bc == '' or args.bc in bc_file]

  if len(bc_files_to_run) > 1:

    # Generate temporary folder that is shared among all runs
    temp_folder_name = generate_temp_folder_name()
    os.mkdir(db.analysis_dir() + "/" + temp_folder_name)
    packages_functions = {}

    # Run analyzer individually on each bc package
    for bc_file in bc_files_to_run:
      try:
        functions = run_analyzer_on_one_of_bc_files(db, bc_file, temp_folder_name, args)
        packages_functions[bc_file] = functions
      except Exception as e:
        print(e)
        exit()

    # Run feature extractor on all data generated
    input_file = generate_feature_extract_input(db, packages_functions, temp_folder_name)
    run_feature_extractor(db, input_file, args)

    # Remove the temp folder
    shutil.rmtree(db.analysis_dir() + "/" + temp_folder_name)

  else:
    bc_file = bc_files_to_run[0]
    run_analyzer_on_the_only_bc_file(db, bc_file, args)


def get_analyzer_args(db, bc_file, args, temp_folder=None, extract_features=False):
  bc_name = ntpath.basename(bc_file)

  base_args = [bc_file, db.analysis_dir(), '--subfolder', bc_name, '--slice-depth', str(args.slice_depth)]

  if extract_features == False:
    base_args += ['--no-feature']

  if temp_folder != None:
    base_args += ['--target-num-slices-map-file', f'{temp_folder}/{bc_name}.json']

  if args.include_fn:
    base_args += ['--target-inclusion-filter', args.include_fn]

  if args.entry_location:
    base_args += ['--entry-location', args.entry_location]

  if args.regex:
    base_args += ['--use-regex-filter']

  if args.serial:
    base_args += ['--use-serial']

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

  if args.print_call_graph:
    base_args += ['--print-call-graph']

  if args.print_options:
    base_args += ['--print-options']

  if args.exec_only_slice_fn_name and args.exec_only_slice_id:
    base_args += [
        '--execute-only-slice-id',
        str(args.exec_only_slice_id), '--execute-only-slice-function-name', args.exec_only_slice_fn_name
    ]

  return base_args


def run_analyzer_on_one_of_bc_files(db, bc_file, temp_folder, args):
  print(f"=== Running analyzer on {os.path.basename(bc_file)}... ===")
  bc_name = ntpath.basename(bc_file)
  analyzer_args = get_analyzer_args(db, bc_file, args, temp_folder=temp_folder)
  cmd = [analyzer] + analyzer_args
  run = subprocess.run(cmd, cwd=this_path)

  output_file = db.analysis_dir() + "/" + temp_folder + "/" + bc_name + ".json"
  with open(output_file) as f:
    return json.load(f)


def run_analyzer_on_the_only_bc_file(db, bc_file, args):
  bc_name = ntpath.basename(bc_file)
  analyzer_args = get_analyzer_args(db, bc_file, args, extract_features=True)
  cmd = [analyzer] + analyzer_args
  run = subprocess.run(cmd, cwd=this_path)


def generate_feature_extract_input(db, packages_functions, temp_folder):
  packages = []
  functions = {}
  for package, occurrences in packages_functions.items():
    pkg_name = ntpath.basename(package)
    pkg = {"name": pkg_name, "dir": package}
    packages.append(pkg)
    for func_name, num_slices in occurrences.items():
      if not func_name in functions:
        functions[func_name] = {"name": func_name, "occurrences": []}
      functions[func_name]["occurrences"].append([pkg_name, num_slices])
  result = {
      "packages": packages,
      "functions": list(functions.values()),
  }

  filename = db.analysis_dir() + "/" + temp_folder + "/ALL.json"
  with open(filename, "w") as f:
    json.dump(result, f)

  return filename


def get_extractor_args(db, input_file, args):
  base_args = [input_file, db.analysis_dir()]

  if args.causality_dict_size != None:
    base_args += ['--causality-dictionary-size', str(args.causality_dict_size)]

  return base_args


def run_feature_extractor(db, input_file, args):
  print(f"=== Running feature extraction... ===")
  extractor = "target/release/feature-extract"
  extractor_args = get_extractor_args(db, input_file, args)
  cmd = [extractor] + extractor_args
  run = subprocess.run(cmd, cwd=this_path)
