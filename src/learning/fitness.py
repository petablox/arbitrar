import numpy as np
import math


class Fitness:
  def __init__(self, x):
    pass

  def value(self):
    raise NotImplemented()

  def plot(self):
    pass


class MinimumDistanceCluster(Fitness):
  """
  Minimum Distance Cluster + Entropy

  We group cluster by connected components which edges are drawn between
  the closest points. Then we calculate the entropy ($\Sum p \log p$) of
  the dataset.
  """
  def __init__(self, x):
    """
    Initialize the fitness model. Compute all the edges & clusters.
    """
    self.x = x

    # Generate edges. All edges (i, j) are strictly i < j
    self.edges = set()
    for i in range(len(self.x)):
      j = self.get_closest_point_index(i)
      edge = (i, j) if i < j else (j, i)
      self.edges.add(edge)

    # Generate cluster (without merging)
    clusters = []
    for edge in self.edges:
      (i, j) = edge

      # First see if i or j is in existing cluster
      existed = False
      for cluster in clusters:
        if i in cluster or j in cluster:
          cluster.add(i)
          cluster.add(j)
          existed = True
          break

      # If neither is in existing cluster
      if not existed:
        clusters.append(set(i, j))

    # Merge clusters if there are intersections
    self.clusters = []
    for i in range(len(clusters)):
      c1 = clusters[i]

      # Check if c1 is empty
      if len(c1) == 0:
        continue

      # Join all the clusters that has intersection with c1
      for j in range(i + 1, len(clusters)):
        c2 = clusters[j]
        if not c1.isdisjoint(c2):
          c1.update(c2)
          c2.clear()

      # Store c1 as a cluster
      self.clusters.append(c1)

  def get_closest_point_index(self, p_index: int):
    """
    Given an index of a point, get the index of its closest point
    """
    p = self.x[p_index]
    min_i = None
    min_dist = None
    for i in range(len(self.x)):
      if i != p_index:
        p_other = self.x[i]
        dist = np.linalg.norm(p - p_other)
        if min_dist == None or dist < min_dist:
          min_i = i
          min_dist = dist

  def value(self):
    """
    Calculate the entropy of this dataset based on clusters
    """
    total = len(self.x)

    entropy = 0
    for cluster in self.clusters:
      count = len(cluster)
      p = count / total
      entropy -= p * math.log(p)

    return entropy
