import warnings
from functools import reduce
from collections.abc import Iterable


def warn(*args, **kwargs):
  pass


warnings.warn = warn


def index_of_ith_one(v, i) -> int:
  return index_of_ith(v, i, 1)


def index_of_ith_zero(v, i) -> int:
  return index_of_ith(v, i, 0)


def index_of_ith(v, i, e) -> int:
  c = -1
  for j in range(len(v)):
    if v[j] == e:
      c += 1
      if c == i:
        return j
  raise Exception("Not found")


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
