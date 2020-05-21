from sklearn.svm import OneClassSVM
from sklearn.ensemble import IsolationForest

class Model:
  def __init__(self, datapoints, x, clf):
    self.datapoints = datapoints
    self.x = x
    self.clf = clf

  def alarms(self):
    predicted = self.clf.predict(self.x)
    scores = self.clf.score_samples(self.x)
    for (dp, p, s) in zip(self.datapoints, predicted, scores):
      if p < 0:
        yield (dp, s)

  def results(self):
    predicted = self.clf.predict(self.x)
    scores = self.clf.score_samples(self.x)
    for (dp, p, s) in zip(self.datapoints, predicted, scores):
      yield (dp, p, s)

  def predicted(self):
    return self.clf.predict(self.x)


# One-Class SVM
class OCSVM(Model):
  def __init__(self, datapoints, x, args):
    clf = OneClassSVM(kernel=args.kernel, nu=args.nu).fit(x)
    super().__init__(datapoints, x, clf)


# Isolation Forest
class IF(Model):
  def __init__(self, datapoints, x, args):
    clf = IsolationForest(contamination=args.contamination).fit(x)
    super().__init__(datapoints, x, clf=clf)
