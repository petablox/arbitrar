import numpy as np
import math
from scipy import spatial
import sys

sys.setrecursionlimit(10000)


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

    # Build the KDTree for optimization
    print(f"Building KDTree...")
    kdtree = spatial.KDTree(x, leafsize=100)

    # Generate edges. All edges (i, j) are strictly i < j
    self.edges = set()
    for i in range(len(self.x)):
      print(f"Finding edge for point {i}/{len(self.x)}...", end="\r")
      p = self.x[i]
      dist, j = kdtree.query(p)
      self.edges.add((i, j))

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
        s = set()
        s.add(i)
        s.add(j)
        clusters.append(s)

    # Merge clusters if there are intersections
    self.clusters = []
    for i in range(len(clusters)):
      print(f"Merging cluster {i}/{len(clusters)}", end="\r")
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

    print(f"Entropy: {entropy}")

    return entropy
