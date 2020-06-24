from sklearn.svm import OneClassSVM

from .meta import Model

class OCSVM(Model):
  def __init__(self, datapoints, x, args):
    clf = OneClassSVM(kernel=args.kernel, nu=args.nu).fit(x)
    super().__init__(datapoints, x, clf)