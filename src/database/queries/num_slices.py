from .meta import QueryExecutor, print_counts


class NumSlicesQuery(QueryExecutor):
  def setup_parser(parser):
    parser.add_argument('-p', '--package', type=str, help='Only the slices in a package')
    parser.add_argument('-b', '--bc', type=str, help='Only the slices in a bc-file')
    parser.add_argument('-f', '--function', type=str, help='Only the slices around a function')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose')

  def execute(args):
    db = args.db
    if args.bc:
      bc_name = db.find_bc_name(args.bc)
      if bc_name:
        print(db.num_slices(func_name=args.function, bc=bc_name))
      else:
        print(f"Unknown bc {bc_name}")
    else:
      count = 0
      individual_count = []
      for bc_name in db.bc_files(package=args.package, full=False):
        n = db.num_slices(func_name=args.function, bc=bc_name)
        count += n
        if n > 0:
          individual_count.append((bc_name, n))

      if args.verbose:
        individual_count.append(("Total", count))
        print_counts(individual_count)
      else:
        print(count)
