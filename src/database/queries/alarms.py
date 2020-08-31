import os
import pandas
from ..meta import Executor, pp
from ..helpers import SourceFeatureVisualizer


class AlarmsQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('learning-dir', type=str, help="path to alarms file")
    parser.add_argument('--source', type=str)
    parser.add_argument('--padding', type=int)
    parser.add_argument('--slice', action='store_true')

  @staticmethod
  def execute(args):
    if args.source:
      vis = SourceFeatureVisualizer(args.source)

    db = args.db
    var_args = vars(args)
    fn = var_args["learning-dir"].split("/")[-2].split("-")[-1]

    pd = pandas.read_csv(var_args["learning-dir"])
    nalarms = len(pd)
    lastslice = -1
    for i in range(nalarms):
      d = pd.iloc[i]
      input_bc_file = d["bc"]
      bc_name = db.find_bc_name(input_bc_file)
      bc = bc_name if bc_name else input_bc_file
      slice_id = d["slice_id"]
      trace_id = d["trace_id"]

      datapoint = db.datapoint(fn, bc, slice_id, trace_id)

      if lastslice == slice_id and args.slice:
        continue
      lastslice = slice_id

      if not args.source:
        pp.pprint(datapoint.trace())
      else:
        result = vis.show(datapoint, label=f"{i}/{nalarms}")
        if not result:
          break

    vis.destroy()
