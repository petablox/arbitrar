from .meta import QueryExecutor, pp


class SliceQuery(QueryExecutor):
  def setup_parser(parser):
    parser.add_argument('bc-file', type=str, help='The bc-file that the slice belongs to')
    parser.add_argument('function', type=str, help='The function that the slice contain')
    parser.add_argument('slice-id', type=int, help='The slice id')

  def execute(args):
    db = args.db
    var_args = vars(args)
    input_bc_file = var_args["bc-file"]
    bc_name = args.db.find_bc_name(input_bc_file)
    bc = bc_name if bc_name else input_bc_file
    slice = args.db.slice(args.function, bc, var_args["slice-id"])
    if slice:
      pp.pprint(slice)
    else:
      print("Slice does not exist")
