from sklearn.svm import OneClassSVM
from sklearn.ensemble import IsolationForest

# import torch
# import torch.nn as nn
# import torch.nn.functional as F

class Model:
  def __init__(self, datapoints, x, clf):
    self.datapoints = datapoints
    self.x = x
    self.clf = clf

  def alarms(self):
    predicted = self.clf.predict(self.x)
    scores = self.clf.score_samples(self.x)
    for (dp, p, s) in zip(self.datapoints, predicted, scores):
      if p < 0:
        yield (dp, s)

  def results(self):
    predicted = self.clf.predict(self.x)
    scores = self.clf.score_samples(self.x)
    for (dp, p, s) in zip(self.datapoints, predicted, scores):
      yield (dp, p, s)

  def predicted(self):
    return self.clf.predict(self.x)


# One-Class SVM
class OCSVM(Model):
  def __init__(self, datapoints, x, args):
    clf = OneClassSVM(kernel=args.kernel, nu=args.nu).fit(x)
    super().__init__(datapoints, x, clf)


# class OneClassClassification(nn.Module):
#   def __init__(self, nu, lambd_w, lambd_v, input_dim, device):
#     super(OneClassClassification, self).__init__()
#     self.nu = nu
#     self.lambd_w = lambd_w
#     self.lambd_v = lambd_v
#     self.input_dim = input_dim
#     self.device = device

#     self.w = torch.nn.Parameter(torch.randn(self.input_dim), requires_grad=True)
#     self.r = torch.nn.Parameter(torch.randn(1).squeeze(0), requires_grad=True)

#   def forward(self, feats):
#     obj = self.lambd_w * torch.sum(self.w ** 2)
#     obj += 1. / self.nu * torch.mean(F.relu(self.r - torch.matmul(feats, self.w)))
#     obj -= self.r
#     return obj

#   def score(self, feats):
#     with torch.no_grad():
#       return (torch.matmul(feats, self.w) - self.r) / torch.sqrt(torch.mean(self.w ** 2))


# class OneClassClassificationTrainer:
#   def __init__(self, objective, n_epochs, lr, device):
#     self.obj = objective.to(device)
#     self.n_epochs = n_epochs
#     self.lr = lr
#     self.device = device
#     self.optim = optim.Adam(filter(lambda p: p.requires_grad, self.obj.parameters()), lr=lr)

#   def train(self, x):
#     for epoch in range(self.n_epochs):



# class RegularizedOCSVM(Model):
#   def __init__(self, datapoints, x, args):
#     trainer = OneClassClassificationTrainer()


# Isolation Forest
class IF(Model):
  def __init__(self, datapoints, x, args):
    clf = IsolationForest(contamination=args.contamination).fit(x)
    super().__init__(datapoints, x, clf=clf)
