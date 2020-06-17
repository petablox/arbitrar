import numpy as np
import random
from sklearn.svm import SVC

from .meta import ActiveLearner

class BinarySVMLearner(ActiveLearner):
  def __init__(self, datapoints, xs, amount, args):
    super().__init__(datapoints, xs, amount, args)
    self.ts = []
    self.os = []

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
      abs_scores = np.abs(model.predict([x for (_, x) in ps]))
      argmin_score = np.argmin(abs_scores)
      (p_i, _) = labeled[argmin_score]
      return p_i

  def feedback(self, item, is_alarm):
    if is_alarm:
      self.os.append(item)
    else:
      self.ts.append(item)

  def alarms(self, ps):
    labeled = self.ts + self.os
    X = [x for (_, x) in labeled]
    y = [1 for _ in self.ts] + [-1 for _ in self.os]
    model = SVC()
    model.fit(X, y)
    all_ps = labeled + ps
    scores = model.predict([x for (_, x) in all_ps])
    alarms = [(self.datapoints[i], score) for ((i, _), score) in zip(all_ps, scores)]
    return alarms
