import numpy as np
from sklearn.svm import OneClassSVM
from sklearn.ensemble import IsolationForest
from src.database import Database, DataPoint


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('-m', '--model', type=str, default='ocsvm', help='Model (ocsvm)')

  # OCSVM Parameters
  parser.add_argument('--kernel', type=str, default='rbf', help='OCSVM Kernel')
  parser.add_argument('--nu', type=float, default=0.01, help='OCSVM nu')

  # Isolation Forest Parameters
  parser.add_argument('--contamination', type=float, default=0.01, help="Isolation Forest Contamination")


class Model:
  def alarms(self):
    raise Exception("Alarm not implemented")


# One-Class SVM
class OCSVM(Model):
  def __init__(self, datapoints, x, args):
    self.datapoints = datapoints
    self.x = x
    self.clf = OneClassSVM(kernel=args.kernel, nu=args.nu).fit(x)

  def alarms(self):
    predicted = self.clf.predict(self.x)
    scores = self.clf.score_samples(self.x)
    for (dp, p, s) in zip(self.datapoints, predicted, scores):
      if p == -1:
        yield (dp, s)


# Isolation Forest
class IF(Model):
  def __init__(self, datapoints, x, args):
    self.datapoints = datapoints
    self.x = x
    self.clf = IsolationForest(contamination=args.contamination).fit(x)

  def alarms(self):
    predicted = self.clf.predict(self.x)
    scores = self.clf.score_samples(self.x)
    for (dp, p, s) in zip(self.datapoints, predicted, scores):
      if p == -1:
        yield (dp, s)


models = {"ocsvm": OCSVM, "isolation-forest": IF}


def main(args):
  db = args.db
  datapoints = list(db.function_datapoints(args.function))
  features = unify_features(datapoints)
  x = np.array([encode_feature(feature) for feature in features])
  model = models[args.model](datapoints, x, args)
  for (dp, score) in sorted(list(model.alarms()), key=lambda x: x[1]):
    print(dp.slice_id, dp.trace_id, score, [l for l in dp.dugraph()["labels"] if "alarm" in l])


def unify_causality(causalities):
  d = {}
  for causality in causalities:
    for func in causality.keys():
      d[func] = True
  return d


def unify_features(datapoints):
  features = [dp.feature() for dp in datapoints]
  invoked_before = unify_causality([f["invoked_before"] for f in features])
  invoked_after = unify_causality([f["invoked_after"] for f in features])

  # Unify the features
  for feature in features:
    # First invoked before
    for func in invoked_before.keys():
      if not func in feature["invoked_before"]:
        feature["invoked_before"][func] = False
    # Then invoked after
    for func in invoked_after.keys():
      if not func in feature["invoked_after"]:
        feature["invoked_after"][func] = False

  return features


def encode_feature(feature_json):
  invoked_before_features = encode_causality(feature_json["invoked_before"])
  invoked_after_features = encode_causality(feature_json["invoked_after"])
  retval_features = encode_retval(feature_json["retval_check"]) if "retval_check" in feature_json else []
  return invoked_before_features + invoked_after_features + retval_features


def encode_causality(causality):
  return [int(causality[key]) for key in sorted(causality)]


def encode_retval(retval):
  if retval["has_retval_check"]:
    return [
        int(retval["has_retval_check"]),
        int(retval["check_branch_taken"]),
        int(retval["branch_is_zero"]),
        int(retval["branch_not_zero"])
    ]
  else:
    return [
        int(retval["has_retval_check"]),
        0,  # Default
        0,  # Default
        0  # Default
    ]
