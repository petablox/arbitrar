from typing import Dict, Type
import os
import numpy as np
import joblib
import sys
import json

import matplotlib.pyplot as plt
from sklearn.manifold import TSNE
# from tsnecuda import TSNE

from src.database import Database, DataPoint

from .utils import index_of_ith_one
from .unsupervised_learner import ocsvm, isolation_forest
from .unsupervised_learner.meta import Model
from .fitness import MinimumDistanceClusterEntropy, GaussianMixtureClusterEntropy
from .selection import MCMCFeatureSelection, MCMCFeatureGroupSelection
from .feature_group import FeatureGroups
from .unifier import unify_features, unify_features_with_sample

models: Dict[str, Type[Model]] = {"ocsvm": ocsvm.OCSVM, "isolation-forest": isolation_forest.IF}

fitness_functions = {"mdc": MinimumDistanceClusterEntropy, "gmc": GaussianMixtureClusterEntropy}

feature_selector = {"mcmc-feature": MCMCFeatureSelection, "mcmc-feature-group": MCMCFeatureGroupSelection}


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('-m', '--model', type=str, default='ocsvm', help='Model (ocsvm)')
  parser.add_argument('-g', '--ground-truth', type=str, help='Ground Truth Label')
  parser.add_argument('-s', '--seed', type=int, default=1234)
  parser.add_argument('-v', '--verbose', action='store_true')
  parser.add_argument('-i', '--input', type=str)
  parser.add_argument('--train-with-embedded', action='store_true')

  # Feature Settings
  parser.add_argument('--no-causality', action='store_true', help='Does not include causality features')
  parser.add_argument('--no-retval', action='store_true', help='Does not include retval features')
  parser.add_argument('--no-argval', action='store_true', help='Does not include argval features')

  # Feature selection
  parser.add_argument('--enable-feature-selection', action='store_true')
  parser.add_argument('--feature-selector', type=str, default='mcmc-feature-group')
  parser.add_argument('--fitness-function', type=str, default='gmc')
  parser.add_argument('--fitness-dimension', type=int, default=2, help='The dimension used to compute fitness')
  # parser.add_argument('--visualize-fitness', action='store_true', help='Output the fitness function') # Enabled always

  # Gaussian Mixture Model
  parser.add_argument('--gmc-n-components', type=int, default=5)

  # MCMC
  parser.add_argument('--mcmc-iteration', type=int, default=200)
  parser.add_argument('--mcmc-score-regulation', type=int)
  parser.add_argument('--num-features', type=int, default=5)
  parser.add_argument('--num-feature-groups', type=int, default=3)
  parser.add_argument('--fix-retval', action='store_true')
  parser.add_argument('--fix-argval', action='store_true')
  parser.add_argument('--fix-group', type=str, nargs='+', default=[])

  # OCSVM Parameters
  parser.add_argument('--kernel', type=str, default='rbf', help='OCSVM Kernel')
  parser.add_argument('--nu', type=float, default=0.01, help='OCSVM nu')

  # Isolation Forest Parameters
  parser.add_argument('--contamination', type=float, default=0.01, help="Isolation Forest Contamination")


def main(args):
  np.random.seed(args.seed)
  if args.input:
    test(args)
  else:
    train_and_test(args)


