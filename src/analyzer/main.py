import subprocess
import os
import ntpath
import json
import shutil
import re
import string

from .utils import Timer

this_path = os.path.dirname(os.path.realpath(__file__))

exclude_fn = r'^llvm\|^load\|^_tr_\|^_\.\|^OPENSSL_cleanse'


def setup_parser(parser):
  parser.add_argument('-b', '--bc', type=str, default="", help='The .bc file to analyze')
  parser.add_argument('-d', '--slice-depth', type=int, default=1, help='Slice depth')
  parser.add_argument('-r', '--redo', action='store_true', help='Redo all analysis')
  parser.add_argument('-i', '--input', type=str, help="Given an input bc file")
  parser.add_argument('-v', '--verbose', type=int, help="Verbose level")
  parser.add_argument('--output-trace', action="store_true", help="Output trace json")
  parser.add_argument('--min-freq', type=int, default=1, help='Threshold of #occurrence of function to be included')
  parser.add_argument('--no-reduction', action='store_true', help='Don\'t reduce trace def-use graph')
  parser.add_argument('--no-path-constraint', action='store_true')
  parser.add_argument('--include-fn', type=str, default="", help='Only include functions')
  parser.add_argument('--serial', action='store_true', help='Execute in serial mode')
  parser.add_argument('--redo-feature', action='store_true', help='Only do feature extraction')
  parser.add_argument('--redo-occurrence', action='store_true', help='Only do occurrence extraction')
  parser.add_argument('--pretty-json', action='store_true', help='Prettify JSON')
  parser.add_argument('--causality-dict-size', type=int, default=5)
  parser.add_argument('--commit', action='store_true', help='Commit the analysis data to the database')
  parser.add_argument('--reduce-slice', action='store_true')
  parser.add_argument('--use-batch', action='store_true')
  parser.add_argument('--batch-size', type=int)
  parser.add_argument('--random-worklist', action='store_true')


def main(args):
  db = args.db
  if args.input:
    inp = os.path.join(os.getcwd(), args.input)
    run_analyzer(db, inp, args)
  else:
    for bc_file in db.bc_files():
      if args.bc == '' or args.bc in bc_file:
        try:
          run_analyzer(db, bc_file, args)
        except:
          pass


def alpha_num(s):
  return "".join([c for c in s if c.isalnum() or c == '_'])


def remove_path_if_existed(path):
  if os.path.exists(path):
    print(f"Removing directory {path}")
    shutil.rmtree(path)


