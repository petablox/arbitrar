import os
import sys
from ..meta import pp
from os import system
from termcolor import cprint
import curses

from ..datapoint import DataPoint


class SourceFeatureVisualizer():
  def __init__(self):
    self.stdscr = curses.initscr()

    curses.savetty()

    curses.start_color()
    curses.use_default_colors()

    curses.init_pair(1, curses.COLOR_YELLOW, -1)
    curses.init_pair(2, curses.COLOR_RED, -1)
    curses.init_pair(3, curses.COLOR_GREEN, -1)
    # curses.init_pair(4, 7, -1)

    self.stdscr.clear()

    self.columns = os.get_terminal_size()[0]
    self.half_width = int(self.columns / 2)
    self.lines = 200

    self.left_window = curses.newwin(self.lines, self.half_width)
    self.right_window = curses.newwin(self.lines, self.half_width, 0, self.half_width + 2)

    # self.source = source

  def display(self, datapoint: DataPoint, label="", padding=20):
    # Initialize datapoint data
    # bc = datapoint.bc
    # func_name = datapoint.func_name
    slice_id = datapoint.slice_id
    trace_id = datapoint.trace_id

    trace = datapoint.trace()
    used = set()
    for v in trace['instrs']:
      toks = v['loc'].split(":")
      if len(toks) < 3:
        continue
      line, _col = int(toks[1]), int(toks[2])
      used.add(line)

    slice = datapoint.slice()
    toks = slice['instr'].split(":")
    if (len(toks) < 3):
      path = ""
      line = 0
    else:
      path, line, _col = toks[0], int(toks[1]), toks[2]

    self.left_window.erase()
    self.right_window.erase()
    self.left_window.addstr(f"[{path}:{line}] Slice-Id:{slice_id} Trace-Id:{trace_id} Code {label}\n",
                            curses.color_pair(1))
    self.right_window.addstr(f"[{path}:{line}] Slice-Id:{slice_id} Trace-Id:{trace_id} Features\n",
                             curses.color_pair(1))

    # cprint(f"Slice [{path}] {slice_id} Trace {trace_id} Alarm {i}/{nalarms}")
    # path = os.path.join(self.source, path)
    if not os.path.exists(path):
      print(f"No file found at {path}")
    else:
      with open(path, "r", encoding="ISO-8859-1") as f:
        lcount = 1
        lmin = max(0, line - padding)
        lmax = line + padding
        for l in f.readlines():
          if lcount >= lmin and lcount <= lmax:
            if lcount == line:
              self.left_window.addstr(f"==> {lcount}:{l}", curses.color_pair(1))
              #cprint(f"==> {lcount}:{l}", "red", end="")
            else:
              colr = 3 if lcount in used else 0
              self.left_window.addstr(f"    {lcount}:{l}", curses.color_pair(colr))
          lcount += 1

    feature = datapoint.grouped_feature()
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

  def show(self, datapoint, label="", padding=30):
    self.display(datapoint, label=label, padding=padding)

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

  def ask(self,
          datapoint,
          keys,
          actions,
          prompt="> ",
          label="",
          padding=30,
          scroll_down_key="n",
          scroll_up_key="p",
          quit_key="q"):
    """
    Please make sure that `keys` do not collide with scroll_down_key, scroll_up_key, and quit_key
    """
    self.display(datapoint, label=label, padding=padding)

    # Prompt the user input
    self.left_window.addstr("")
    self.left_window.addstr(prompt)

    try:
      while True:
        key = self.left_window.getkey()
        if key == scroll_down_key:
          self.right_window.scrollok(True)
          self.right_window.scroll(10)
        elif key == scroll_up_key:
          self.right_window.scrollok(True)
          self.right_window.scroll(-10)

        # Quit using 'q'
        elif key == quit_key:
          self.destroy()
          return quit_key

        # Any key, move foward
        if key in keys:
          return key
        elif actions and key in actions:
          actions[key]()

        # Refresh the window
        self.right_window.refresh()
    except:  # KeyboardInterrupt:
      self.destroy()
      sys.exit()

  def destroy(self):
    curses.endwin()

    # self.left_window.erase()
    # self.left_window.refresh()
    # self.right_window.erase()
    # self.right_window.refresh()

    # Delete windows
    # del self.left_window
    # del self.right_window

    # # Restore std screen
    # self.stdscr.touchwin()
    # self.stdscr.refresh()
