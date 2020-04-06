import pprint
pp = pprint.PrettyPrinter(indent=4)

class QueryExecutor:
    def setup_parser(parser):
        pass

    def execute(args):
        pass


class PackagesQuery(QueryExecutor):
    def execute(args):
        db = args.db
        print("Name\tFetch Status\tBuild Status")
        for package in db.packages:
            f = "fetched" if package.fetched else "not fetched"
            b = package.build.result.value
            print(f"{package.name}\t{f}\t\t{b}")


class BCFilesQuery(QueryExecutor):
    def setup_parser(parser):
        parser.add_argument('-p', '--package', type=str, help="Only the bc files in a package")

    def execute(args):
        bc_files = args.db.bc_files(package = args.package)
        for bc_file in bc_files:
            print(bc_file)


class NumSlicesQuery(QueryExecutor):
    def setup_parser(parser):
        parser.add_argument('-p', '--package', type=str, help='Only the slices in a package')
        parser.add_argument('-b', '--bc', type=str, help='Only the slices in a bc-file')
        parser.add_argument('-f', '--function', type=str, help='Only the slices around a function')

    def execute(args):
        db = args.db
        print(db.num_slices(func_name = args.function, bc = bc_name))


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
                pp.pprint(args.db.slice(args.function, bc_name, var_args["slice-id"]))
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
        raise Exception("Not implemented")


class TraceQuery(QueryExecutor):
    def setup_parser(parser):
        parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to")
        parser.add_argument('function', type=str, help="The function that the trace is about")
        parser.add_argument('slice-id', type=int, help='The slice id')
        parser.add_argument('trace-id', type=int, help='The trace id')

    def execute(args):
        raise Exception("Not implemented")


class FeatureQuery(QueryExecutor):
    def setup_parser(parser):
        parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to")
        parser.add_argument('function', type=str, help="The function that the trace is about")
        parser.add_argument('slice-id', type=int, help='The slice id')
        parser.add_argument('trace-id', type=int, help='The trace id')

    def execute(args):
        raise Exception("Not implemented")


query_executors = {
    'packages': PackagesQuery,
    'bc-files': BCFilesQuery,
    'num-slices': NumSlicesQuery,
    'slice': SliceQuery,
    'num-traces': NumTracesQuery,
    'trace': TraceQuery,
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