def run_analyzer(db, bc_file, args):
  all_timer = Timer()

  bc_name = ntpath.basename(bc_file)
  temp_dir = db.temp_dir(create=True)
  if "include_fn" in args and args.include_fn:
    include_fn_str = alpha_num(args.include_fn)
    temp_outdir = f"{temp_dir}/{bc_name}_{include_fn_str}"
  else:
    temp_outdir = f"{temp_dir}/{bc_name}"

  # Marker files
  occurrence_file = db.occurrence_json_dir(bc_name)
  analyze_finished_file = f"{temp_outdir}/anal_fin.txt"
  move_finished_file = f"{temp_outdir}/move_fin.txt"

  # Check temporary directory
  has_temp_dir = os.path.exists(temp_outdir)

  # Check if occurrence analysis is finished
  has_occurrence_file = os.path.exists(occurrence_file)

  # Run occurrence if not finished
  if args.redo_occurrence or not has_occurrence_file:
    print("Calculating function occurrences...")
    occurrence_timer = Timer()
    cmd = ['./analyzer', 'occurrence', bc_file, '-json', '-exclude-fn', exclude_fn, '-outdir', temp_outdir]
    run = subprocess.run(cmd, cwd=this_path)
    if run.returncode != 0:
      print("Occurrence Failed")
    else:
      shutil.copy(f"{temp_outdir}/occurrence.json", occurrence_file)
      print(f"Occurrence Finished. Elapsed {occurrence_timer.time():0.2f}s")
  else:
    print(f"Skipping occurrence counting of {bc_name}")

  # Check if analysis is finished
  has_analyze_finished_file = os.path.exists(analyze_finished_file)
  analyze_finished = has_temp_dir and has_analyze_finished_file

  # Analyze if not finished
  if args.redo or not analyze_finished:
    print("Starting Analysis...")
    analysis_timer = Timer()

    cmd = [
        './analyzer', bc_file, '-no-analysis', '-n',
        str(args.slice_depth), '-exclude-fn', exclude_fn, '-causality-dict-size',
        str(args.causality_dict_size), '-outdir', temp_outdir
    ]

    if "min_freq" in args:
      print(f"Setting min-freq to {args.min_freq}")
      cmd += ['-min-freq', str(args.min_freq)]

    if "include_fn" in args and args.include_fn:
      print(f"Only including functions {args.include_fn}")
      cmd += ['-include-fn', args.include_fn]

    if args.no_reduction:
      print(f"No reduction of DUGraph")
      cmd += ['-no-reduction']

    if args.output_trace:
      print(f"Outputting trace")
      cmd += ['-output-trace']

    if args.no_path_constraint:
      print(f"No path constraint")
      cmd += ['-no-path-constraint']

    if args.serial:
      print(f"Execute in serial")
      cmd += ['-serial']

    if args.verbose != None:
      print(f"Setting verbose level to {args.verbose}")
      cmd += ['-verbose', str(args.verbose)]

    if args.reduce_slice:
      print(f"Use slice reduction")
      cmd += ['-reduce-slice']

    if args.use_batch:
      print(f"Use batched execution")
      cmd += ['-use-batch']

    if args.batch_size != None:
      print(f"Use batch size {args.batch_size}")
      cmd += ['-batch-size', str(args.batch_size)]

    if args.random_worklist:
      print(f"Use randomized worklist")
      cmd += ['-random-worklist']

    run = subprocess.run(cmd, cwd=this_path, env={'OCAMLRUNPARAM': 'b'})

    if run.returncode != 0:
      print(f"\nAnalysis of {bc_name} failed")
      print("Stderr: ", run.stderr)
      return

    print(f"Analysis finished in {analysis_timer.time():0.2f}s")

    # Save a file indicating the state of analysis
    open(analyze_finished_file, 'a').close()

  # Only run feature extraction
  elif args.redo_feature:
    print("Extracting Features...")
    feature_extraction_timer = Timer()

    cmd = [
        './analyzer', 'feature', '-exclude-fn', exclude_fn, '-causality-dict-size',
        str(args.causality_dict_size), temp_outdir
    ]

    if args.use_batch:
      print(f"Use batched execution")
      cmd += ['-use-batch']

    if args.batch_size != None:
      print(f"Use batch size {args.batch_size}")
      cmd += ['-batch-size', str(args.batch_size)]

    run = subprocess.run(cmd, cwd=this_path)
    if run.returncode != 0:
      print(f"Analysis of {bc_name} failed after {feature_extraction_timer.time():0.2f}s")
      return
    print(f"Feature Extraction Finished in {feature_extraction_timer.time():0.2f}s")
  else:
    print(f"Skipping analysis of {bc_name}")

  # Check if database commit needs to be done
  if args.redo or args.commit or args.redo_feature or not os.path.exists(move_finished_file):
    print("Storing Analyzed Database...")
    commit_timer = Timer()
    visited_funcs = set()

    if args.use_batch:
      outdirs = [os.path.join(temp_outdir, d) for d in os.listdir(temp_outdir) if "batch_" in d]
    else:
      outdirs = [temp_outdir]

    slice_count = 0
    func_counts = {}
    for outdir in outdirs:

      # Move files over to real location
      # First we move slices
      with open(f"{outdir}/slices.json") as f:
        slices_json = json.load(f)
        for local_slice_id, slice_json in enumerate(slices_json):
          slice_count += 1
          print(f"Commiting slice #{slice_count}", end="\r")

          callee = slice_json["call_edge"]["callee"]

          # Remove existing folders
          if not callee in visited_funcs:
            if args.redo:
              remove_path_if_existed(db.func_bc_slices_dir(callee, bc_name))
              remove_path_if_existed(db.func_bc_dugraphs_dir(callee, bc_name))
              remove_path_if_existed(db.func_bc_features_dir(callee, bc_name))
            elif args.redo_feature:
              remove_path_if_existed(db.func_bc_features_dir(callee, bc_name))
          visited_funcs.add(callee)

          # Calculate counts
          if callee in func_counts:
            index = func_counts[callee]
            func_counts[callee] += 1
          else:
            index = 0
            func_counts[callee] = 1

          # If we are not redoing feature
          if not args.redo_feature:

            # Move slices
            fpd = db.func_bc_slices_dir(callee, bc_name, create=True)
            with open(f"{fpd}/{index}.json", "w") as out:
              json.dump(slice_json, out)

            # Then we move dugraphs
            dugraphs_dir = db.func_bc_slice_dugraphs_dir(callee, bc_name, index, create=True)
            with open(f"{outdir}/dugraphs/{callee}-{local_slice_id}.json") as dgs_file:
              dgs_json = json.load(dgs_file)
              num_traces = len(dgs_json)
              for trace_id, dg_json in enumerate(dgs_json):
                with open(f"{dugraphs_dir}/{trace_id}.json", "w") as out:
                  json.dump(dg_json, out)
          else:
            with open(f"{outdir}/dugraphs/{callee}-{local_slice_id}.json") as dgs_file:
              dgs_json = json.load(dgs_file)
              num_traces = len(dgs_json)

          # We move extracted features
          features_dir = db.func_bc_slice_features_dir(callee, bc_name, index, create=True)
          for trace_id in range(num_traces):
            source = f"{outdir}/features/{callee}/{local_slice_id}-{trace_id}.json"
            target = f"{features_dir}/{trace_id}.json"
            shutil.copyfile(source, target)

    # Store the status
    open(move_finished_file, "a").close()
    print(f"\nCommitting Analysis Data Finished in {commit_timer.time():0.2f}s")
    print(f"Finished analysis of {bc_name} in {all_timer.time():0.2f}s")
  else:
    print(f"Skipping committing analysis data of {bc_name}")
