from typing import Tuple, Callable, List, Dict
from functools import reduce
import math
import json
import random
import numpy as np
import sys
import matplotlib.pyplot as plt
from sklearn.neighbors import KernelDensity

from src.database import Database, DataPoint

from .unifier import unify_features
from .feature_group import FeatureGroups
from .active_learner import kde, dual_occ, bin_svm, rand, ssad

# Learner :: (List<DataPoint>, NP.ndarray, int  , Args) -> (List<(DataPoint, Score)>, List<float>)
#         :: (Datapoints     , X         , Count, args) -> (alarms                  , AUC_Graph  )
learners = {
    "kde": kde.KDELearner,
    "dual-occ": dual_occ.DualOCCLearner,
    "bin-svm": bin_svm.BinarySVMLearner,
    "ssad": ssad.SSADLearner,
    "random": rand.RandomLearner
}


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('--bc', type=str)
  parser.add_argument('--active-learner', type=str, default='kde')
  parser.add_argument('--limit', type=float, default=0.1, help='Number of alarms to report')
  parser.add_argument('--evaluate-count', type=int)
  parser.add_argument('--evaluate-percentage', type=float)
  parser.add_argument('--evaluate-with-alarms', action='store_true')
  parser.add_argument('--num-outliers', type=int)
  parser.add_argument('--num-alarms', type=int, default=100)
  parser.add_argument('--padding', type=int, default=20)
  parser.add_argument('--time', action='store_true')
  parser.add_argument('--mark-first-bug-bc', type=str)
  parser.add_argument('--mark-first-bug-slice-id', type=int)
  parser.add_argument('--mark-first-bug-trace-id', type=int)
  parser.add_argument('--num-dp', type=int)

  parser.add_argument('--visualization', action='store_true')

  # You have to provide either source or ground-truth. When ground-truth is enabled, we will ignore source
  parser.add_argument('--source', type=str, help='The source program to refer to')
  parser.add_argument('--ground-truth', type=str)
  parser.add_argument('--function-spec', type=str, help="Path to function spec for auto learning")

  # Feature Settings
  parser.add_argument('--no-causality', action='store_true', help='Does not include causality features')
  parser.add_argument('--no-causality-before', action='store_true', help='Does not include before causality features')
  parser.add_argument('--no-causality-after', action='store_true', help='Does not include after causality features')
  parser.add_argument('--no-retval', action='store_true', help='Does not include retval features')
  parser.add_argument('--no-argval', action='store_true', help='Does not include argval features')
  parser.add_argument('--no-arg-pre', action='store_true', help='Does not include argval features')
  parser.add_argument('--no-arg-post', action='store_true', help='Does not include argval features')
  parser.add_argument('--no-control-flow', action='store_true', help='Does not include control flow features')

  # Setup learner specific arguments
  for learner in learners.values():
    learner.setup_parser(parser)


