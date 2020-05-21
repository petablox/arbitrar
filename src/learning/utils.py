import numpy as np


class BoundingBox:
  def __init__(self, x):
    self.minv, self.maxv = x[0], x[0]
    for i in range(1, len(x)):
      self.minv = np.minimum(x[i], minv)
      self.maxv = np.maximum(x[i], maxv)

  def size(self):
    return self.maxv - self.minv


class SpatialHashTable:
  def __init__(self, x, div=10):
    # Get the bounding box for the table
    self.bb = BoundingBox(x)

    # Minimum Amount of Diff
    min_diff = np.amin(self.bb.size())
