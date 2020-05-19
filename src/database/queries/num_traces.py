from ..meta import Executor


def num_traces_with_filter(db, package, bc, function, slice_id, filter):
  count = 0
  f = eval(filter)
  bc_files = list(db.bc_files(package=package, full=False)) if package else [db.find_bc_name(bc)] if bc else None
  for dp in db.function_datapoints(function):
    if bc_files == None or dp.bc in bc_files:
      if slice_id == None or dp.slice_id == slice_id:
        if f(dp):
          count += 1
  print(count)


def num_traces(db, package, bc, function, slice_id):
  count = 0
  if package:
    for bc_name in db.bc_files(package=package, full=False):
      n = db.num_traces(bc=bc_name, func_name=function)
      count += n
  else:
    bc = db.find_bc_name(bc) if bc else None
    if slice_id and function and bc:
      count += db.num_traces_of_slice(function, bc, slice_id)
    else:
      n = db.num_traces(bc=bc, func_name=function)
      count += n
  print(count)


class NumTracesQuery(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('-p', '--package', type=str, help='Only the traces in a package')
    parser.add_argument('-b', '--bc', type=str, help='Only the traces in a bc-file')
    parser.add_argument('-f', '--function', type=str, help='Only the traces around a function')
    parser.add_argument('--slice-id', type=int)
    parser.add_argument('--filter', type=str)

  @staticmethod
  def execute(args):
    db = args.db
    if args.filter:
      num_traces_with_filter(db, args.package, args.bc, args.function, args.slice_id, args.filter)
    else:
      num_traces(db, args.package, args.bc, args.function, args.slice_id)
