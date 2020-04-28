from .meta import QueryExecutor, pp


class DUGraphQuery(QueryExecutor):
  def setup_parser(parser):
    parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to")
    parser.add_argument('function', type=str, help="The function that the trace is about")
    parser.add_argument('slice-id', type=int, help='The slice id')
    parser.add_argument('trace-id', type=int, help='The trace id')

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
      pp.pprint(dugraph)
    else:
      print("DUGraph does not exist")
