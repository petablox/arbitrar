from .meta import ActiveLearner

class DualOCCLearner(ActiveLearner):
  def __init__(self, datapoints, xs, amount, args):
    super().__init__(datapoints, xs, amount, args)
    self.ts = []
    self.os = []

  def select(self, ps):
    # (p_i, _) = argmax(ps, self.ts, self.os, self.score_function, self.args.limit)
    return 0

  def feedback(self, item, is_alarm):
    if is_alarm:
      self.os.append(item)
    else:
      self.ts.append(item)

  def alarms(self, num_alarms):
    return []
