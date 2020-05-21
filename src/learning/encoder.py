def encode_feature(feature_json, enable_causality=True, enable_retval=True, enable_argval=True):
  features = []

  # Causality features
  if enable_causality:
    features += encode_causality_dictionary(feature_json["invoked_before"])
    features += encode_causality_dictionary(feature_json["invoked_after"])

  # Return value features
  if enable_retval:
    features += encode_retval(feature_json["retval_check"]) if "retval_check" in feature_json else []

  # Argument value features
  if enable_argval:
    features += encode_argval(feature_json["argval_0_check"]) if "argval_0_check" in feature_json else []
    features += encode_argval(feature_json["argval_1_check"]) if "argval_1_check" in feature_json else []
    features += encode_argval(feature_json["argval_2_check"]) if "argval_2_check" in feature_json else []
    features += encode_argval(feature_json["argval_3_check"]) if "argval_3_check" in feature_json else []

  return features


def encode_causality(causality):
  fields = ["invoked_more_than_once", "share_argument", "share_return_value"]  #, "same_context"]
  if causality["invoked"]:
    return [1] * len(fields) + [causality[f] for f in fields]
  else:
    return [0] * (2 * len(fields))


def encode_causality_dictionary(causality_dict):
  return [i for key in sorted(causality_dict) for i in encode_causality(causality_dict[key])]


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