def main(args):
  db = args.db

  print("Fetching Datapoints From Database...")
  datapoints = list(db.function_datapoints(args.function))[0:args.num_dp]

  print("Unifying Features...")
  feature_jsons = unify_features(datapoints)
  sample_feature_json = feature_jsons[0]

  print("Generating Feature Groups and Encoder")
  feature_groups = FeatureGroups(sample_feature_json,
                                 enable_causality=not args.no_causality,
                                 enable_causality_before=not args.no_causality_before,
                                 enable_causality_after=not args.no_causality_after,
                                 enable_retval=not args.no_retval,
                                 enable_argval=not args.no_argval,
                                 enable_arg_pre=not args.no_arg_pre,
                                 enable_arg_post=not args.no_arg_post,
                                 enable_control_flow=not args.no_control_flow)

  for dp in datapoints:
    dp.apply_feature_groups(feature_groups)

  print("Encoding Features...")
  xs = [np.array(feature_groups.encode(feature)) for feature in feature_jsons]
  amount_to_evaluate = len(xs)
  if args.evaluate_count:
    amount_to_evaluate = min(len(xs), args.evaluate_count)
  elif args.evaluate_percentage:
    amount_to_evaluate = int(len(xs) * args.evaluate_percentage)

  exp_dir = db.new_learning_dir(args.function)
  args.exp_dir = exp_dir

  print("Active Learning...")
  active_learner = learners[args.active_learner]
  model = active_learner(datapoints, xs, amount_to_evaluate, args, output_anim = args.visualization)

  print("MARK FIRST BUG BC", args.mark_first_bug_bc)
  if args.mark_first_bug_bc and args.mark_first_bug_slice_id:
    print("Marking the first bug...")
    model.mark(args.mark_first_bug_bc, args.mark_first_bug_slice_id, args.mark_first_bug_trace_id, True)

  alarms, auc_graph, alarms_perc_graph, pospoints, tsne_anim = model.run()

  if args.ground_truth:
    print("Running Random Baseline...")
    random_learner = learners["random"]
    random_model = random_learner(datapoints, xs, amount_to_evaluate, args, output_anim = False)
    _, random_auc_graph, _, _, _ = random_model.run()
  else:
    random_auc_graph = None

  # Dump lots of things
  print("Dumping result...")

  if args.visualization:
    # Dumping tsne animation
    tsne_anim.anim.save(f"{exp_dir}/tsne_anim.mp4")

  # Dump the unified features
  with open(f"{exp_dir}/unified.json", "w") as f:
    j = {'before': list(sample_feature_json['before'].keys()), 'after': list(sample_feature_json['after'].keys())}
    json.dump(j, f)

  # Dump the Xs used to train the model
  np.array(xs).dump(f"{exp_dir}/x.dat")

  # Dump the raised alarms
  with open(f"{exp_dir}/alarms.csv", "w") as f:
    f.write("bc,slice_id,trace_id,score,alarms\n")
    for (dp, score) in alarms:
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)

  # Dump the yes points alarms
  with open(f"{exp_dir}/match.csv", "w") as f:
    f.write("bc,slice_id,trace_id,score,alarms,attempt\n")
    for (dp, attempt) in pospoints:
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},0,\"{str(dp.alarms())}\",{attempt}\n"
      f.write(s)

  # Dump the AUC graph
  auc = compute_and_dump_auc_graph(auc_graph, random_auc_graph, f"{args.function} AUC", exp_dir)

  # Dump the AP graph
  # if args.ground_truth:
  #   dump_alarms_percentage_graph(alarms_perc_graph, exp_dir)

  # Dump logs
  with open(f"{exp_dir}/log.txt", "w") as f:
    f.write("cmd\n")
    f.write("  " + str(sys.argv) + "\n")
    f.write(f"AUC: {auc}\n")
    f.write(f"AUC_GRAPH: {auc_graph}\n")


def fps_from_tps(tps):
  length = len(tps)
  fps, prev_tp_count, prev_fp_count, auc = [], 0, 0, 0.0
  for i in range(length):
    if tps[i] == prev_tp_count:
      prev_fp_count += 1
      auc += tps[i]
    fps.append(prev_fp_count)
    prev_tp_count = tps[i]

  if fps[-1] == 0 or tps[-1] == 0:
    auc = 0.0
  elif fps[-1] > 0:
    auc = auc / (fps[-1] * tps[-1])
  else:
    auc = 1.0

  return fps, auc


"""
return the AUC value
"""


def compute_and_dump_auc_graph(auc_graph, baseline, title, exp_dir) -> float:
  auc_fig, auc_ax = plt.subplots()

  auc_ax.set_title(title)
  auc_ax.set_ylabel('#TP')
  auc_ax.set_xlabel('#FP')

  tps, (fps, auc) = auc_graph, fps_from_tps(auc_graph)
  y_eq_x = range(fps[-1])

  if baseline:
    baseline_tps, (baseline_fps, _) = baseline, fps_from_tps(baseline)

  # Plot
  auc_ax.plot(fps, tps, label='Ours')
  auc_ax.plot(y_eq_x, y_eq_x, '--', label='y = x')

  if baseline:
    auc_ax.plot(baseline_fps, baseline_tps, label='Random Baseline')

  # Legend
  auc_ax.legend()

  # Save the image
  auc_fig.savefig(f"{exp_dir}/auc.png")

  # Return AUC
  return auc


def dump_alarms_percentage_graph(alarms_perc_graph, exp_dir):
  ap_fig, ap_ax = plt.subplots()
  ap_ax.set_ylabel('%% of TP in alarms')
  ap_ax.set_xlabel('# Attempts')
  ap_ax.plot(range(len(alarms_perc_graph)), alarms_perc_graph)
  ap_fig.savefig(f"{exp_dir}/ap.png")
