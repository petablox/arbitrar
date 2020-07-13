import os
import json


class DataPoint:
  def __init__(self, db, func_name, bc, slice_id, trace_id, slice=None, dugraph=None, feature=None):
    self.db = db
    self.func_name = func_name
    self.bc = bc
    self.slice_id = slice_id
    self.trace_id = trace_id

    # Private caches
    self._slice = slice
    self._dugraph = dugraph
    self._feature = feature

  def slice(self):
    if not self._slice:
      self._slice = self.db.slice(self.func_name, self.bc, self.slice_id)
    return self._slice

  def dugraph(self):
    if not self._dugraph:
      self._dugraph = self.db.dugraph(self.func_name, self.bc, self.slice_id, self.trace_id)
    return self._dugraph

  def feature(self):
    if not self._feature:
      self._feature = self.db.feature(self.func_name, self.bc, self.slice_id, self.trace_id)
    return self._feature

  def labels(self):
    dugraph = self.dugraph()
    return dugraph["labels"] if "labels" in dugraph and dugraph["labels"] else []

  def alarms(self):
    return [a for a in self.labels() if "alarm" in a]

  def has_label(self, label=None):
    if label:
      for l in self.labels():
        if label in l:
          return True
      return False
    else:
      return len(self.labels()) > 0


class FunctionSpec:
  def __init__(self, path):
    if not os.path.exists(path):
      raise ValueError(f"#{path} for function spec does not exist")
    with open(path) as f:
      self.spec_str = f.read()
    self.spec = eval(self.spec_str)
    print(self.spec_str)
    print(self.spec)

  def match(self, dp):
    f = dp.feature()
    return self.spec(f)
