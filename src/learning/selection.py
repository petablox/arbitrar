import numpy as np
import random

class FeatureSelection:
  def __init__(self, x):
    self.x = x

  def select(self, dst_dim

class MCMCFeatureSelection:
  """
  Metropolis-Hastings Algorithm
  """

  def __init__(self, x):
    super().__init__(x)
    (_, self.dim) = np.shape(x)

  def select(self, dst_dim: int, iteration=1000):
    mask = self.random_mask(dst_dim)
    score = self.evaluate_mask(mask)
    for i in range(iteration):
      next_mask = self.mutate_mask(mask, dst_dim)
      next_score = self.evaluate_mask(mask)
      acceptance = score / next_score
      if acceptance > random.random():
        mask = next_mask
        score = next_score
    return mask

  def random_mask(self, dst_dim):
    pass

  def evaluate_mask(self, mask):
    pass

  def mutate_mask(self, mask):
    pass
