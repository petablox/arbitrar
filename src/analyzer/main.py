import subprocess
import os
import ntpath
import json
import shutil
import re
import string

this_path = os.path.dirname(os.path.realpath(__file__))

exclude_fn = '^llvm\|^load\|^_tr_\|^_\.\|^OPENSSL_cleanse'


def setup_parser(parser):
  parser.add_argument('-b', '--bc', type=str, default="", help='The .bc file to analyze')
  parser.add_argument('-s', '--slice-size', type=int, default=1, help='Slice size')
  parser.add_argument('-r', '--redo', action='store_true', help='Redo all analysis')
  parser.add_argument('-i', '--input', type=str, help="Given an input bc file")
  parser.add_argument('--min-freq', type=int, default=1, help='Threshold of #occurrence of function to be included')
  parser.add_argument('--no-reduction', action='store_true', help='Don\'t reduce trace def-use graph')
  parser.add_argument('--include-fn', type=str, default="", help='Only include functions')
  parser.add_argument('--redo-feature', action='store_true', help='Only do feature extraction')
  parser.add_argument('--pretty-json', action='store_true', help='Prettify JSON')
  parser.add_argument('--causality-dict-size', type=int, default=5)
  parser.add_argument('--commit', action='store_true', help='Commit the analysis data to the database')


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


def run_analyzer(db, bc_file, args):
  bc_name = ntpath.basename(bc_file)
  temp_dir = db.temp_dir(create=True)
  if "include_fn" in args and args.include_fn:
    include_fn_str = alpha_num(args.include_fn)
    temp_outdir = f"{temp_dir}/{bc_name}_{include_fn_str}"
  else:
    temp_outdir = f"{temp_dir}/{bc_name}"

  # Marker files
  occurrence_finished_file = f"{temp_outdir}/occur_fin.txt"
  analyze_finished_file = f"{temp_outdir}/anal_fin.txt"
  move_finished_file = f"{temp_outdir}/move_fin.txt"

  # Clear the files in the analysis/ if we need to redo anything
  # if args.redo or args.commit:
  #   db.clear_analysis_of_bc(bc_file)

  has_temp_dir = os.path.exists(temp_outdir)

  # Check if occurrence analysis is finished
  has_occurrence_finished_file = os.path.exists(occurrence_finished_file)
  occurrence_finished = has_temp_dir and has_occurrence_finished_file

  # Run occurrence if not finished
  if args.redo or not occurrence_finished:
    cmd = ['./analyzer', 'occurrence', bc_file, '-json', '-exclude-fn', exclude_fn, '-outdir', temp_outdir]

    run = subprocess.run(cmd, cwd=this_path)

    shutil.copy(f"{temp_outdir}/occurrence.json", f"{db.occurrence_dir()}/{bc_name}.json")

    open(occurrence_finished_file, 'a').close()
  else:
    print(f"Skipping occurrence counting of {bc_name}")

  # Check if analysis is finished
  has_analyze_finished_file = os.path.exists(analyze_finished_file)
  analyze_finished = has_temp_dir and has_analyze_finished_file

  # Analyze if not finished
  if args.redo or not analyze_finished:
    cmd = [
        './analyzer', bc_file, '-no-analysis', '-n',
        str(args.slice_size), '-exclude-fn', exclude_fn, '-causality-dict-size',
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

    run = subprocess.run(cmd, cwd=this_path)

    if run.returncode != 0:
      print(f"Analysis of {bc_name} failed")
      return

    # Save a file indicating the state of analysis
    open(analyze_finished_file, 'a').close()

  # Only run feature extraction
  elif args.redo_feature:
    run = subprocess.run([
        './analyzer', 'feature', '-exclude-fn', exclude_fn, '-causality-dict-size',
        str(args.causality_dict_size), temp_outdir
    ],
                         cwd=this_path)

    if run.returncode != 0:
      print(f"Analysis of {bc_name} failed")
      return

  else:
    print(f"Skipping analysis of {bc_name}")

  # Check if database commit needs to be done
  if args.redo or args.commit or args.redo_feature or not os.path.exists(move_finished_file):

    # Move files over to real location
    # First we move slices
    with open(f"{temp_outdir}/slices.json") as f:
      func_counts = {}
      slices_json = json.load(f)
      for slice_id, slice_json in enumerate(slices_json):
        print(f"Commiting slice #{slice_id}", end="\r")

        callee = slice_json["call_edge"]["callee"]
        if callee in func_counts:
          index = func_counts[callee]
          func_counts[callee] += 1
        else:
          index = 0
          func_counts[callee] = 1

        if not args.redo_feature:

          # Move slices
          fpd = db.func_bc_slices_dir(callee, bc_name, create=True)
          with open(f"{fpd}/{index}.json", "w") as out:
            json.dump(slice_json, out)

          # Then we move dugraphs
          dugraphs_dir = db.func_bc_slice_dugraphs_dir(callee, bc_name, index, create=True)
          with open(f"{temp_outdir}/dugraphs/{callee}-{slice_id}.json") as dgs_file:
            dgs_json = json.load(dgs_file)
            num_traces = len(dgs_json)
            for trace_id, dg_json in enumerate(dgs_json):
              with open(f"{dugraphs_dir}/{trace_id}.json", "w") as out:
                json.dump(dg_json, out)
        else:
          with open(f"{temp_outdir}/dugraphs/{callee}-{slice_id}.json") as dgs_file:
            dgs_json = json.load(dgs_file)
            num_traces = len(dgs_json)

        # We move extracted features
        features_dir = db.func_bc_slice_features_dir(callee, bc_name, index, create=True)
        for trace_id in range(num_traces):
          source = f"{temp_outdir}/features/{callee}/{slice_id}-{trace_id}.json"
          target = f"{features_dir}/{trace_id}.json"
          shutil.copyfile(source, target)

    # Store the status
    open(move_finished_file, "a").close()

    print(f"\nFinished analysis of {bc_name}")
  else:
    print(f"Skipping committing analysis data of {bc_name}")
