from sklearn.ensemble import IsolationForest

from .meta import Model


class IF(Model):
  def __init__(self, datapoints, x, args):
    clf = IsolationForest(contamination=args.contamination).fit(x)
    super().__init__(datapoints, x, clf=clf)
