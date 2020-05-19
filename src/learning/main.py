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

from .encoder import encode_feature
from .unifier import unify_features, unify_features_with_sample


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


def train_and_test(args):
  db = args.db

  print("Fetching Datapoints From Database...")
  datapoints = list(db.function_datapoints(args.function))

  print("Unifying Features...")
  features = unify_features(datapoints)

  print("Encoding Features...")
  x = np.array([encode_feature(feature) for feature in features])

  print("Training Model...")
  model = models[args.model](datapoints, x, args)

  # Get the output directory
  exp_dir = db.new_learning_dir(args.function)

  print("Dumping Training Data...");

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

  # Dump the Xs used to train the model
  x.dump(f"{exp_dir}/x.dat")

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

  # Dump the raised alarms in a condensed way
  with open(f"{exp_dir}/alarms_brief.csv", "w") as f:
    f.write("bc,slice_id,num_traces,score_avg\n")

    # Get average
    scores_dict = {}
    for (dp, score) in sorted(list(model.alarms()), key=lambda x: x[1]):
      key = (dp.bc, dp.slice_id)
      if key in scores_dict:
        total, count = scores_dict[key]
        scores_dict[key] = (total + score, count + 1)
      else:
        scores_dict[key] = (score, 1)

    # Dump average
    for ((bc, slice_id), (total, count)) in sorted(list(scores_dict.items()), key=lambda x: x[1][0] / x[1][1]):
      avg = total / count
      s = f"{bc},{slice_id},{count},{avg}"
      f.write(s)
      if args.verbose:
        print(s, end="")

  print("Generating T-SNE Graph")

  # Dump t-SNE
  x_embedded = TSNE(n_components=2, verbose=2 if args.verbose else 0).fit_transform(x)
  predicted = model.predicted()
  if args.ground_truth:
    tp, tn, fp, fn = [], [], [], []

    def label(prediction, datapoint):
      pos = prediction < 0
      alarm = datapoint.has_alarm(alarm=args.ground_truth)
      if pos and alarm:  # True positive
        return tp
      elif not pos and not alarm:  # True negative
        return tn
      elif pos and not alarm:  # False positive
        return fp
      else:  # False negative
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
