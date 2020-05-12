import os
from ..meta import Executor, pp
from os import system
import pandas
from termcolor import cprint


class AlarmQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('learning-dir', type=str, help="learning dir that contains alarms.csv")
    parser.add_argument('--source', type=str)
    parser.add_argument('--padding', type=int)

  @staticmethod
  def execute(args):
    db = args.db
    var_args = vars(args)
    fn = var_args["learning-dir"].split("-")[-1]

    pd = pandas.read_csv(os.path.join(var_args["learning-dir"], "alarms.csv"))
    nalarms = len(pd)
    for i in range(nalarms):
      d = pd.iloc[i]
      input_bc_file = d["bc"]
      bc_name = args.db.find_bc_name(input_bc_file)
      bc = bc_name if bc_name else input_bc_file
      slice_id = d["slice_id"]
      trace_id = d["trace_id"]

      dugraph = args.db.dugraph(fn, bc, slice_id, trace_id)
      if dugraph:
        system('clear')
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
          cprint(f"Slice {slice_id} Trace {trace_id} Alarm {i}/{nalarms}")
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
                    cprint(f"==> {lcount}:{l}", "red", end="")
                  else:
                    colr = "green" if lcount in used else "white"
                    cprint(f"    {lcount}:{l}", colr, end="")
                lcount += 1
      else:
        print("DUGraph does not exist")
      print()
      input('Press enter to continue...')
