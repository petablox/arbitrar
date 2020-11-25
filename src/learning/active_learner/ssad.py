import numpy as np
import cvxopt

from ..models.get_kernel import get_kernel
from ..models.saad_convex import ConvexSSAD
from .meta import ActiveLearner


class SSADLearner(ActiveLearner):
  def __init__(self, datapoints, xs, amount, args, output_anim = False):
    if args.ssad_show_progress:
      super().__init__(datapoints, xs, amount, args, log_newline=True, output_anim = output_anim)
    else:
      super().__init__(datapoints, xs, amount, args, output_anim = output_anim)
      cvxopt.solvers.options['show_progress'] = False
    self.X = np.transpose(np.array(self.xs))
    self.Y = np.zeros(len(xs), dtype=np.int)

  @staticmethod
  def setup_parser(parser):
    parser.add_argument("--ssad-show-progress", action="store_true")

  def select(self, ps):
    train_kernel = get_kernel(self.X, self.X)
    ssad = ConvexSSAD(train_kernel, self.Y)
    ssad.fit()

    test_x = np.transpose(np.array([x for (_, x) in ps]))
    test_kernel = get_kernel(test_x, self.X[:, ssad.svs])
    res = ssad.apply(test_kernel)

    argmin_res = np.argmin(res)
    (i, _) = ps[argmin_res]
    return i

  def feedback(self, item, is_alarm):
    value = -1 if is_alarm else 1
    (i, _) = item
    self.Y[i] = value

  def alarms(self, num_alarms):
    train_kernel = get_kernel(self.X, self.X)
    ssad = ConvexSSAD(train_kernel, self.Y)
    ssad.fit()
    test_kernel = get_kernel(self.X, self.X[:, ssad.svs])
    res = ssad.apply(test_kernel)
    alarms = [(self.datapoints[i], score) for (i, score) in enumerate(res)]
    return sorted(alarms, key=lambda a: a[1])[:num_alarms]
