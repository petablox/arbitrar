def setup_parser(parser):
    subparsers = parser.add_subparsers(dest="db_cmd")

    _ = subparsers.add_parser("bc-files")
    # TODO: Add --package argument

def print_bc_files(args):
    bc_files = args.db.bc_files()
    print(f"{len(bc_files)} bc-files in total:")
    for bc_file in bc_files:
        print(bc_file)

def main(args):
    if args.db_cmd == 'bc-files':
        print_bc_files(args)