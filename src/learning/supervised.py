import sys
import numpy as np
from sklearn.svm import SVC
from sklearn.metrics import accuracy_score, f1_score

from .unifier import unify_features
from .feature_group import FeatureGroups


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('gt', type=str, help='Ground Truth Label')


def main(args):
  db = args.db

  print("Fetching Datapoints from Database...")
  datapoints = list(db.function_datapoints(args.function))

  print("Unifying Features...")
  feature_jsons = unify_features(datapoints)
  sample_feature_json = feature_jsons[0]

  print("Generating Feature Groups and Encoder")
  feature_groups = FeatureGroups(sample_feature_json)

  print("Encoding Features...")
  xs = np.array([feature_groups.encode(feature) for feature in feature_jsons])
  ys = np.array([-1 if dp.has_label(label=args.gt) else 1 for dp in datapoints])

  print("Training...")
  model = SVC()
  model.fit(xs, ys)
  y_hat = model.predict(xs)

  acc = accuracy_score(ys, y_hat)
  print(f"Accuracy: {acc}")
