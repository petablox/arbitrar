import warnings

def warn(*args, **kwargs):
  pass

warnings.warn = warn

def index_of_ith_one(v, i):
  c = -1
  for j in range(len(v)):
    if v[j] == 1:
      c += 1
      if c == i:
        return j