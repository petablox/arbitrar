from .feature_group import CausalityFeatureGroup


def unify_features_with_sample(datapoints, unified):
  def unify_feature(datapoint, unified):
    feature = datapoint.feature()
    for k in ['before', 'after']:
      feature[k] = {key: feature[k][key] if key in feature[k] else False for key in unified[k]}
    return feature

  return [unify_feature(dp, unified) for dp in datapoints]


def unify_causality(causalities):
  d = set()
  for causality in causalities:
    for func in causality.keys():
      d.add(func)
  return d


def unify_features(datapoints):
  features = [dp.feature() for dp in datapoints]
  before = unify_causality([f["before"] for f in features])
  after = unify_causality([f["after"] for f in features])

  # Unify the features
  for feature in features:
    # First invoked before
    for func in before:
      if not func in feature["before"]:
        feature["before"][func] = CausalityFeatureGroup.default()

    # Then invoked after
    for func in after:
      if not func in feature["after"]:
        feature["after"][func] = CausalityFeatureGroup.default()

  return features
