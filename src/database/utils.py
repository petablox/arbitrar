import os


def mkdir(d: str) -> str:
  if not os.path.exists(d):
    os.mkdir(d)
  return d
