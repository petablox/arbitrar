import numpy as np
import random

from .fitness import GaussianMixtureClusterEntropy
from .utils import index_of_ith_one
from .feature_group import FeatureGroup, FeatureGroups


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
    return self.args.mcmc_score_regulation == None or score < self.args.mcmc_score_regulation

  def random_mask(self):
    v = np.full(self.src_dim, 0)  # Create a vector of dimension dim with everything 0
    v[:self.dst_dim] = True  # Set the first 0 - dst_dim to 1
    np.random.shuffle(v)  # Shuffle the mask
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
    mask_mat = np.transpose(
        np.matrix([[1 if index_of_ith_one(mask, i) == j else 0 for j in range(self.src_dim)]
                   for i in range(self.dst_dim)]))
    masked_x = self.x * mask_mat
    return masked_x

  def evaluate_mask(self, mask):
    masked_x = self.masked_x(mask)
    model = GaussianMixtureClusterEntropy(masked_x, self.args)
    score = model.value()

    # Entropy score is the lower the better.
    # We want the higher the better.
    return 1.0 / score


class MCMCFeatureGroupSelection(FeatureSelection):
  def __init__(self, x: np.ndarray, groups: FeatureGroups, dst_groups_dim: int, args):
    self.x = x
    (_, self.src_dim) = np.shape(x)
    self.groups = groups
    self.group_indices = groups.indices()
    self.src_groups_dim = self.groups.num_feature_groups()
    self.dst_groups_dim = dst_groups_dim
    self.num_zeros = self.src_groups_dim - self.dst_groups_dim
    self.args = args

  def select(self, iteration=1000):

    # Initialize group mask
    print("Selecting feature with MCMC")
    mask = self.random_group_mask()
    score = self.evaluate_group_mask(mask)

    # Initialize best mask
    print(f"Initializing: score {score}")
    best_mask = mask.copy()
    best_score = score.copy()

    # Start iteration
    for i in range(iteration):

      # Mutate the mask and calculate the next score
      next_mask = self.mutate_group_mask(mask)
      next_score = self.evaluate_group_mask(next_mask)
      print(" " * 100, end="\r")
      print(f"Iteration {i}: Sampled next mask, scored {next_score}... ", end="")

      # Check regulation
      if self.meet_regulation(next_score):

        # Calculate acceptance
        acceptance = next_score / score
        if acceptance > random.random():

          # If proceed, update the current mask and score
          mask = next_mask
          score = next_score

          # If is the best score, update
          if score > best_score:
            best_mask = mask
            best_score = score
            print("New High Score!", end="\r")
          else:
            print("Proceeding", end="\r")
        else:

          # Else, do nothing
          print("Rejecting", end="\r")
      else:
        mask = next_mask
        score = next_score
        print("Too Big. Proceeding", end="\r")

    # Return the best mask found
    print(" " * 100, end="\r")
    print(f"Final mask {best_mask} scored {best_score}")
    return self.feature_mask(best_mask)  # Return the feature mask

  def meet_regulation(self, score):
    return self.args.mcmc_score_regulation == None or score < self.args.mcmc_score_regulation

  def random_group_mask(self):
    num_fixed = self.groups.num_fixed_feature_groups()
    num_non_fixed = self.groups.num_non_fixed_feature_groups()
    num_variables = self.dst_groups_dim - num_fixed
    num_groups = self.groups.num_feature_groups()

    if num_variables > 0:

      # Create a random mask for variable bits
      v = np.full(num_non_fixed, 0)  # Create a vector of non_fixed dimension
      v[:num_variables] = 1  # Set the first 0 - variable to 1
      np.random.shuffle(v)  # Shuffle the mask

      # Fill in the full mask where fixed bit is set to 1 and variable bit is set to v
      ret = []
      counter = 0
      for i in range(num_groups):
        if self.groups[i].fixed:
          ret.append(1)
        else:
          ret.append(v[counter])
          counter += 1

      # Create np array
      return np.array(ret)

    else:

      # If nothing is variable, then just return a mask where fixed groups are enabled
      return np.array([int(g.fixed) for g in self.groups])

  def mutate_group_mask(self, group_mask):
    num_variables = self.dst_groups_dim - self.groups.num_fixed_feature_groups()
    if num_variables > 0:
      new_mask = group_mask.copy()
      turn_zero_index = int(random.random() * self.num_zeros)
      turn_one_index = int(random.random() * num_variables)
      turn_zero_i = -1
      turn_one_i = -1
      for i in range(len(self.groups)):
        n = new_mask[i]
        if n == 0:
          turn_zero_i += 1
          if turn_zero_i == turn_zero_index:
            new_mask[i] = 1
        else:  # n == 1
          if not self.groups[i].fixed:
            turn_one_i += 1
            if turn_one_i == turn_one_index:
              new_mask[i] = 0
      return new_mask
    else:
      return group_mask

  def feature_mask(self, group_mask):
    mask = np.full(self.src_dim, 0)
    for i in range(len(self.groups)):
      (start, end) = self.group_indices[i]
      if group_mask[i] == 1:
        for j in range(start, end):
          mask[j] = 1
    return mask

  def group_masked_x(self, group_mask):
    mask = self.feature_mask(group_mask)
    return self.masked_x(mask)

  def masked_x(self, mask):
    num_ones = sum(mask)  # Number of ones in a mask (with only 0 and 1s) is sum of the mask
    mask_mat = np.transpose(
        np.matrix([[1 if index_of_ith_one(mask, i) == j else 0 for j in range(self.src_dim)] for i in range(num_ones)]))
    masked_x = self.x * mask_mat
    return masked_x

  def evaluate_group_mask(self, group_mask):
    masked_x = self.group_masked_x(group_mask)
    model = GaussianMixtureClusterEntropy(masked_x, self.args)
    score = model.value()

    # Entropy score is the lower the better.
    # We want the higher the better.
    return 1.0 / score
