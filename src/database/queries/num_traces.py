from .meta import QueryExecutor


class NumTracesQuery(QueryExecutor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('-p', '--package', type=str, help='Only the traces in a package')
    parser.add_argument('-b', '--bc', type=str, help='Only the traces in a bc-file')
    parser.add_argument('-f', '--function', type=str, help='Only the traces around a function')

  @staticmethod
  def execute(args):
    db = args.db
    count = 0
    if args.package:
      for bc_name in db.bc_files(package=args.package, full=False):
        n = db.num_traces(bc=bc_name, func_name=args.function)
        count += n
    else:
      n = db.num_traces(bc=args.bc, func_name=args.function)
      count += n
    print(count)
