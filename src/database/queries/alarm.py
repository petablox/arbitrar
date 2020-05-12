import os
from ..meta import Executor, pp
from os import system
import pandas
from termcolor import cprint

import curses


class AlarmQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('learning-dir', type=str, help="learning dir that contains alarms.csv")
    parser.add_argument('--source', type=str)
    parser.add_argument('--padding', type=int)
    parser.add_argument('--slice', action='store_true')

  @staticmethod
  def execute(args):
    stdscr = curses.initscr()
    stdscr.clear()

    columns, lines = os.get_terminal_size()
    half_width = int(columns / 2)
    lines = 200

    left_window = curses.newwin(lines, half_width)
    right_window = curses.newwin(lines, half_width, 0, half_width + 2)

    #curses.start_color()
    #curses.init_pair(1, curses.COLOR_RED, curses.COLOR_WHITE)

    db = args.db
    var_args = vars(args)
    fn = var_args["learning-dir"].split("-")[-1]

    pd = pandas.read_csv(os.path.join(var_args["learning-dir"], "alarms.csv"))
    nalarms = len(pd)
    lastslice = -1
    for i in range(nalarms):
      d = pd.iloc[i]
      input_bc_file = d["bc"]
      bc_name = args.db.find_bc_name(input_bc_file)
      bc = bc_name if bc_name else input_bc_file
      slice_id = d["slice_id"]
      trace_id = d["trace_id"]

      if lastslice == slice_id and args.slice:
          continue
      lastslice = slice_id

      dugraph = args.db.dugraph(fn, bc, slice_id, trace_id)
      if dugraph:
        if not args.source:
          pp.pprint(dugraph)
        else:
          used = set()
          for v in dugraph['vertex']:
            toks = v['location'].split(":")
            if len(toks) < 4:
              continue
            line, col = int(toks[2]), int(toks[3])
            used.add(line)
          slice = db.slice(fn, bc, slice_id)
          toks = slice['call_edge']['location'].split(":")
          path, func, line, col = toks[0], toks[1], int(toks[2]), toks[3]

          left_window.erase()
          right_window.erase()
          left_window.addstr(f"Slice [{path}] {slice_id} Trace {trace_id} Alarm {i}/{nalarms}\n")
          right_window.addstr("Features\n")

          #cprint(f"Slice [{path}] {slice_id} Trace {trace_id} Alarm {i}/{nalarms}")
          path = os.path.join(args.source, path)
          padding = args.padding if args.padding else 20
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
                    left_window.addstr(f"==> {lcount}:{l}")
                    #cprint(f"==> {lcount}:{l}", "red", end="")
                  else:
                    left_window.addstr(f"    {lcount}:{l}")
                    #colr = "green" if lcount in used else "white"
                    #cprint(f"    {lcount}:{l}", colr, end="")
                lcount += 1

          feature = args.db.feature(fn, bc, slice_id, trace_id)
          if feature:
            formatted = pp.pformat(feature).splitlines()
            for l, t in enumerate(formatted):
                if l >= lines-10:
                    continue
                right_window.addstr(t + "\n")
          else:
            right_window.addstr("No features")
      else:
        print("DUGraph does not exist")
      #print()
      left_window.refresh()
      right_window.refresh()

      while True:
        key = left_window.getkey()
        if key == "n":
            right_window.scrollok(True)
            right_window.scroll(10)
        elif key == "p":
            right_window.scrollok(True)
            right_window.scroll(-10)
        else:
            break
        right_window.refresh()

