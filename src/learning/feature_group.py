from enum import Enum
from functools import reduce
from typing import List, Tuple
import operator

import numpy as np

from . import utils


class FeatureGroups:
  def __init__(self, sample_feature_json, enable_causality=True, enable_retval=True, enable_argval=True, fix_causality=False, fix_retval=False, fix_argval=False):
    self.groups = []
    if enable_causality:
      for invoked_type in InvokedType:
        for function_name in sample_feature_json[invoked_type]:
          self.groups.append(CausalityFeatureGroup(fix_causality, invoked_type, function_name))
    if enable_retval:
      self.groups.append(RetvalFeatureGroup(fix_retval))
    if enable_argval:
      for arg_i in [0, 1, 2, 3]:
        argval_group = ArgvalFeatureGroup(fix_argval, arg_i)
        if utils.has_dot_separated_field(sample_feature_json, argval_group.field()):
          self.groups.append(argval_group)

  def meaning_of(self, i) -> str:
    """
    Get the meaning of i-th element inside the encoded feature vector
    """
    counter = 0
    for g in self.groups:
      offset = i - counter
      if offset < g.num_features():
        return g.meaning_of(offset)
    raise Exception(f"Unknown meaning of {i}")

  def encode(self, feature_json) -> np.ndarray:
    """
    Encode the feature json into an np.array
    """
    return np.array(reduce(operator.add, [g.encode(feature_json) for g in self.groups], []))

  def num_features(self) -> int:
    return reduce(operator.add, [g.num_features() for g in self.groups])

  def num_feature_groups(self) -> int:
    return len(self.groups)

  def indices(self) -> List[Tuple[int, int]]:
    """
    Return: List of (start, end)
    """
    indices, counter = [], 0
    for g in self.groups:
      groups.append((counter, counter + g.num_features()))
      counter += g.num_features()
    return indices


class FeatureGroup:
  fields = []

  def __init__(self, fixed: bool):
    self.fixed = fixed

  def field(self) -> str:
    raise Exception("Not implemented")

  def meaning_of(self, i) -> str:
    raise Exception("Not implemented")

  def num_features(self) -> int:
    return len(self.fields)

  def encode(self, feature_json) -> List[int]:
    j = utils.get_dot_separated_field(feature_json, self.field())
    return [int(j[f]) for f in self.fields]


class ArgvalFeatureGroup(FeatureGroup):
  fields = ["has_argval_check", "check_branch_taken", "branch_is_zero", "branch_not_zero"]

  def __init__(self, fixed, arg_i):
    super().__init__(fixed)
    self.arg_i = arg_i

  def field(self) -> str:
    return f"argval_{self.arg_i}_check"

  def meaning_of(self, i) -> str:
    return f"argval.{self.arg_i}.{self.fields[i]}"


class RetvalFeatureGroup(FeatureGroup):
  fields = ["has_retval_check", "check_branch_taken", "branch_is_zero", "branch_not_zero"]

  def __init__(self, fixed):
    super().__init__(fixed)

  def field(self) -> str:
    return "retval_check"

  def meaning_of(self, i) -> str:
    return f"retval.{self.fields[i]}"


class InvokedType(Enum):
  BEFORE = "invoked_before"
  AFTER = "invoked_after"


class CausalityFeatureGroup(FeatureGroup):
  fields = ["invoked", "invoked_more_than_once", "share_argument", "share_return_value", "same_context"]

  def __init__(self, fixed: bool, invoked_type: InvokedType, function_name: str):
    super().__init__(fixed)
    self.invoked_type = invoked_type
    self.function_name = function_name

  def field(self) -> str:
    return f"{self.invoked_type}.{self.function_name}"

  def meaning_of(self, i) -> str:
    return f"{self.invoked_type}.{self.function_name}.{self.fields[i]}"
