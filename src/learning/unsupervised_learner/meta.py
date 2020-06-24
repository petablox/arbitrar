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