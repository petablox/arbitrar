import subprocess
import os
import ntpath
import json

# This file path
dir_path = os.path.dirname(os.path.realpath(__file__))

def setup_parser(parser):
    parser.add_argument('-s', '--slice-size', type=int, default=1, help='Slice size')
    parser.add_argument('-r', '--redo', action='store_true', help='Redo all analysis')
    parser.add_argument('-b', '--bc', type=str, default="", help='The .bc file to analyze')
    parser.add_argument('-f', '--feature', action='store_true', help='Only do feature extraction')
    parser.add_argument('--min-freq', type=int, default=1, help='Threshold of #occurrence of function to be considered API')
    parser.add_argument('-c', '--commit', action='store_true', help='Commit the analysis data to the database')


def main(args):
    db = args.db

    # Get the bc_files
    bc_files = db.bc_files()

    # Run analyzer on each one of the bc_files
    for bc_file in bc_files:
        if args.bc == '' or args.bc in bc_file:
            run_analyzer(db, bc_file, args)


def run_analyzer(db, bc_file, args):
    bc_name = ntpath.basename(bc_file)
    temp_outdir = f"{db.temp_dir()}/{bc_name}"
    analyze_finished_file = f"{temp_outdir}/anal_fin.txt"
    move_finished_file = f"{temp_outdir}/move_fin.txt"

    # Clear the files in the analysis/ if we need to redo anything
    if args.redo or args.commit:
        db.clear_analysis_of_bc(bc_file)

    # Check if analysis is finished
    if args.redo or not os.path.exists(analyze_finished_file):
        run = subprocess.run(
            ['./analyzer', bc_file, '-n', str(args.slice_size), '-min-freq', '10',
             '-exclude-fn', '^__\|^llvm\|^load\|^_tr_\|^OPENSSL_cleanse', '-outdir', temp_outdir],
            cwd=dir_path)

        # Save a file indicating the state of analysis
        open(analyze_finished_file, 'a').close()

    # Only run feature extraction
    elif args.feature:
        run = subprocess.run(['./analyzer', 'feature', temp_outdir], cwd=dir_path)

    else:
        print(f"Skipping analysis of {bc_name}")

    # Check if database commit needs to be done
    if args.redo or args.commit or not os.path.exists(move_finished_file):

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

                if not args.feature:
                    fpd = db.func_bc_slices_dir(callee, bc_name)
                    with open(f"{fpd}/{index}.json", "w") as out:
                        json.dump(slice_json, out)

                    # Then we move dugraphs
                    dugraphs_dir = db.func_bc_slice_dugraphs_dir(callee, bc_name, index)
                    with open(f"{temp_outdir}/dugraphs/{callee}-{slice_id}.json") as dgs_file:
                        dgs_json = json.load(dgs_file)
                        num_traces = len(dgs_json)
                        for trace_id, dg_json in enumerate(dgs_json):
                            with open(f"{dugraphs_dir}/{trace_id}.json", "w") as out:
                                json.dump(dg_json, out)

                # We move extracted features
                features_dir = db.func_bc_slice_features_dir(callee, bc_name, index)
                for trace_id in range(num_traces):
                    with open(f"{temp_outdir}/features/{callee}/{slice_id}-{trace_id}.json") as feature_file:
                        feature_json = json.load(feature_file)
                        with open(f"{features_dir}/{trace_id}.json", "w") as out:
                            json.dump(feature_json, out)

        # Store the status
        open(move_finished_file, "a").close()