def test(args):
  db = args.db

  input_exp_dir = os.path.join(os.getcwd(), args.input)
  clf_dir = f"{input_exp_dir}/model.joblib"
  clf = joblib.load(clf_dir)

  unified_dir = f"{input_exp_dir}/unified.json"
  with open(unified_dir) as f:
    unified = json.load(f)

  datapoints = list(db.function_datapoints(args.function))
  feature_jsons = unify_features_with_sample(datapoints, unified)
  sample_feature_json = feature_jsons[0]

  fix_groups = args.fix_group
  if args.fix_retval:
    fix_groups.append("retval")
  if args.fix_argval:
    fix_groups.append("argval")
  feature_groups = FeatureGroups(sample_feature_json,
                                 enable_causality=not args.no_causality,
                                 enable_retval=not args.no_retval,
                                 enable_argval=not args.no_argval,
                                 fix_groups=fix_groups)

  x = np.array([feature_groups.encode(feature) for feature in feature_jsons])
  model = get_model(args)(datapoints, x, clf)

  exp_dir = db.new_learning_dir(args.function)

  # Dump the command line arguments
  with open(f"{exp_dir}/log.txt", "w") as f:
    f.write(str(sys.argv))

  # Dump the raised alarms
  with open(f"{exp_dir}/alarms.csv", "w") as f:
    f.write("bc,slice_id,trace_id,alarm,score,alarms\n")
    for (dp, p, score) in sorted(list(model.results()), key=lambda x: x[1]):
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{p < 0},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)
      if args.verbose:
        print(s, end="")


