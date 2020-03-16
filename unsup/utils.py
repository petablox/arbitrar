import json
import os

def load_jsons(dir):
  for (_, _, filenames) in os.walk(dir):
    jsons = []
    for filename in filenames:
      json_dir = dir + "/" + filename
      with open(json_dir) as f:
        data = json.load(f)
        jsons.append(data)
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
        -1,
        -1,
        -1
      ]
  return retval_features

def encode_json(data):
  causality_features = encode_causality(data)
  retval_features = encode_retval(data)
  return causality_features + retval_features