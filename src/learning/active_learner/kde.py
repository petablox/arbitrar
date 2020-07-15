from typing import Tuple, Callable, List, Dict
import math
import json
import random
import numpy as np
import sys
import matplotlib.pyplot as plt
from sklearn.neighbors import KernelDensity
from sklearn.model_selection import GridSearchCV
import scipy.spatial.distance

from src.database import Database, DataPoint
from src.database.helpers import SourceFeatureVisualizer

from .meta import ActiveLearner

Vec = np.ndarray

IdVecs = List[Tuple[int, Vec]]


def nparr_of_idvecs(idvecs: IdVecs):
  return np.array([x for _, x in idvecs])


class ScoreFunction:
  def __init__(self, xs, bandwidth):
    self.bandwidth = bandwidth


class Score1(ScoreFunction):
  def score(self, i, u, pos, neg, p_t) -> float:
    if len(pos) == 0:
      return 0

    poss_density = KernelDensity(bandwidth=self.bandwidth).fit(nparr_of_idvecs(pos))
    score = poss_density.score_samples([u])[0]

    return score


class Score2(ScoreFunction):
  def score(self, i, u, pos, neg, p_t) -> float:
    raise Exception("Not implemented")


class Score3(ScoreFunction):
  def score(self, i, u, pos, neg, p_t) -> float:
    raise Exception("Not implemented")


class Score4(ScoreFunction):
  def score(self, i, u, pos, neg, p_pos) -> float:
    """
    The higher the score is, the more likely it is a positive sample
    """
    if len(neg) == 0:
      return 0

    ts_arr = nparr_of_idvecs(neg)
    os_arr = nparr_of_idvecs(pos)
    ts_plus_u_arr = nparr_of_idvecs(neg + [(i, u)])
    os_plus_u_arr = nparr_of_idvecs(pos + [(i, u)])

    ts_density = KernelDensity(bandwidth=self.bandwidth).fit([u])
    f_plus_u = KernelDensity(bandwidth=self.bandwidth).fit(os_plus_u_arr)
    # os_density = KernelDensity(bandwidth=0.1).fit(os_arr)

    s_t_1 = (np.sum(ts_density.score_samples(ts_plus_u_arr))) / (len(neg) + 1)
    if len(pos) == 0:
      s_t_2 = 0
    else:
      s_t_2 = np.sum(f_plus_u.score_samples(os_arr)) / len(pos)
    s_t = s_t_1 - s_t_2

    if len(neg) == 0:
      s_o_1 = 0
    else:
      s_o_1 = np.sum(ts_density.score_samples(ts_arr)) / len(neg)
    s_o_2 = np.sum(ts_density.score_samples(os_plus_u_arr)) / (len(pos) + 1)
    s_o = s_o_1 - s_o_2

    return p_pos * s_t + (1. - p_pos) * s_o


class Score5(ScoreFunction):
  def score(self, i, u, pos, neg, p_pos):
    # +++++ NEW IMPLEMENTATION +++++ #

    n, m = len(pos), len(neg)

    if n == 0 and m == 0:
      return 0

    s_pos_1 = 0
    if n > 0:
      for (_i, _x_i) in pos + [(i, u)]:
        pos_plus_u_min_i = nparr_of_idvecs([(_j, _x_j) for (_j, _x_j) in pos + [(i, u)] if _j != _i])
        dens = KernelDensity(bandwidth=self.bandwidth).fit(pos_plus_u_min_i)

        s_pos_1 += np.exp(dens.score_samples([_x_i]))[0]
      s_pos_1 /= n + 1

    dens = KernelDensity(bandwidth=self.bandwidth).fit(nparr_of_idvecs(pos + [(i, u)]))
    s_pos_2 = np.mean(np.exp(dens.score_samples(nparr_of_idvecs(neg))))

    s_pos = s_pos_1 - s_pos_2

    s_neg_1, s_neg_2 = 0, 0
    if n > 0:
      # for (_i, _x_i) in pos:
      #   pos_min_i = nparr_of_idvecs([(_j, _x_j) for (_j, _x_j) in pos if _j != _i])
      #   dens = KernelDensity(bandwidth=0.1).fit(pos_min_i)
      #   s_neg_1 += dens.score_samples([_x_i])[0]
      # s_neg_1 /= n

      dens = KernelDensity(bandwidth=self.bandwidth).fit(nparr_of_idvecs(pos))
      s_neg_2 = np.mean(np.exp(dens.score_samples(nparr_of_idvecs(neg + [(i, u)]))))

    s_neg = s_neg_1 - s_neg_2

    return p_pos * s_pos + (1 - p_pos) * s_neg


class Score6(ScoreFunction):
  def score(self, i, u, pos, neg, p_pos):
    pos_score = 0
    if len(pos) > 0:
      pos_dens = KernelDensity(bandwidth=self.bandwidth).fit(nparr_of_idvecs(pos))
      pos_score = pos_dens.score_samples([u])[0]

    neg_score = 0
    if len(neg) > 0:
      neg_dens = KernelDensity(bandwidth=self.bandwidth).fit(nparr_of_idvecs(neg))
      neg_score = neg_dens.score_samples([u])[0]

    return pos_score - neg_score


