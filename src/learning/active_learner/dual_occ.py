from src.database.helpers import SourceFeatureVisualizer

def active_learn(datapoints, xs, amount, args):
  us = list(enumerate(xs))
  ts = []
  os = []

  outlier_count = 0
  auc_graph = []

  if args.source:
    vis = SourceFeatureVisualizer(args.source)

  try:
    for attempt_count in range(amount):
      pass
  except:
    pass