from enum import Enum
from functools import reduce
from typing import Optional, List, Tuple
import operator

import numpy as np

from . import utils


class FeatureGroup:
  fields = []

  def __init__(self, fixed=False):
    self.fixed = fixed

  def field(self) -> str:
    raise Exception("Not implemented")

  def meaning_of(self, i) -> str:
    raise Exception("Not implemented")

  def num_features(self) -> int:
    return len(self.fields)

  def encode(self, feature_json) -> List[int]:
    j = self.get_from_json(feature_json)
    if j != None and isinstance(j, dict):
      try:
        return [int(j[f]) if j[f] != None else -1 for f in self.fields]
      except:
        print(j, self.fields)
        exit()
    else:
      raise Exception(f"Cannot get field {self.field()} from json {feature_json}")

  def get_from_json(self, feature_json):
    return feature_json[self.field()]

  def contained_in_json(self, feature_json):
    return self.field() in feature_json


class ControlFlowFeatureGroup(FeatureGroup):
  fields = ["has_loop", "target_in_a_loop", "has_cond_br_after_target"]

  def field(self) -> str:
    return "control_flow"

  def meaning_of(self, i) -> str:
    return f"control_flow.{self.fields[i]}"


class LoopFeatureGroup(FeatureGroup):
  fields = ["has_loop", "target_in_a_loop"]

  def field(self) -> str:
    return "loop"

  def meaning_of(self, i) -> str:
    return f"loop.{self.fields[i]}"


class ArgPreFeatureGroup(FeatureGroup):
  fields = ["checked", "compared_with_zero", "arg_check_is_zero", "arg_check_not_zero", "is_constant", "is_global"]

  def __init__(self, arg_i, fixed=False):
    super().__init__(fixed)
    self.arg_i = arg_i

  def field(self) -> str:
    return f"arg.{self.arg_i}.pre"

  def meaning_of(self, i) -> str:
    return f"arg.{self.arg_i}.pre.{self.fields[i]}"


class ArgPostFeatureGroup(FeatureGroup):
  fields = ["used", "used_in_call", "used_in_check", "derefed", "returned", "indir_returned"]

  def __init__(self, arg_i, fixed=False):
    super().__init__(fixed)
    self.arg_i = arg_i

  def field(self) -> str:
    return f"arg.{self.arg_i}.post"

  def meaning_of(self, i) -> str:
    return f"arg.{self.arg_i}.post.{self.fields[i]}"


class RetvalFeatureGroup(FeatureGroup):
  fields = ["derefed", "stored", "returned", "indir_returned"]

  def __init__(self, fixed=False):
    super().__init__(fixed)

  def field(self) -> str:
    return "ret"

  def meaning_of(self, i) -> str:
    return f"ret.{self.fields[i]}"


class RetvalCheckFeatureGroup(FeatureGroup):
  fields = ["checked", "slice_checked", "br_eq_zero", "br_neq_zero", "compared_with_non_const", "compared_with_zero"]

  def __init__(self, fixed=False):
    super().__init__(fixed)

  def field(self) -> str:
    return "ret.check"

  def meaning_of(self, i) -> str:
    return f"ret.check.{self.fields[i]}"


class InvokedType(Enum):
  BEFORE = "before"
  AFTER = "after"


class CausalityFeatureGroup(FeatureGroup):
  fields = ["invoked", "invoked_more_than_once", "share_argument", "share_return"]

  def __init__(self, invoked_type: InvokedType, function_name: str, fixed=False):
    super().__init__(fixed)
    self.invoked_type = invoked_type
    self.function_name = function_name

  def field(self) -> str:
    return f"{self.invoked_type.value}.{self.function_name}"

  def meaning_of(self, i) -> str:
    return f"{self.invoked_type.value}.{self.function_name}.{self.fields[i]}"

  @staticmethod
  def default() -> dict:
    return {f: False for f in CausalityFeatureGroup.fields}

  def get_from_json(self, feature_json):
    return utils.get_dot_separated_field(feature_json, self.field())

  def contained_in_json(self, feature_json):
    return utils.has_dot_separated_field(feature_json, self.field())


class FeatureGroups:
  def __init__(self,
               sample_feature_json,
               enable_loop=True,
               enable_control_flow=True,
               enable_causality=True,
               enable_retval=True,
               enable_argval=True,
               fix_groups=[]):
    self.groups = []

    if enable_loop:
      group = LoopFeatureGroup()
      if group.contained_in_json(sample_feature_json):
        self.groups.append(group)

    if enable_control_flow:
      group = ControlFlowFeatureGroup()
      if group.contained_in_json(sample_feature_json):
        self.groups.append(group)

    if enable_causality:
      for invoked_type in InvokedType:
        for function_name in sample_feature_json[invoked_type.value]:
          self.groups.append(CausalityFeatureGroup(invoked_type, function_name))

    if enable_retval:
      retval_group = RetvalFeatureGroup()
      if retval_group.contained_in_json(sample_feature_json):
        self.groups.append(retval_group)

      retval_check_group = RetvalCheckFeatureGroup()
      if retval_group.contained_in_json(sample_feature_json):
        self.groups.append(retval_check_group)

    if enable_argval:
      for arg_i in [0, 1, 2, 3]:
        ith_arg_pre_group = ArgPreFeatureGroup(arg_i)
        ith_arg_post_group = ArgPostFeatureGroup(arg_i)
        if ith_arg_pre_group.contained_in_json(sample_feature_json):
          self.groups.append(ith_arg_pre_group)
          self.groups.append(ith_arg_post_group)

  @staticmethod
  def try_fix(group: FeatureGroup, fix_groups: List[str]):
    if should_be_fixed(group, fix_groups):
      group.fixed = True

  @staticmethod
  def should_be_fixed(group: FeatureGroup, fix_groups: List[str]) -> bool:
    for fix_group in fix_groups:
      if fix_group in group.field():
        return True
    return False

  def meaning_of(self, i: int) -> str:
    """
    Get the meaning of i-th element inside the encoded feature vector
    """
    counter = 0
    for g in self.groups:
      offset = i - counter
      if offset < g.num_features():
        return g.meaning_of(offset)
      counter += g.num_features()
    raise Exception(f"Unknown meaning of {i}")

  def __iter__(self):
    for g in self.groups:
      yield g

  def __getitem__(self, key: int) -> FeatureGroup:
    return self.groups[key]

  def __len__(self) -> int:
    return len(self.groups)

  def get_from_json(self, feature_json):
    return {g.field(): g.get_from_json(feature_json) for g in self.groups}

  def encode(self, feature_json) -> np.ndarray:
    """
    Encode the feature json into an np.array
    """
    return np.array(reduce(operator.add, [g.encode(feature_json) for g in self.groups], []))

  def num_features(self) -> int:
    return reduce(operator.add, [g.num_features() for g in self.groups])

  def num_feature_groups(self) -> int:
    return len(self.groups)

  def ith_group(self, i: int) -> FeatureGroup:
    return self.groups[i]

  def num_fixed_feature_groups(self) -> int:
    return reduce(lambda s, g: s + 1 if g.fixed else s, self.groups, 0)

  def num_non_fixed_feature_groups(self) -> int:
    return reduce(lambda s, g: s + 1 if not g.fixed else s, self.groups, 0)

  def indices(self) -> List[Tuple[int, int]]:
    """
    Return: List of (start, end)
    """
    indices, counter = [], 0
    for g in self.groups:
      indices.append((counter, counter + g.num_features()))
      counter += g.num_features()
    return indices
