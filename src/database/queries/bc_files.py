from .meta import QueryExecutor


class BCFilesQuery(QueryExecutor):
  def setup_parser(parser):
    parser.add_argument('-p', '--package', type=str, help="Only the bc files in a package")

  def execute(args):
    bc_files = args.db.bc_files(package=args.package)
    for bc_file in bc_files:
      print(bc_file)
