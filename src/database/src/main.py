import pprint
from . import utils

pp = pprint.PrettyPrinter(indent = 2)

class QueryExecutor:
    def setup_parser(parser):
        pass

    def execute(args):
        pass


class PackagesQuery(QueryExecutor):
    def execute(args):
        db = args.db
        print("Name\t\tFetch Status\tBuild Status")
        for package in db.packages:
            f = "fetched" if package.fetched else "not fetched"
            b = package.build.result.value
            print(f"{package.name}\t\t{f}\t\t{b}")


class BCFilesQuery(QueryExecutor):
    def setup_parser(parser):
        parser.add_argument('-p', '--package', type=str, help="Only the bc files in a package")

    def execute(args):
        bc_files = args.db.bc_files(package = args.package)
        for bc_file in bc_files:
            print(bc_file)


class OccurrenceQuery(QueryExecutor):
    def setup_parser(parser):
        parser.add_argument('function', type=str, help="The function name")
        parser.add_argument('-p', '--package', type=str, help="The package")
        parser.add_argument('-v', '--verbose', action='store_true', help="Verbose")

    def execute(args):
        count = 0
        individual_counts = []
        for bc_file, occurrence in args.db.occurrences(package = args.package):
            if args.function in occurrence:
                n = occurrence[args.function]
                count += n
                individual_counts.append((bc_file, n))

        if args.verbose:
            individual_counts.append(("Total", count))
            utils.print_counts(individual_counts)
        else:
            print(count)


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
                print(db.num_slices(func_name = args.function, bc = bc_name))
            else:
                print(f"Unknown bc {bc_name}")
        else:
            count = 0
            individual_count = []
            for bc_name in db.bc_files(package = args.package, full = False):
                n = db.num_slices(func_name = args.function, bc = bc_name)
                count += n
                if n > 0:
                    individual_count.append((bc_name, n))

            if args.verbose:
                individual_count.append(("Total", count))
                utils.print_counts(individual_count)
            else:
                print(count)


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
        if bc_name:
            slice = args.db.slice(args.function, bc_name, var_args["slice-id"])
            if slice:
                pp.pprint(slice)
            else:
                print("Slice does not exist")
        else:
            print(f"Unknown bc {input_bc_file}")


class NumTracesQuery(QueryExecutor):
    def setup_parser(parser):
        parser.add_argument('-p', '--package', type=str, help='Only the traces in a package')
        parser.add_argument('-b', '--bc', type=str, help='Only the traces in a bc-file')
        parser.add_argument('-f', '--function', type=str, help='Only the traces around a function')

    def execute(args):
        db = args.db
        count = 0
        if args.package:
            for bc_name in db.bc_files(package = args.package, full = False):
                n = db.num_traces(bc = bc_name, func_name = args.function)
                count += n
        else:
            n = db.num_traces(bc = args.bc, func_name = args.function)
            count += n
        print(count)


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
        fn = args.function
        slice_id = var_args["slice-id"]
        trace_id = var_args["trace-id"]
        if bc_name:
            dugraph = args.db.dugraph(fn, bc_name, slice_id, trace_id)
            if dugraph:
                pp.pprint(dugraph)
            else:
                print("DUGraph does not exist")
        else:
            print(f"Unknown bc {input_bc_file}")


class FeatureQuery(QueryExecutor):
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
        fn = args.function
        slice_id = var_args["slice-id"]
        trace_id = var_args["trace-id"]
        if bc_name:
            feature = args.db.feature(fn, bc_name, slice_id, trace_id)
            if feature:
                pp.pprint(feature)
            else:
                print("Feature does not exist")
        else:
            print(f"Unknown bc {input_bc_file}")


query_executors = {
    'packages': PackagesQuery,
    'bc-files': BCFilesQuery,
    'occurrence': OccurrenceQuery,
    'num-slices': NumSlicesQuery,
    'slice': SliceQuery,
    'num-traces': NumTracesQuery,
    'dugraph': DUGraphQuery,
    'feature': FeatureQuery
}


def setup_parser(parser):
    subparsers = parser.add_subparsers(dest="query")
    for key, executor in query_executors.items():
        query_parser = subparsers.add_parser(key)
        executor.setup_parser(query_parser)


def main(args):
    if args.query in query_executors:
        query_executors[args.query].execute(args)
    else:
        print(f"Unknown query {args.query}")
