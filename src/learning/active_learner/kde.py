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

# from .unifier import unify_features
# from .feature_group import FeatureGroups

Vec = np.ndarray

IdVecs = List[Tuple[int, Vec]]

DensityFunction = Callable[[IdVecs, int, Vec], float]

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


def argmax(ps: IdVecs, ts: IdVecs, os: IdVecs, score: ScoreFunction, p_t: float) -> Tuple[int, float]:
  max_i = None
  max_score = None
  for (i, x) in ps:
    s = score(i, x, ts, os, p_t)
    if max_i == None or s > max_score:
      max_i = i
      max_score = s
  return (max_i, max_score)


def top_scored(ps: IdVecs, ts: IdVecs, os: IdVecs, score: ScoreFunction, limit: float):
  """
  limit: a number between 0 and 1, indicating the portion of alarms to be reported
  Return a list of (index, x, score) that rank the lowest on score
  """
  xs = ps + ts + os
  xs_with_scores = [(i, x, score(i, x, ts, os, limit)) for (i, x) in xs]
  num_xs = len(xs_with_scores)
  num_alarms = int(num_xs * limit)
  sorted_xs_with_scores = sorted(xs_with_scores, key=lambda d: -d[2])
  return sorted_xs_with_scores[0:num_alarms]


def active_learn(datapoints, xs, args):
  score_function = score_functions[args.score]

  ps = list(enumerate(xs))
  ts = []
  os = []

  outlier_count = 0
  auc_graph = []
  evaluate_count = int(len(datapoints) * args.evaluate_percentage)

  if args.source:
    vis = SourceFeatureVisualizer(args.source)

  try:
    for attempt_count in range(evaluate_count):

      # Get the index of datapoint that has the lowest score
      (p_i, _) = argmax(ps, ts, os, score_function, args.limit)
      if p_i == None:
        break

      # Get the full datapoint
      dp_i = datapoints[p_i]
      item = (p_i, xs[p_i])

      if args.ground_truth:

        # Alarm
        is_alarm = dp_i.has_label(label=args.ground_truth)
        print(f"Attempt {attempt_count} is alarm: {str(is_alarm)}   ", end="\r")

      elif args.source:

        # If the ground truth is not provided
        # Ask the user to label. y: Is Outlier, n: Not Outlier, u: Unknown
        result = vis.ask(dp_i,
                        ["y", "n"],
                        prompt=f"Attempt {attempt_count}: Do you think this is a bug? [y|n|u] > ",
                        scroll_down_key="]",
                        scroll_up_key="[")
        if result != "q":
          if result == "y":
            is_alarm = True
          elif result == "n":
            is_alarm = False
        else:
          break

      else:
        print("Must provide --ground-truth or --source. Aborting")
        sys.exit()

      if is_alarm:
        os.append(item)
        outlier_count += 1
      else:
        ts.append(item)
      ps = [(i, x) for (i, x) in ps if i != p_i]
      auc_graph.append(outlier_count)

  except SystemExit:
    print("Aborting")
    sys.exit()
  except Exception as err:
    if not args.ground_truth:
      vis.destroy()
    raise err

  # Remove the visualizer
  if not args.ground_truth:
    vis.destroy()
  else:
    print("")

  # Generate the scores and alarms
  alarm_id_scores = top_scored(ps, ts, os, score_function, args.limit)
  alarms = [(datapoints[i], score) for (i, _, score) in alarm_id_scores]

  return alarms, auc_graph