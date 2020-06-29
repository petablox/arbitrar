import random

from .meta import ActiveLearner


class RandomLearner(ActiveLearner):
  def __init__(self, datapoints, xs, amount, args):
    super().__init__(datapoints, xs, amount, args)

  @staticmethod
  def setup_parser(parser):
    pass

  def select(self, ps):
    (p_i, _) = ps[random.randint(0, len(ps) - 1)]
    return p_i

  def feedback(self, item, is_alarm):
    pass

  def alarms(self, num_alarms):
    return []
