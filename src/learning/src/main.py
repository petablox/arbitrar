import os
import numpy as np
import joblib
import sys
import json

from sklearn.svm import OneClassSVM
from sklearn.ensemble import IsolationForest
from sklearn.manifold import TSNE

import matplotlib.pyplot as plt

from src.database import Database, DataPoint


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('-m', '--model', type=str, default='ocsvm', help='Model (ocsvm)')
  parser.add_argument('-g', '--ground-truth', type=str, help='Ground Truth Label')
  parser.add_argument('-s', '--seed', type=int, default=1234)
  parser.add_argument('-v', '--verbose', action='store_true')
  parser.add_argument('-i', '--input', type=str)

  # OCSVM Parameters
  parser.add_argument('--kernel', type=str, default='rbf', help='OCSVM Kernel')
  parser.add_argument('--nu', type=float, default=0.01, help='OCSVM nu')

  # Isolation Forest Parameters
  parser.add_argument('--contamination', type=float, default=0.01, help="Isolation Forest Contamination")


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


models = {"ocsvm": OCSVM, "isolation-forest": IF}


def main(args):
  np.random.seed(args.seed)
  if args.input:
    test(args)
  else:
    train_and_test(args)


def test(args):
  db = args.db

  input_exp_dir = os.path.join(os.getcwd(), args.input)
  clf_dir = f"{input_exp_dir}/model.joblib"
  clf = joblib.load(clf_dir)

  unified_dir = f"{input_exp_dir}/unified.json"
  with open(unified_dir) as f:
    unified = json.load(f)

  datapoints = list(db.function_datapoints(args.function))
  features = unify_features_with_sample(datapoints, unified)
  x = np.array([encode_feature(feature) for feature in features])
  model = Model(datapoints, x, clf)

  exp_dir = db.new_learning_dir(args.function)

  # Dump the command line arguments
  with open(f"{exp_dir}/log.txt", "w") as f:
    f.write(str(sys.argv))

  # Dump the raised alarms
  with open(f"{exp_dir}/alarms.csv", "w") as f:
    f.write("bc,slice_id,trace_id,alarm,score,alarms\n")
    for (dp, p, score) in sorted(list(model.results()), key=lambda x: x[1]):
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{p < 0},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)
      if args.verbose:
        print(s, end="")


def unify_features_with_sample(datapoints, unified):
  def unify_feature(datapoint, unified):
    feature = datapoint.feature()
    for k in ['invoked_before', 'invoked_after']:
      feature[k] = { key: feature[k][key] if key in feature[k] else False for key in unified[k] }
    return feature
  return [unify_feature(dp, unified) for dp in datapoints]


def train_and_test(args):
  db = args.db

  # Get the model
  datapoints = list(db.function_datapoints(args.function))
  features = unify_features(datapoints)
  x = np.array([encode_feature(feature) for feature in features])
  print(x)
  model = models[args.model](datapoints, x, args)

  # Get the output directory
  exp_dir = db.new_learning_dir(args.function)

  with open(f"{exp_dir}/unified.json", "w") as f:
    sample_feature = features[0]
    j = {
        'invoked_before': list(sample_feature['invoked_before'].keys()),
        'invoked_after': list(sample_feature['invoked_after'].keys())
    }
    json.dump(j, f)

  # Dump the command line arguments
  with open(f"{exp_dir}/log.txt", "w") as f:
    f.write(str(sys.argv))

  # Dump the model
  with open(f"{exp_dir}/model.joblib", "wb") as f:
    joblib.dump(model.clf, f)

  # Dump the raised alarms
  with open(f"{exp_dir}/alarms.csv", "w") as f:
    f.write("bc,slice_id,trace_id,score,alarms\n")
    for (dp, score) in sorted(list(model.alarms()), key=lambda x: x[1]):
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)
      if args.verbose:
        print(s, end="")

  # Dump t-SNE
  x_embedded = TSNE(n_components=2, verbose=2 if args.verbose else 0).fit_transform(x)
  predicted = model.predicted()
  if args.ground_truth:
    tp, tn, fp, fn = [], [], [], []

    def label(prediction, datapoint):
      pos = prediction < 0
      alarm = datapoint.has_alarm(alarm = args.ground_truth)
      if pos and alarm: # True positive
        return tp
      elif not pos and not alarm: # True negative
        return tn
      elif pos and not alarm: # False positive
        return fp
      else: # False negative
        return fn

    for x, p, dp in zip(x_embedded, predicted, datapoints):
      label(p, dp).append(x)

    for arr, color, zorder in [(tn, 'b', 0), (fp, 'y', 1), (fn, 'r', 2), (tp, 'g', 3)]:
      nparr = np.array(arr) if len(arr) > 0 else np.empty([0, 2])
      plt.scatter(nparr[:, 0], nparr[:, 1], c=color, zorder=zorder)

  else:
    colors = ['g' if p > 0 else 'r' for p in predicted]
    plt.scatter(x_embedded[:, 0], x_embedded[:, 1], c=colors)
  plt.savefig(f"{exp_dir}/tsne.png")


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
  argval_0_features = encode_argval(feature_json["argval_0_check"]) if "argval_0_check" in feature_json else []
  argval_1_features = encode_argval(feature_json["argval_1_check"]) if "argval_1_check" in feature_json else []
  argval_2_features = encode_argval(feature_json["argval_2_check"]) if "argval_2_check" in feature_json else []
  argval_3_features = encode_argval(feature_json["argval_3_check"]) if "argval_3_check" in feature_json else []
  return invoked_before_features + invoked_after_features + \
         retval_features + \
         argval_0_features + argval_1_features + argval_2_features + argval_3_features


def encode_causality(causality):
  return [int(causality[key]) for key in sorted(causality)]


def encode_retval(retval):
  if retval["has_retval_check"]:
    return [
        int(retval["has_retval_check"]) * 10,
        int(retval["check_branch_taken"]),
        int(retval["branch_is_zero"]),
        int(retval["branch_not_zero"])
    ]
  else:
    return [
        0,
        0,  # Default
        0,  # Default
        0  # Default
    ]


def encode_argval(argval):
  if argval["has_argval_check"]:
    return [
        int(argval["has_argval_check"]) * 10,
        int(argval["check_branch_taken"]),
        int(argval["branch_is_zero"]),
        int(argval["branch_not_zero"])
    ]
  else:
    return [
        0,
        0,
        0,
        0
    ]
