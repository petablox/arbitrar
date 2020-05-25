import os
from ..meta import pp
from os import system
from termcolor import cprint

import curses


class SourceFeatureVisualizer():
  def __init__(self):
    self.stdscr = curses.initscr()

    curses.start_color()

    curses.init_pair(1, curses.COLOR_YELLOW, curses.COLOR_BLACK)
    curses.init_pair(2, curses.COLOR_RED, curses.COLOR_BLACK)
    curses.init_pair(3, curses.COLOR_BLUE, curses.COLOR_BLACK)

    self.stdscr.clear()

    self.columns = os.get_terminal_size()[0]
    self.half_width = int(self.columns / 2)
    self.lines = 200

    self.left_window = curses.newwin(self.lines, self.half_width)
    self.right_window = curses.newwin(self.lines, self.half_width, 0, self.half_width + 2)

  def show(self, datapoint, source, label="", padding=20):

    # Initialize datapoint data
    bc = datapoint.bc
    func_name = datapoint.func_name
    slice_id = datapoint.slice_id
    trace_id = datapoint.trace_id

    dugraph = datapoint.dugraph()
    used = set()
    for v in dugraph['vertex']:
      toks = v['location'].split(":")
      if len(toks) < 4:
        continue
      line, col = int(toks[2]), int(toks[3])
      used.add(line)

    slice = datapoint.slice()
    toks = slice['call_edge']['location'].split(":")
    path, func, line, col = toks[0], toks[1], int(toks[2]), toks[3]

    self.left_window.erase()
    self.right_window.erase()
    self.left_window.addstr(f"[{path}:{line}] Slice-Id:{slice_id} Trace-Id:{trace_id} Code {label}\n",
                            curses.color_pair(1))
    self.right_window.addstr(f"[{path}:{line}] Slice-Id:{slice_id} Trace-Id:{trace_id} Features\n",
                             curses.color_pair(1))

    #cprint(f"Slice [{path}] {slice_id} Trace {trace_id} Alarm {i}/{nalarms}")
    path = os.path.join(source, path)
    if not os.path.exists(path):
      print(f"No file found at {path}")
    else:
      with open(path, "r") as f:
        lcount = 1
        lmin = max(0, line - padding)
        lmax = line + padding
        for l in f.readlines():
          if lcount >= lmin and lcount <= lmax:
            if lcount == line:
              self.left_window.addstr(f"==> {lcount}:{l}", curses.color_pair(2))
              #cprint(f"==> {lcount}:{l}", "red", end="")
            else:
              colr = 3 if lcount in used else 0
              self.left_window.addstr(f"    {lcount}:{l}", curses.color_pair(colr))
          lcount += 1

    feature = datapoint.feature()
    if feature:
      formatted = pp.pformat(feature).splitlines()
      for l, t in enumerate(formatted):
        if l >= self.lines - 10:
          continue
        self.right_window.addstr(t + "\n")
    else:
      self.right_window.addstr("No features")

    self.left_window.refresh()
    self.right_window.refresh()

    while True:
      key = self.left_window.getkey()
      if key == "n":
        self.right_window.scrollok(True)
        self.right_window.scroll(10)
      elif key == "p":
        self.right_window.scrollok(True)
        self.right_window.scroll(-10)

      # Quit using 'q'
      elif key == "q":
        return False

      # Any key, move foward
      else:
        return True
      self.right_window.refresh()