from src.database import Database, DataPoint
from src.database.helpers import SourceFeatureVisualizer

from .unifier import unify_features, unify_features_with_sample
from .feature_group import *


def cube_pdf(xs, x):
  pass


def gaussian_pdf(xs, x):
  raise Exception("Not implemented")


pdfs = {
    'cube': cube_pdf,
    'gaussian': gaussian_pdf
}

def score_1(xs, x, ts, os):
  raise Exception("Not implemented")


def score_2(xs, x, ts, os):
  raise Exception("Not implemented")


def score_3(xs, x, ts, os):
  raise Exception("Not implemented")


def score_4(xs, x, ts, os):
  pass


score_functions = {
    'score_1': score_1
    'score_2': score_2
    'score_3': score_3
    'score_4': score_4
}


def setup_parser(parser):
  parser.add_argument('function', type=str, help='Function to train on')
  parser.add_argument('-d', '--pdf', type=str, default="cube", help='Density Function')
  parser.add_argument('-s', '--score', type=str, default="score_4", help='Score Function')
  parser.add_argument('-l', '--limit', type=int, default=0.01, help="Number of alarms reported")


def argmax(ps, ts, os, score, density) -> int:
  """
  Return the index of the datapoint in xs that score the highest
  """
  pass


def top_scored(ps, ts, os, score, density, limit):
  """
  Return a list of indices that rank the highest on score
  """
  pass


def main(args):
  db = args.db

  print("Fetching Datapoints From Database...")
  datapoints = list(db.function_datapoints(args.function))

  print("Unifying Features...")
  feature_jsons = unify_featuers(datapoints)
  sample_feature_json = feature_jsons[0]

  print("Generating Feature Groups and Encoder")
  feature_groups = FeatureGroups(sample_feature_json)

  print("Encoding Features...")
  xs = [feature_groups.encode(feature) for feature in feature_jsons]

  print("Initializing Helper Datapoints...")
  ps = list(enumerate(xs))
  ts = []
  os = []

  print("Initializing Functinos...")
  score_function = score_functions[args.score]
  density_function = pdfs[args.pdf]

  print("Initializing Visualizer...")
  vis = SourceFeatureVisualizer(args.source)

  while True:
    p_i = argmax(ps, ts, os, score_function, density_function)
    datapoint_i = datapoints[p_i]

    # Ask the user to label. y: Is Outlier, n: Not Outlier, u: Unknown
    result = vis.ask(datapoint, ["y", "n", "u"], scroll_down_key="]", scroll_up_key="[")
    item = (p_i, xs[p_i])
    if result != "q":
      if result == "y":
        os.append(item)
        ps.remove(item)
      elif result == "n":
        ts.append(item)
        ps.remove(item)
      else: # result == "u"
        pass
    else:
      break

  # Get the alarms
  alarm_id_scores = top_scored(ps, ts, os, score_function, density_function, args.limit)
  alarm_dps = [(datapoints[i], score) for (i, score) in alarm_id_scores]
  print("Dumping result")

  # Dump the unified features
  with open(f"{exp_dir}/unified.json", "w") as f:
    j = {
        'invoked_before': list(sample_feature_json['invoked_before'].keys()),
        'invoked_after': list(sample_feature_json['invoked_after'].keys())
    }
    json.dump(j, f)

  # Dump the Xs used to train the model
  np.array(xs).dump(f"{exp_dir}/x.dat")

  # Dump the raised alarms
  with open(f"{exp_dir}/alarms.csv", "w") as f:
    f.write("bc,slice_id,trace_id,scroe,alarms\n")
    for (dp, score) in alarm_dps:
      s = f"{dp.bc},{dp.slice_id},{dp.trace_id},{score},\"{str(dp.alarms())}\"\n"
      f.write(s)
