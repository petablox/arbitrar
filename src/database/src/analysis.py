import os


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
