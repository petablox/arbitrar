import numpy as np
from sklearn.svm import OneClassSVM
from src.database import Database, DataPoint


def setup_parser(parser):
    parser.add_argument('function', type=str, help='Function to train on')
    parser.add_argument('-m', '--model', type=str, default='ocsvm', help='Model (ocsvm)')

    # OCSVM Parameters
    parser.add_argument('--kernel', type=str, default='rbf', help='OCSVM Kernel')
    parser.add_argument('--nu', type=float, default=0.01, help='OCSVM nu')


class Model:
    def alarms(self):
        raise Exception("Alarm not implemented")


class OCSVM(Model):
    def __init__(self, datapoints, x, args):
        self.datapoints = datapoints
        self.x = x
        self.clf = OneClassSVM(
            kernel = args.kernel,
            nu = args.nu
        ).fit(x)

    def alarms(self):
        predicted = self.clf.predict(self.x)
        scores = self.clf.score_samples(self.x)
        for (dp, p, s) in zip(self.datapoints, predicted, scores):
            if p == -1:
                yield (dp, s)


models = { "ocsvm": OCSVM }


def main(args):
    db = args.db
    datapoints = list(db.function_datapoints(args.function))
    x = np.array([encode_feature(dp) for dp in datapoints])
    model = models[args.model](datapoints, x, args)
    for (dp, score) in model.alarms():
        print(dp.slice_id, dp.trace_id, score)


def encode_feature(datapoint):
    feature_json = datapoint.feature()
    invoked_before_features = encode_causality(feature_json["invoked_before"])
    invoked_after_features = encode_causality(feature_json["invoked_after"])
    retval_features = encode_retval(feature_json["retval_check"]) if "retval_check" in feature_json else []
    return invoked_before_features + invoked_after_features + retval_features


def encode_causality(causality):
    return [int(causality[key]) for key in sorted(causality)]


def encode_retval(retval):
    if retval["has_retval_check"]:
        return [
            int(retval["has_retval_check"]),
            int(retval["check_branch_taken"]),
            int(retval["branch_is_zero"]),
            int(retval["branch_not_zero"])
        ]
    else:
        return [
            int(retval["has_retval_check"]),
            0, # Default
            0, # Default
            0  # Default
        ]
