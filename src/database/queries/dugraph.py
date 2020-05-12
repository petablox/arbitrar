import os
from ..meta import Executor, pp
from termcolor import cprint


class DUGraphQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to")
    parser.add_argument('function', type=str, help="The function that the trace is about")
    parser.add_argument('slice-id', type=int, help='The slice id')
    parser.add_argument('trace-id', type=int, help='The trace id')
    parser.add_argument('--source', type=str)
    parser.add_argument('--padding', type=int)

  @staticmethod
  def execute(args):
    db = args.db
    var_args = vars(args)
    input_bc_file = var_args["bc-file"]
    bc_name = args.db.find_bc_name(input_bc_file)
    bc = bc_name if bc_name else input_bc_file
    fn = args.function
    slice_id = var_args["slice-id"]
    trace_id = var_args["trace-id"]
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
        cprint(f"Slice {slice_id} Trace {trace_id}")
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
