import sys
import numpy as np
import math
import itertools
import matplotlib as mpl
from scipy import linalg
from sklearn import mixture
from scipy import spatial

sys.setrecursionlimit(10000)


class Fitness:
  def __init__(self, x, args):
    pass

  def value(self):
    raise NotImplemented()

  def plot(self, ax):
    pass


class MinimumDistanceCluster(Fitness):
  """
  Minimum Distance Cluster + Entropy

  We group cluster by connected components which edges are drawn between
  the closest points. Then we calculate the entropy ($\Sum p \log p$) of
  the dataset.
  """
  def __init__(self, x, args):
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


class GaussianMixtureCluster(Fitness):
  """
  Gaussian Mixture Cluster + Entropy
  """
  def __init__(self, x, args):
    """
    Initialize the Gaussian Mixture Model
    """
    self.x = x
    self.dim = np.shape(x)[1]
    self.n_components = args.gmc_n_components

    # Get the predicted y
    self.model = mixture.GaussianMixture(n_components=self.n_components).fit(self.x)
    self.predicted_proba = self.model.predict_proba(self.x)

    # Calculate
    self.y_counts = np.array([0 for _ in range(self.n_components)])
    for proba in self.predicted_proba:
      self.y_counts = np.add(self.y_counts, proba)

  def value(self):
    total = len(self.x)

    entropy = 0
    for count in self.y_counts:
      p = count / total
      entropy -= p * math.log(p)

    return entropy

  def plot(self, ax):
    if self.dim != 2:
      print("Skipping plot Gaussian Mixture Clusters")
      return False

    colors = itertools.cycle(['navy', 'c', 'cornflowerblue', 'gold', 'darkorange'])
    means = self.model.means_
    covariances = self.model.covariances_

    for i, (mean, covar, color) in enumerate(zip(means, covariances, colors)):
      v, w = linalg.eigh(covar)
      v = 2. * np.sqrt(2.) * np.sqrt(v)
      u = w[0] / linalg.norm(w[0])

      # Plot an ellipse to show the Gaussian component
      angle = np.arctan(u[1] / u[0])
      angle = 180. * angle / np.pi  # convert to degrees
      ell = mpl.patches.Ellipse(mean, v[0], v[1], 180. + angle, color=color)
      ell.set_clip_box(ax.bbox)
      ell.set_alpha(0.5)
      ax.add_artist(ell)
