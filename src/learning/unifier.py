from .feature_group import CausalityFeatureGroup


def unify_features_with_sample(datapoints, unified):
  def unify_feature(datapoint, unified):
    feature = datapoint.feature()
    for k in ['invoked_before', 'invoked_after']:
      feature[k] = {key: feature[k][key] if key in feature[k] else False for key in unified[k]}
    return feature

  return [unify_feature(dp, unified) for dp in datapoints]


def unify_causality(causalities):
  d = {}
  for causality in causalities:
    for func in causality.keys():
      d[func] = True
  return d


def unify_features(datapoints):
  features = [dp.feature() for dp in datapoints]
  invoked_before = unify_causality([f["invoked_before"] for f in features])
  invoked_after = unify_causality([f["invoked_after"] for f in features])

  # Unify the features
  for feature in features:
    # First invoked before
    for func in invoked_before.keys():
      if not func in feature["invoked_before"]:
        feature["invoked_before"][func] = CausalityFeatureGroup.default()
    # Then invoked after
    for func in invoked_after.keys():
      if not func in feature["invoked_after"]:
        feature["invoked_after"][func] = CausalityFeatureGroup.default()

  return features
