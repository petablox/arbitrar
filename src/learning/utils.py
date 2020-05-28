import warnings
from collections.abc import Iterable

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


def get_dot_separated_field(json, field):
  return reduce(lambda j, f: j[f] if j != None and f in j else None, field.split("."), json)


def has_dot_separated_field(json, field):
  j = json
  for f in field.split("."):
    if isinstance(j, Iterable) and f in j:
      j = j[f]
    else:
      return False
  return True