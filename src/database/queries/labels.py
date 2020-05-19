from ..meta import Executor


class LabelsQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('function', type=str)
    parser.add_argument('-a', '--alarm', type=str)
    parser.add_argument('--alarm-only', action='store_true')

  @staticmethod
  def execute(args):
    db = args.db
    for dp in db.function_datapoints(args.function):
      if dp.has_label(args.alarm):
        if args.alarm_only:
          print(dp.bc, dp.slice_id, dp.trace_id, dp.labels())
