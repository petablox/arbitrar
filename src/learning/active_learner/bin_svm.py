import numpy as np
import random
from sklearn.svm import SVC

from .meta import ActiveLearner


class BinarySVMLearner(ActiveLearner):
  def __init__(self, datapoints, xs, amount, args, output_anim = False):
    super().__init__(datapoints, xs, amount, args, output_anim = output_anim)
    self.ts = []
    self.os = []

  @staticmethod
  def setup_parser(parser):
    parser.add_argument('--bin-svm-select-lowest', action='store_true')

  def select(self, ps):
    if len(self.ts) == 0 or len(self.os) == 0:
      (p_i, _) = ps[random.randint(0, len(ps) - 1)]
      return p_i
    else:
      labeled = self.ts + self.os
      X = [x for (_, x) in labeled]
      y = [1 for _ in self.ts] + [-1 for _ in self.os]
      model = SVC()
      model.fit(X, y)
      if self.args.bin_svm_select_lowest:
        scores = model.predict([x for (_, x) in ps])
        argmin_score = np.argmin(scores)
      else:
        abs_scores = np.abs(model.predict([x for (_, x) in ps]))
        argmin_score = np.argmin(abs_scores)
      (p_i, _) = ps[argmin_score]
      return p_i

  def feedback(self, item, is_alarm):
    if is_alarm:
      self.os.append(item)
    else:
      self.ts.append(item)

  def alarms(self, num_alarms):
    if len(self.ts) == 0 or len(self.os) == 0:
      return []
    else:
      labeled = self.ts + self.os
      X = [x for (_, x) in labeled]
      y = [1 for _ in self.ts] + [-1 for _ in self.os]
      model = SVC()
      model.fit(X, y)
      scores = model.predict(self.xs)
      dp_scores = [(self.datapoints[i], score) for (i, score) in zip(range(len(self.xs)), scores)]
      sorted_dp_scores = sorted(dp_scores, key=lambda d: d[1])
      return sorted_dp_scores[0:num_alarms]
