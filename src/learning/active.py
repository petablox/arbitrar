from typing import Tuple, Callable, List, Dict
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
from .active_learner import kde

# Learner :: (List<DataPoint>, NP.ndarray, Args) -> (List<(DataPoint, Score)>, List<float>)
#         :: (Datapoints     , X         , args) -> (alarms                  , AUC_Graph  )
learners = {
    "kde": kde.active_learn
}


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('--active-learner', type=str, default="kde")
  parser.add_argument('-d', '--pdf', type=str, default="gaussian", help='Density Function')
  parser.add_argument('-s', '--score', type=str, default="score_4", help='Score Function')
  parser.add_argument('-l', '--limit', type=float, default=0.1, help="Number of alarms reported")
  parser.add_argument('--evaluate-percentage', type=float, default=1)

  # You have to provide either source or ground-truth. When ground-truth is enabled, we will ignore source
  parser.add_argument('--source', type=str, help='The source program to refer to')
  parser.add_argument('--ground-truth', type=str)


def main(args):
  db = args.db
  active_learner = learners[args.active_learner]

  print("Fetching Datapoints From Database...")
  datapoints = list(db.function_datapoints(args.function))

  print("Unifying Features...")
  feature_jsons = unify_features(datapoints)
  sample_feature_json = feature_jsons[0]

  print("Generating Feature Groups and Encoder")
  feature_groups = FeatureGroups(sample_feature_json)

  print("Encoding Features...")
  xs = [np.array(feature_groups.encode(feature)) for feature in feature_jsons]

  print("Active Learning...")
  alarms, auc_graph = active_learner(datapoints, xs, args)

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
  if args.ground_truth:
    auc_fig, auc_ax = plt.subplots()
    auc_ax.plot(range(1, len(auc_graph) + 1), auc_graph)
    auc_fig.savefig(f"{exp_dir}/auc.png")