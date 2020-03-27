def setup_parser(parser):
    subparsers = parser.add_subparsers(dest="db_cmd")

    _ = subparsers.add_parser("bc-files")
    # TODO: Add --package argument

    num_slices_parser = subparsers.add_parser("num-slices")
    num_slices_parser.add_argument('-p', '--package', type=str, help='Only the slices in a package')
    num_slices_parser.add_argument('-b', '--bc', type=str, help='Only the slices in a bc-file')
    num_slices_parser.add_argument('-f', '--function', type=str, help='Only the slices around a function')

    slice_parser = subparsers.add_parser("slice")
    slice_parser.add_argument('bc-file', type=str, help='The bc-file that the slice belongs to')
    slice_parser.add_argument('function', type=str, help='The function that the slice contain')
    slice_parser.add_argument('slice-id', type=int, help='The slice id')

    num_traces_parser = subparsers.add_parser("num-traces")
    num_traces_parser.add_argument('-p', '--package', type=str, help='Only the traces in a package')
    num_traces_parser.add_argument('-b', '--bc', type=str, help='Only the traces in a bc-file')
    num_traces_parser.add_argument('-f', '--function', type=str, help='Only the traces around a function')

    trace_parser = subparsers.add_parser("trace")
    trace_parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to")
    trace_parser.add_argument('function', type=str, help="The function that the trace is about")
    trace_parser.add_argument('slice-id', type=int, help='The slice id')
    trace_parser.add_argument('trace-id', type=int, help='The trace id')

    feature_parser = subparsers.add_parser("feature")
    feature_parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to")
    feature_parser.add_argument('function', type=str, help="The function that the trace is about")
    feature_parser.add_argument('slice-id', type=int, help='The slice id')
    feature_parser.add_argument('trace-id', type=int, help='The trace id')


def print_bc_files(args):
    bc_files = args.db.bc_files()
    print(f"{len(bc_files)} bc-files in total:")
    for bc_file in bc_files:
        print(bc_file)


def print_num_slices(args):
    raise Exception("Not implemented")


def print_slice(args):
    raise Exception("Not implemented")


def print_num_traces(args):
    raise Exception("Not implemented")


def print_trace(args):
    raise Exception("Not implemented")


def print_feature(args):
    raise Exception("Not implemented")

actions = {
    'bc-files': print_bc_files,
    'num-slices': print_num_slices,
    'slice': print_slice,
    'num-traces': print_num_traces,
    'trace': print_trace,
    'feature': print_feature
}

def main(args):
    actions[args.db_cmd](args)