def train_and_test(args):
  db = args.db
  model_fn = get_model(args)
  fitness_function = get_fitness_function(args)

  print("Fetching Datapoints From Database...")
  datapoints = list(db.function_datapoints(args.function))

  print("Unifying Features...")
  feature_jsons = unify_features(datapoints)
  sample_feature_json = feature_jsons[0]

  fix_groups = args.fix_group
  if args.fix_retval:
    fix_groups.append("retval")
  if args.fix_argval:
    fix_groups.append("argval")
  feature_groups = FeatureGroups(sample_feature_json,
                                 enable_causality=not args.no_causality,
                                 enable_retval=not args.no_retval,
                                 enable_argval=not args.no_argval,
                                 fix_groups=fix_groups)

  print("Encoding Features...")
  x = np.array([feature_groups.encode(feature) for feature in feature_jsons])

  if args.enable_feature_selection:
    print(f"Using feature selection {args.feature_selector}...")
    if args.feature_selector == 'mcmc-feature':
      selector = MCMCFeatureSelection(x, args.num_features, args)
      mask = selector.select(iteration=args.mcmc_iteration)
      x = selector.masked_x(mask)
    elif args.feature_selector == 'mcmc-feature-group':
      selector = MCMCFeatureGroupSelection(x, feature_groups, args.num_feature_groups, args)
      mask = selector.select(iteration=args.mcmc_iteration)
      x = selector.masked_x(mask)

  (num_datapoints, dim) = np.shape(x)

  print("Embedding Fitness with TSNE...")
  tsne_fitter = TSNE(n_components=args.fitness_dimension, verbose=2 if args.verbose else 0)
  x_fitness = tsne_fitter.fit_transform(x)

  # Computing Entropy
  print("Computing Fitness Function for the Dataset")
  fit = fitness_function(x, args)
  fitness_score = fit.value()

  print("Training Model...")
  if args.train_with_embedded:
    model = model_fn(datapoints, x_fitness, args)
  else:
    model = model_fn(datapoints, x, args)

  # Get the output directory
  exp_dir = db.new_learning_dir(args.function)

  # Generate alarms
  alarms = sorted(list(model.alarms()), key=lambda x: x[1])

  # Dump training data
  print("Dumping Training Data...")

  # Dump the selection
  with open(f"{exp_dir}/fitness.txt", "w") as f:
    f.write(f"Fitness Model: {args.fitness_function}\n")
    f.write(f"Fitness Score: {fitness_score}\n")

  # Dump the unified features
  with open(f"{exp_dir}/unified.json", "w") as f:
    j = {'before': list(sample_feature_json['before'].keys()), 'after': list(sample_feature_json['after'].keys())}
    json.dump(j, f)

  # Dump the Xs used to train the model
  x.dump(f"{exp_dir}/x.dat")

  # Mask
  if args.enable_feature_selection:
    with open(f"{exp_dir}/mask.txt", "w") as f:
      f.write("Raw Mask:\n")
      f.write(str(mask) + "\n")

      f.write("Enabled Meanings:\n")
      for i in range(dim):
        index = index_of_ith_one(mask, i)
        meaning = feature_groups.meaning_of(index)
        f.write(f"{meaning}\n")

  # Dump the model
  with open(f"{exp_dir}/model.joblib", "wb") as f:
    joblib.dump(model.clf, f)

  # Dump the raised alarms
  with open(f"{exp_dir}/alarms.csv", "w") as f:
    f.write("bc,slice_id,trace_id,score,alarms\n")
    for (dp, score) in alarms:
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)

  # Dump the raised alarms in a condensed way
  num_alarmed_slices = 0
  with open(f"{exp_dir}/alarms_brief.csv", "w") as f:
    f.write("bc,slice_id,num_traces,score_avg\n")

    # Get average
    scores_dict = {}
    for (dp, score) in alarms:
      key = (dp.bc, dp.slice_id)
      if key in scores_dict:
        total, count = scores_dict[key]
        scores_dict[key] = (total + score, count + 1)
      else:
        scores_dict[key] = (score, 1)

    # Dump average
    for ((bc, slice_id), (total, count)) in sorted(list(scores_dict.items()), key=lambda x: x[1][0] / x[1][1]):
      num_alarmed_slices += 1
      avg = total / count
      s = f"{bc},{slice_id},{count},{avg}\n"
      f.write(s)

  # Dump the command line arguments
  with open(f"{exp_dir}/log.txt", "w") as f:
    f.write("cmd\n")
    f.write("  " + str(sys.argv) + "\n")
    f.write("parsed_args\n")
    var_args = vars(args)
    for key in var_args:
      f.write(f"  {key}: {var_args[key]}\n")
    f.write(f"num_datapoints: {num_datapoints}\n")
    f.write(f"dim: {dim}\n")
    f.write(f"num_alarms: {len(alarms)}\n")
    f.write(f"num_alarmed_slices: {num_alarmed_slices}\n")

  # Generate TSNE
  print("Generating T-SNE Plot")

  tsne_fig, tsne_ax = plt.subplots()
  fitness_fig, fitness_ax = plt.subplots()

  if args.fitness_dimension == 2:
    # No need to transform again since x_fitness is already 2 dimensional
    x_embedded = x_fitness
  else:
    # Transform to 2 dimensional for visualization
    x_embedded = TSNE(n_components=2, verbose=2 if args.verbose else 0).fit_transform(x_fitness)

  # Dump t-SNE
  predicted = model.predicted()
  if args.ground_truth:
    tp, tn, fp, fn = [], [], [], []

    def label(prediction, datapoint):
      pos = prediction < 0
      alarm = datapoint.has_label(label=args.ground_truth)

      if pos and alarm:  # True positive
        return tp
      elif not pos and not alarm:  # True negative
        return tn
      elif pos and not alarm:  # False positive
        return fp
      else:  # False negative
        return fn

    for x, p, dp in zip(x_embedded, predicted, datapoints):
      label(p, dp).append(x)

    dp_types = [
        (tn, 'b', ',', 3, 0),  # True Negative
        (fp, 'y', '.', 3, 1),  # False Positive
        (fn, 'r', 'o', 7, 2),  # False Negative
        (tp, 'g', 'o', 5, 3)  # True Positive
    ]

    for arr, color, marker, size, zorder in dp_types:
      nparr = np.array(arr) if len(arr) > 0 else np.empty([0, 2])
      for ax in tsne_ax, fitness_ax:
        ax.scatter(nparr[:, 0], nparr[:, 1], c=color, s=size, marker=marker, zorder=zorder)

  else:
    colors = ['g' if p > 0 else 'r' for p in predicted]
    for ax in tsne_ax, fitness_ax:
      ax.scatter(x_embedded[:, 0], x_embedded[:, 1], c=colors)

  tsne_fig.savefig(f"{exp_dir}/tsne.png")

  # Save fitness function plot
  fit_2d = fitness_function(x_embedded, args)
  if fit_2d.plot(fitness_ax) != False:
    fitness_fig.savefig(f"{exp_dir}/fitness.png")


def get_model(args) -> Type[Model]:
  return models[args.model]


def get_fitness_function(args):
  return fitness_functions[args.fitness_function]
