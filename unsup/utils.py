from sklearn.svm import OneClassSVM
from sklearn.ensemble import IsolationForest
import json
import os

def load_jsons(dir):
  for (_, _, filenames) in os.walk(dir):
    jsons = []
    for filename in filenames:
      json_dir = dir + "/" + filename
      with open(json_dir) as f:
        features = json.load(f)
        jsons.append({
          "file": json_dir,
          "slice_id": int(filename[0:filename.index("-")]),
          "trace_id": int(filename[filename.index("-") + 1:filename.index(".")]),
          "features": features
        })
    return jsons

def encode_causality(data):
  return [int(v) for v in data["causality"].values()]

def encode_retval(data):
  retval_features = []
  if "retval_check" in data:
    retval = data["retval_check"]
    if retval["has_retval_check"]:
      retval_features = [
        int(retval["has_retval_check"]),
        int(retval["check_branch_taken"]),
        int(retval["branch_is_zero"]),
        int(retval["branch_not_zero"])
      ]
    else:
      retval_features = [
        int(retval["has_retval_check"]),
        0, # Default
        0, # Default
        0  # Default
      ]
  return retval_features

def encode_json(data):
  causality_features = encode_causality(data["features"])
  retval_features = encode_retval(data["features"])
  return causality_features + retval_features

def ocsvm(dir, **kwargs):
  jsons = load_jsons(dir)
  x = [encode_json(data) for data in jsons]
  clf = OneClassSVM(**kwargs).fit(x)
  return jsons, x, clf

def isolation_forest(dir, **kwargs):
  jsons = load_jsons(dir)
  x = [encode_json(data) for data in jsons]
  clf = IsolationForest(random_state=0, **kwargs).fit(x)
  return jsons, x, clf