from ..meta import Executor, print_counts
import re


class OccurrenceQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('-f', '--function', type=str, help="The function name")
    parser.add_argument('-p', '--package', type=str, help="The package")
    parser.add_argument('-r', '--regexp', action='store_true', help="Use -f as regexp")
    parser.add_argument('-v', '--verbose', action='store_true', help="Verbose")
    parser.add_argument('-t', '--threshold', type=int, help="Occurred at least [threshold] times")
    parser.add_argument('-l', '--limit', type=int, help="Only output top [limit] results")
    parser.add_argument('--lmin', type=int, help="Limit start")
    parser.add_argument('--bc', type=str, help="LLVM Byte Code File")
    parser.add_argument('--in-bc', nargs='+', help="BC Files")

  @staticmethod
  def execute(args):
    if args.function:
      count = 0
      individual_counts = []
      for bc_file, occurrence in args.db.occurrences(package=args.package, bc_file=args.bc):
        if args.regexp:
          for f, n in occurrence.items():
            if re.match(args.function, f):
              count += n
              individual_counts.append((bc_file + ":" + f, n))
        else:
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
      if args.in_bc:
        sets = {}
        occurrences = {}

        def contains(bc_file):
          for include_bc in args.in_bc:
            if include_bc in bc_file:
              return True
          return False

        for bc_file, occurrence in args.db.occurrences(package=args.package):
          if contains(bc_file):
            occurrences[bc_file] = occurrence
            if not bc_file in sets:
              sets[bc_file] = set()
            for func, _ in occurrence.items():
              sets[bc_file].add(func)

        itsct = None
        for (_, s) in sets.items():
          if itsct is None:
            itsct = s
          else:
            itsct = itsct.intersection(s)

        if itsct != None:
          for func in itsct:
            print(f"{func} -- ", end="")
            for bc_file, occs in occurrences.items():
              if func in occs:
                print(f"{bc_file}: {occs[func]}, ", end="")
            print()

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
        if args.lmin != None:
          if args.limit != None:
            print_counts(counts_arr[args.lmin : args.lmin + args.limit])
          else:
            print_counts(counts_arr[args.lmin : args.lmin + 50])
        elif args.limit != None:
          print_counts(counts_arr[0 : args.limit])
        else:
          print_counts(counts_arr)
