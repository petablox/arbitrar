from os import system
from ..meta import Executor, pp


class SlicesQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('function', type=str)
    parser.add_argument('--location', type=str)

  @staticmethod
  def execute(args):
    db = args.db
    for slice_id, slice in db.function_slices(args.function):
      if not args.location or args.location in slice["call_edge"]["location"]:
        system('clear')
        print("Slice", slice_id)
        pp.pprint(slice)
        input('Press enter to continue...')
