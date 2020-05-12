def encode_feature(feature_json):
  invoked_before_features = encode_causality_dictionary(feature_json["invoked_before"])
  invoked_after_features = encode_causality_dictionary(feature_json["invoked_after"])
  retval_features = encode_retval(feature_json["retval_check"]) if "retval_check" in feature_json else []
  argval_0_features = encode_argval(feature_json["argval_0_check"]) if "argval_0_check" in feature_json else []
  argval_1_features = encode_argval(feature_json["argval_1_check"]) if "argval_1_check" in feature_json else []
  argval_2_features = encode_argval(feature_json["argval_2_check"]) if "argval_2_check" in feature_json else []
  argval_3_features = encode_argval(feature_json["argval_3_check"]) if "argval_3_check" in feature_json else []
  return invoked_before_features + invoked_after_features + retval_features + \
         argval_0_features + argval_1_features + argval_2_features + argval_3_features


def encode_causality(causality):
  fields = ["invoked_more_than_once", "share_argument", "share_return_value"]
  if causality["invoked"]:
    return [1] * len(fields) + [causality[f] for f in fields]
  else:
    return [0] * (2 * len(fields))


def encode_causality_dictionary(causality_dict):
  return [int(causality_dict[key]) for key in sorted(causality_dict)]


def encode_retval(retval):
  fields = ["check_branch_taken", "branch_is_zero", "branch_not_zero"]
  if retval["has_retval_check"]:
    return [1] * len(fields) + [retval[f] for f in fields]
  else:
    return [0] * (2 * len(fields))


def encode_argval(argval):
  fields = ["check_branch_taken", "branch_is_zero", "branch_not_zero"]
  if argval["has_argval_check"]:
    return [1] * len(fields) + [argval[f] for f in fields]
  else:
    return [0] * (2 * len(fields))