import numpy as np
import random

from .fitness import GaussianMixtureCluster
from .utils import index_of_ith_one

class FeatureSelection:
  def __init__(self):
    pass

  def select(self):
    pass


class MCMCFeatureSelection(FeatureSelection):
  """
  Metropolis-Hastings Algorithm + GMC
  """

  def __init__(self, x, dst_dim, args):
    self.x = x
    (_, self.src_dim) = np.shape(x)
    self.dst_dim = dst_dim
    self.num_zeros = self.src_dim - self.dst_dim
    self.args = args

  def select(self, iteration=1000):
    print("Selecting feature with MCMC")
    mask = self.random_mask()
    score = self.evaluate_mask(mask)
    print(f"Initializing: score {score}")
    best_mask = mask.copy()
    best_score = score.copy()
    for i in range(iteration):
      next_mask = self.mutate_mask(mask)
      next_score = self.evaluate_mask(next_mask)
      print(" " * 100, end="\r")
      print(f"Iteration {i}: Sampled next mask, scored {next_score}... ", end="")
      if self.meet_regulation(next_score):
        acceptance = next_score / score
        if acceptance > random.random():
          mask = next_mask
          score = next_score
          if score > best_score:
            best_mask = mask
            best_score = score
            print("New High Score!", end="\r")
          else:
            print("Proceeding", end="\r")
        else:
          print("Rejecting", end="\r")
      else:
        mask = next_mask
        score = next_score
        print("Too Big. Proceeding", end="\r")
    print(f"Final mask {best_mask} scored {best_score}")
    return best_mask

  def meet_regulation(self, score):
    return self.args.mcmc_score_regulation == None or next_score < self.args.mcmc_score_regulation

  def random_mask(self):
    v = np.full(self.src_dim, 0) # Create a vector of dimension dim with everything 0
    v[:self.dst_dim] = True # Set the first 0 - dst_dim to 1
    np.random.shuffle(v) # Shuffle the mask
    return v

  def mutate_mask(self, mask):
    new_mask = mask.copy()
    turn_zero_index = int(random.random() * self.num_zeros)
    turn_one_index = int(random.random() * self.dst_dim)
    turn_zero_i = -1
    turn_one_i = -1
    for i in range(self.src_dim):
      n = new_mask[i]
      if n == 0:
        turn_zero_i += 1
        if turn_zero_i == turn_zero_index:
          new_mask[i] = 1
      else:
        turn_one_i += 1
        if turn_one_i == turn_one_index:
          new_mask[i] = 0
    return new_mask

  def masked_x(self, mask):
    mask_mat = np.transpose(np.matrix([
      [1 if index_of_ith_one(mask, i) == j else 0 for j in range(self.src_dim)] for i in range(self.dst_dim)
    ]))
    masked_x = self.x * mask_mat
    return masked_x

  def evaluate_mask(self, mask):
    masked_x = self.masked_x(mask)
    model = GaussianMixtureCluster(masked_x, self.args)
    score = model.value()

    # Entropy score is the lower the better.
    # We want the higher the better.
    return 1.0 / score