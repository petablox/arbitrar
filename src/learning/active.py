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
from src.database.helpers import SourceFeatureVisualizer

from .unifier import unify_features
from .feature_group import FeatureGroups
from .active_learner import kde, dual_occ, bin_svm, rand


# Learner :: (List<DataPoint>, NP.ndarray, int  , Args) -> (List<(DataPoint, Score)>, List<float>)
#         :: (Datapoints     , X         , Count, args) -> (alarms                  , AUC_Graph  )
learners = {
    "kde": kde.KDELearner,
    "dual-occ": dual_occ.DualOCCLearner,
    "bin-svm": bin_svm.BinarySVMLearner,
    "random": rand.RandomLearner
}


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('--active-learner', type=str, default='kde')
  parser.add_argument('--limit', type=float, default=0.1, help='Number of alarms to report')
  parser.add_argument('--evaluate-count', type=int)
  parser.add_argument('--evaluate-percentage', type=float)
  parser.add_argument('--random-baseline', action='store_true')

  # KDE specifics
  parser.add_argument('--kde-pdf', type=str, default="gaussian", help='Density Function')
  parser.add_argument('--kde-score', type=str, default="score_4", help='Score Function')

  # You have to provide either source or ground-truth. When ground-truth is enabled, we will ignore source
  parser.add_argument('--source', type=str, help='The source program to refer to')
  parser.add_argument('--ground-truth', type=str)


def main(args):
  db = args.db

  print("Fetching Datapoints From Database...")
  datapoints = list(db.function_datapoints(args.function))

  print("Unifying Features...")
  feature_jsons = unify_features(datapoints)
  sample_feature_json = feature_jsons[0]

  print("Generating Feature Groups and Encoder")
  feature_groups = FeatureGroups(sample_feature_json)

  print("Encoding Features...")
  xs = [np.array(feature_groups.encode(feature)) for feature in feature_jsons]
  amount_to_evaluate = len(xs)
  if args.evaluate_count:
    amount_to_evaluate = min(len(xs), args.evaluate_count)
  elif args.evaluate_percentage:
    amount_to_evaluate = int(len(xs) * args.evaluate_percentage)

  print("Active Learning...")
  active_learner = learners[args.active_learner]
  model = active_learner(datapoints, xs, amount_to_evaluate, args)
  alarms, auc_graph = model.run()

  if args.random_baseline:
    print("Running Random Baseline...")
    random_learner = learners["random"]
    random_model = random_learner(datapoints, xs, amount_to_evaluate, args)
    _, random_auc_graph = random_model.run()
  else:
    random_auc_graph = None

  # Dump lots of things
  print("Dumping result...")
  exp_dir = db.new_learning_dir(args.function)

  # Dump the unified features
  with open(f"{exp_dir}/unified.json", "w") as f:
    j = {
        'invoked_before': list(sample_feature_json['invoked_before'].keys()),
        'invoked_after': list(sample_feature_json['invoked_after'].keys())
    }
    json.dump(j, f)

  # Dump the Xs used to train the model
  np.array(xs).dump(f"{exp_dir}/x.dat")

  # Dump the raised alarms
  with open(f"{exp_dir}/alarms.csv", "w") as f:
    f.write("bc,slice_id,trace_id,scroe,alarms\n")
    for (dp, score) in alarms:
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)

  # Dump the AUC graph
  auc = compute_and_dump_auc_graph(auc_graph, exp_dir, baseline=random_auc_graph)

  # Dump logs
  with open(f"{exp_dir}/log.txt", "w") as f:
    f.write(f"AUC: {auc}\n")


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
  if fps[-1] > 0:
    auc = auc / (fps[-1] * tps[-1])
  else:
    auc = 1.0

  return fps, auc


"""
return the AUC value
"""
def compute_and_dump_auc_graph(auc_graph, exp_dir, baseline=None) -> float:
  auc_fig, auc_ax = plt.subplots()
  tps, (fps, auc) = auc_graph, fps_from_tps(auc_graph)

  # y = x
  y_eq_x = range(fps[-1])

  if baseline:
    baseline_tps, (baseline_fps, _) = baseline, fps_from_tps(baseline)

  # Plot
  auc_ax.plot(fps, tps)
  auc_ax.plot(y_eq_x, y_eq_x, '--')

  # Plot baseline
  if baseline:
    auc_ax.plot(baseline_fps, baseline_tps)

  auc_fig.savefig(f"{exp_dir}/auc.png")

  # Return AUC
  return auc