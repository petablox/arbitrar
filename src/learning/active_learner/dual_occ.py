import numpy as np
from sklearn.svm import OneClassSVM

from .meta import ActiveLearner


class DualOCCLearner(ActiveLearner):
  def __init__(self, datapoints, xs, amount, args, output_anim = False):
    super().__init__(datapoints, xs, amount, args, output_anim = output_anim)
    self.ts = []
    self.os = []
    self.target_occ = None
    self.outlier_occ = None

  @staticmethod
  def setup_parser(parser):
    parser.add_argument('--dual-occ-agg', type=str, default="exp")  # Or "sim"

  def select(self, ps):
    if len(self.ts) == 0 and len(self.os) == 0:
      return 0
    else:
      us = np.array([x for (_, x) in ps])

      # Compute DV^t
      if len(self.ts) > 0:
        dv_t = self.target_occ.predict(us)
      else:
        dv_t = np.array([1 for _ in ps])

      # Compute DV^o
      if len(self.os) > 0:
        dv_o = self.outlier_occ.predict(us)
      else:
        dv_o = np.array([1 for _ in ps])

      # Compute aggregation function
      if self.args.dual_occ_agg == 'exp':
        agg = dv_o * dv_t  # agg_exploration
      elif self.args.dual_occ_agg == 'sim':
        agg = -np.abs(dv_t - dv_o)
      else:
        raise Exception(f"Unknown aggregation function {self.args.dual_occ_agg}")

      i = np.argmax(agg)
      (p_i, _) = ps[i]
      return p_i

  def feedback(self, item, is_alarm):
    if is_alarm:
      self.os.append(item)
      self.outlier_occ = OneClassSVM(nu=0.9)
      self.outlier_occ.fit([x for (_, x) in self.os])
    else:
      self.ts.append(item)
      self.target_occ = OneClassSVM(nu=0.1)
      self.target_occ.fit([x for (_, x) in self.ts])

  def alarms(self, num_alarms):
    if len(self.ts) > 0:
      dv_t = self.target_occ.predict(self.xs)
    else:
      dv_t = np.array([1 for _ in range(len(self.xs))])
    if len(self.os) > 0:
      dv_o = self.outlier_occ.predict(self.xs)
    else:
      dv_o = np.array([1 for _ in range(len(self.xs))])
    scores = dv_o - dv_t
    alarms = [(self.datapoints[i], score) for (i, score) in zip(range(len(self.xs)), scores)]
    return sorted(alarms, key=lambda a: a[1])[:num_alarms]
