from ..meta import Executor, pp
from ..helpers import SourceFeatureVisualizer


def iterate_datapoints(db, args):
  if args.filter:
    flt = eval(args.filter)

  bc_files = list(db.bc_files(package=args.package,
                              full=False)) if args.package else [db.find_bc_name(args.bc)] if args.bc else None

  for dp in db.function_datapoints(args.function):
    if bc_files == None or dp.bc in bc_files:
      if args.slice_id == None or dp.slice_id == args.slice_id:
        if args.filter == None or flt(dp):
          yield dp


class FeaturesQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('-p', '--package', type=str, help='Only the traces in a package')
    parser.add_argument('-b', '--bc', type=str, help='Only the traces in a bc-file')
    parser.add_argument('-f', '--function', type=str, help='Only the traces around a function')
    parser.add_argument('--slice-id', type=int)
    parser.add_argument('--filter', type=str)
    parser.add_argument('--source', type=str)
    parser.add_argument('--one-per-slice', action='store_true')

  @staticmethod
  def execute(args):
    if args.source:
      vis = SourceFeatureVisualizer()

    if args.one_per_slice:
      last_slice_id = -1

    for datapoint in iterate_datapoints(args.db, args):

      # Skip feature if using one per slice option
      if args.one_per_slice:
        if last_slice_id == datapoint.slice_id:
          continue
        else:
          last_slice_id = datapoint.slice_id

      # Check if source is provided. If is, then use visualizer
      if args.source:
        result = vis.show(datapoint, args.source)
        if not result:
          break
      else:
        pp.pprint(datapoint.feature())
