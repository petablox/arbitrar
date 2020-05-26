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
    for arg_i in [0, 1, 2, 3]:
      field = f"argval_{arg_i}_check"
      features += encode_argval(feature_json[field]) if field in feature_json else []

  return features


def encode_causality(causality):
  fields = ["invoked", "invoked_more_than_once", "share_argument", "share_return_value", "same_context"]
  return [int(causality[f]) for f in fields]


def encode_causality_dictionary(causality_dict):
  return [i for key in sorted(causality_dict) for i in encode_causality(causality_dict[key])]


def encode_retval(retval):
  fields = ["has_retval_check", "check_branch_taken", "branch_is_zero", "branch_not_zero"]
  return [int(retval[f]) if retval[f] != None else 0 for f in fields]


def encode_argval(argval):
  fields = ["has_argval_check", "check_branch_taken", "branch_is_zero", "branch_not_zero"]
  return [int(argval[f]) if argval[f] != None else 0 for f in fields]


def ith_meaning(sample_feature_json, i, enable_causality=True, enable_retval=True, enable_argval=True):
  counter = 0
  if enable_causality:

    # Invoked before
    inv_bef = encode_causality_dictionary(sample_feature_json["invoked_before"])
    if (i - counter) < len(inv_bef):
      cd_meaning = ith_meaning_of_causality_dictionary(sample_feature_json["invoked_before"], i - counter)
      return f"invoked_before.{cd_meaning}"
    counter += len(inv_bef)

    # Invoked after
    inv_aft = encode_causality_dictionary(sample_feature_json["invoked_after"])
    if (i - counter) < len(inv_aft):
      cd_meaning = ith_meaning_of_causality_dictionary(sample_feature_json["invoked_after"], i - counter)
      return f"invoked_after.{cd_meaning}"
    counter += len(inv_aft)

  if enable_retval:
    rtv = encode_retval(sample_feature_json["retval_check"]) if "retval_check" in sample_feature_json else []
    if (i - counter) < len(rtv):
      rt_meaning = ith_meaning_of_retval(sample_feature_json["retval_check"], i - counter)
      return f"retval.{rt_meaning}"
    counter += len(rtv)

  if enable_argval:
    for arg_i in [0, 1, 2, 3]:
      field_name = f"argval_{arg_i}_check"
      agv = encode_argval(sample_feature_json[field_name]) if field_name in sample_feature_json else []
      if (i - counter) < len(agv):
        ag_meaning = ith_meaning_of_argval(sample_feature_json[field_name], i - counter)
        return f"argval.{arg_i}.{ag_meaning}"
      counter += len(agv)

  raise Exception(f"Unknown meaning of index {i}")


def ith_meaning_of_causality_dictionary(causality_dict, i):
  counter = 0
  for key in sorted(causality_dict):
    caus = encode_causality(causality_dict[key])
    if (i - counter) < len(caus):
      return f"{key}.{ith_meaning_of_causality(causality_dict[key], i - counter)}"
    counter += len(caus)

  raise Exception(f"Unknown meaning of index {i} in causality dictionary")


def ith_meaning_of_causality(causality, i):
  return ["invoked", "invoked_more_than_once", "share_argument", "share_return_value", "same_context"][i]


def ith_meaning_of_retval(retval_check, i):
  return ["has_retval_check", "check_branch_taken", "branch_is_zero", "branch_not_zero"][i]


def ith_meaning_of_argval(argval_check, i):
  return ["has_argval_check", "check_branch_taken", "branch_is_zero", "branch_not_zero"][i]