class Score7(ScoreFunction):
  """ The same scoring function as Score6, but use dynamic programming to
      optimize the performance """
  def __init__(self, xs, bandwidth):
    super().__init__(xs, bandwidth)
    self.n = len(xs)
    self.cache = np.empty([self.n, self.n])
    self.cache.fill(-1)  # Use -1 to represent nothing, as the real values will be positive definite

  def index(self, i, j):
    return (i, j) if i < j else (j, i)

  def gaussian(self, x, y):
    b = self.bandwidth
    return np.exp(-(np.linalg.norm(x - y))**2 / (2 * b**2)) / (b * np.sqrt(2 * np.pi))

  def gaussian_cached(self, i, x, j, y):
    index = self.index(i, j)
    if self.cache[index] == -1:
      self.cache[index] = self.gaussian(x, y)
    return self.cache[index]

  def score(self, i, x, pos, neg, p_pos):
    n, m = len(pos), len(neg)
    pos_score, neg_score = 0, 0
    if n > 0:
      for (j, y) in pos:
        pos_score += self.gaussian_cached(i, x, j, y)
      pos_score /= n
    if m > 0:
      for (j, y) in neg:
        neg_score += self.gaussian_cached(i, x, j, y)
      neg_score /= m
    return pos_score - neg_score


class KDELearner(ActiveLearner):
  score_functions: Dict[str, ScoreFunction] = {
      'score_1': Score1,
      'score_2': Score2,
      'score_3': Score3,
      'score_4': Score4,
      'score_5': Score5,
      'score_6': Score6,
      'score_7': Score7
  }

  def __init__(self, datapoints, xs, amount, args):
    super().__init__(datapoints, xs, amount, args)
    if args.kde_bandwidth != None:
      self.bandwidth = args.kde_bandwidth
    else:
      self.bandwidth = self._auto_bandwidth(xs)
    self.score_function = self.score_functions[args.kde_score](xs, self.bandwidth)
    self.pos = []
    self.neg = []

  @staticmethod
  def setup_parser(parser):
    parser.add_argument('--kde-score', type=str, default="score_7", help='Score Function')
    parser.add_argument('--kde-bandwidth', type=float)
    parser.add_argument('--kde-cv', type=int, default=10)
    parser.add_argument('--p-pos', type=float, default=0.1)

  def select(self, unlabeled):
    (p_i, _) = self._argmax(unlabeled, self.pos, self.neg, self.args.p_pos)
    return p_i

  def feedback(self, item, is_alarm):
    if is_alarm:
      self.pos.append(item)
    else:
      self.neg.append(item)

  def alarms(self, num_alarms):
    alarm_id_scores = self._top_scored(list(enumerate(self.xs)), self.pos, self.neg, num_alarms)
    alarms = [(self.datapoints[i], score) for (i, _, score) in alarm_id_scores]
    return alarms

  def _auto_bandwidth(self, xs):
    print("Auto Selecting Bandwidth...")
    X = np.array(xs)
    dists = scipy.spatial.distance.pdist(X)
    mean_dist = np.mean(dists)
    low, high = mean_dist / 10.0, mean_dist * 10.0
    print(f"Selecting bandwidth from {low} to {high} with log scale...")
    grid = GridSearchCV(KernelDensity(), {'bandwidth': np.logspace(low, high, 10)}, cv=self.args.kde_cv)
    grid.fit(X)
    bandwidth = grid.best_params_['bandwidth']
    print(f"Selected bandwidth: {bandwidth}")
    return bandwidth

  def _argmin(self, ps: IdVecs, pos: IdVecs, neg: IdVecs, p_t: float) -> Tuple[int, float]:
    """
    Return the (index, score) of the datapoint in xs that scores the highest
    """
    min_i = None
    min_score = None
    for (i, x) in ps:
      s = self.score_function.score(i, x, pos, neg, p_t)
      if min_i == None or s < min_score:
        min_i = i
        min_score = s
    return (min_i, min_score)

  def _argmax(self, ps: IdVecs, pos: IdVecs, neg: IdVecs, p_t: float) -> Tuple[int, float]:
    max_i = None
    max_score = None
    for (i, x) in ps:
      s = self.score_function.score(i, x, pos, neg, p_t)
      if max_i == None or s > max_score:
        max_i = i
        max_score = s
    return (max_i, max_score)

  def _top_scored(self, xs: IdVecs, pos: IdVecs, neg: IdVecs, num_alarms):
    """
    limit: a number between 0 and 1, indicating the portion of alarms to be reported
    Return a list of (index, x, score) that rank the lowest on score
    """
    xs_with_scores = [(i, x, self.score_function.score(i, x, pos, neg, 0.1)) for (i, x) in xs]
    sorted_xs_with_scores = sorted(xs_with_scores, key=lambda d: -d[2])
    return sorted_xs_with_scores[0:num_alarms]
