import os
from os import system
from ..meta import Executor, pp


class SlicesQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('function', type=str)
    parser.add_argument('--location', type=str)
    parser.add_argument('--source', type=str)
    parser.add_argument('--padding', type=int)

  @staticmethod
  def execute(args):
    db = args.db
    for slice_id, slice in db.function_slices(args.function):
      if not args.location or args.location in slice["call_edge"]["location"]:
        system('clear')
        if not args.source:
            print("Slice", slice_id)
            pp.pprint(slice)
        else:
            # Split in
            toks = slice['call_edge']['location'].split(":")
            path, func, line, col = toks[0], toks[1], int(toks[2]), toks[3]
            print(f"Slice {slice_id} [{path}] [{(slice['call_edge']['instr']).strip()}]")
            path = os.path.join(args.source, path)
            padding = args.padding if args.padding else 5 
            if not os.path.exists(path):
                print(f"No file found at {path}") 
            else:
                with open(path, "r") as f:
                    lcount = 1
                    lmin = max(0, line-padding)
                    lmax = line+padding
                    for l in f.readlines():
                        if lcount >= lmin and lcount <= lmax:
                            pd = "==>" if lcount == line else "   "
                            print(f"{pd} {lcount}:{l}", end="")
                        lcount += 1 

            print()
        input('Press enter to continue...')
