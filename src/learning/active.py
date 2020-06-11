from typing import Tuple, Callable, List, Dict
import math
import json
import random
import numpy as np
import sys
from sklearn.neighbors import KernelDensity

from src.database import Database, DataPoint
from src.database.helpers import SourceFeatureVisualizer

from .unifier import unify_features
from .feature_group import FeatureGroups


Vec = np.ndarray

IdVecs = List[Tuple[int, Vec]]

DensityFunction = Callable[[IdVecs, int, Vec], float]

# Index,
ScoreFunction = Callable[[int, Vec, IdVecs, IdVecs, float], float]

def nparr_of_idvecs(idvecs: IdVecs):
  return np.array([x for _, x in idvecs])


def density(model, x):
  return model.score(np.array([x]))[0]


def score_1(i, x, ts, os, p_t) -> float:
  raise Exception("Not implemented")


def score_2(i, x, ts, os, p_t) -> float:
  raise Exception("Not implemented")


def score_3(i, x, ts, os, p_t) -> float:
  raise Exception("Not implemented")


def score_4(i, u, ts, os, p_t) -> float:
  """
  The higher the score is, the more likely it is a positive sample
  """
  if len(ts) == 0:
    return 0

  ts_arr = nparr_of_idvecs(ts)
  os_arr = nparr_of_idvecs(os)
  ts_plus_u_arr = nparr_of_idvecs(ts + [(i, u)])
  os_plus_u_arr = nparr_of_idvecs(os + [(i, u)])

  ts_density = KernelDensity(bandwidth=0.1).fit(ts_arr)
  f_plus_u = KernelDensity(bandwidth=0.1).fit(os_plus_u_arr)
  # os_density = KernelDensity(bandwidth=0.1).fit(os_arr)

  s_t_1 = (np.sum(ts_density.score_samples(ts_plus_u_arr))) / (len(ts) + 1)
  if len(os) == 0:
    s_t_2 = 0
  else:
    s_t_2 = np.sum(f_plus_u.score_samples(os_arr)) / len(os)
  s_t = s_t_1 - s_t_2

  if len(ts) == 0:
    s_o_1 = 0
  else:
    s_o_1 = np.sum(ts_density.score_samples(ts_arr)) / len(ts)
  s_o_2 = np.sum(ts_density.score_samples(os_plus_u_arr)) / (len(os) + 1)
  s_o = s_o_1 - s_o_2

  return p_t * s_t + (1. - p_t) * s_o


score_functions : Dict[str, ScoreFunction] = {
    'score_1': score_1,
    'score_2': score_2,
    'score_3': score_3,
    'score_4': score_4
}


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('source', type=str, help='The source program to refer to')
  parser.add_argument('-d', '--pdf', type=str, default="gaussian", help='Density Function')
  parser.add_argument('-s', '--score', type=str, default="score_4", help='Score Function')
  parser.add_argument('-l', '--limit', type=float, default=0.01, help="Number of alarms reported")


def argmin(ps: IdVecs, ts: IdVecs, os: IdVecs, score: ScoreFunction, p_t: float) -> Tuple[int, float]:
  """
  Return the (index, score) of the datapoint in xs that score the highest
  """
  min_i = None
  min_score = None
  for (i, x) in ps:
    s = score(i, x, ts, os, p_t)
    if min_i == None or s < min_score:
      min_i = i
      min_score = s
  return (min_i, min_score)


def top_scored(ps: IdVecs, ts: IdVecs, os: IdVecs, score: ScoreFunction, limit: float):
  """
  limit: a number between 0 and 1, indicating the portion of alarms to be reported
  Return a list of (index, x, score) that rank the lowest on score
  """
  xs = ps + ts + os
  xs_with_scores = [(i, x, score(i, x, ts, os, limit)) for (i, x) in xs]
  num_xs = len(xs_with_scores)
  num_alarms = int(num_xs * limit)
  sorted_xs_with_scores = sorted(xs_with_scores, key=lambda d: d[2])
  return sorted_xs_with_scores[0:num_alarms]


def active_learn(datapoints, xs, ps, ts, os, score_function, args):
  vis = SourceFeatureVisualizer(args.source)

  try:
    attempt_count = 0
    while True:
      attempt_count += 1

      # Get the index of datapoint that has the lowest score
      (p_i, _) = argmin(ps, ts, os, score_function, args.limit)
      if p_i == None:
        break

      # Get the full datapoint
      dp_i = datapoints[p_i]

      # Ask the user to label. y: Is Outlier, n: Not Outlier, u: Unknown
      result = vis.ask(dp_i,
                      ["y", "n", "u"],
                      prompt=f"Attempt {attempt_count}: Do you think this is a bug? [y|n|u] > ",
                      scroll_down_key="]",
                      scroll_up_key="[")
      item = (p_i, xs[p_i])
      if result != "q":
        if result == "y" or result == "n":
          if result == "y":
            os.append(item)
          elif result == "n":
            ts.append(item)
          ps = [(i, x) for (i, x) in ps if i != p_i]
        else: # result == "u"
          pass
      else:
        break
  except SystemExit:
    print("Aborting")
    sys.exit()
  except:
    vis.destroy()
    print("Unexpected error: ", sys.exc_info()[0])
    sys.exit()

  # Remove the visualizer
  vis.destroy()

  return ps, ts, os


def main(args):
  db = args.db
  exp_dir = db.new_learning_dir(args.function)
  score_function = score_functions[args.score]

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
  ps, ts, os = active_learn(datapoints, xs, list(enumerate(xs)), [], [], score_function, args)

  # Get the alarms
  print("Done active learning. Generating result...")
  alarm_id_scores = top_scored(ps, ts, os, score_function, args.limit)
  alarm_dps = [(datapoints[i], score) for (i, _, score) in alarm_id_scores]

  # Dump lots of things
  print("Dumping result...")

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
    for (dp, score) in alarm_dps:
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)
