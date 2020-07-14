import time

class Timer:
  def __init__(self):
    self.start = time.perf_counter()

  def time(self):
    now = time.perf_counter()
    return (now - self.start) / 1000