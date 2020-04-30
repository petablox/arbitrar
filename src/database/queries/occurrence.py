from .meta import QueryExecutor, print_counts


class OccurrenceQuery(QueryExecutor):
  def setup_parser(parser):
    parser.add_argument('-f', '--function', type=str, help="The function name")
    parser.add_argument('-p', '--package', type=str, help="The package")
    parser.add_argument('--bc', type=str, help="LLVM Byte Code File")
    parser.add_argument('-v', '--verbose', action='store_true', help="Verbose")
    parser.add_argument('-t', '--threshold', type=int, help="Occurred at least [threshold] times")
    parser.add_argument('-l', '--limit', type=int, help="Only output top [limit] results")

  def execute(args):
    if args.function:
      count = 0
      individual_counts = []
      for bc_file, occurrence in args.db.occurrences(package=args.package, bc_file=args.bc):
        if args.function in occurrence:
          n = occurrence[args.function]
          count += n
          individual_counts.append((bc_file, n))
      if args.verbose:
        individual_counts.append(("Total", count))
        print_counts(individual_counts)
      else:
        print(count)
    else:
      counts = {}
      for bc_file, occurrence in args.db.occurrences(package=args.package, bc_file=args.bc):
        for func, count in occurrence.items():
          if func in counts:
            counts[func] += count
          else:
            counts[func] = count
      counts_arr = []
      for func, count in counts.items():
        if not args.threshold or count >= args.threshold:
          counts_arr.append((func, count))
      counts_arr = sorted(counts_arr, key=lambda t: -t[1])
      if args.limit:
        print_counts(counts_arr[0:args.limit])
      else:
        print_counts(counts_arr)
