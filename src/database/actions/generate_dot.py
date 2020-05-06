from ..meta import Executor
from graphviz import Digraph


def instr_str(vertex):
  ret = ""
  if "result" in vertex and vertex["result"]:
    ret += vertex["result"] + " = "
  ret += vertex["opcode"] + " "

  # Deal with function and its arguments
  if "func" in vertex:
    ret += vertex["func"] + "("
    if "args" in vertex:
      for arg in vertex["args"]:
        ret += arg + ", "
      ret = ret[0:len(ret) - 2]
    ret += ")"

  # Deal with icmp
  if "predicate" in vertex:
    ret += vertex["predicate"] + " "
  if "cond" in vertex:
    ret += vertex["cond"] + " "
  for i in range(10):
    key = f"op{i}"
    if key in vertex:
      ret += vertex[key] + " "
  return ret


def dot_of_dugraph(dugraph):
  dot = Digraph()

  # First insert all the vertices
  dot.attr('node', shape='box', style='filled', fillcolor="white")
  for v in dugraph["vertex"]:
    loc = v["location"]
    id = str(v["id"])
    label = f"[{loc}]\n{instr_str(v)}"
    if v["id"] == dugraph["target"]:
      dot.node(id, label=label, fontcolor="white", fillcolor="blue")
    else:
      dot.node(id, label=label)

  # Then insert all the cf_edges
  for cfe in dugraph["cf_edge"]:
    dot.edge(str(cfe[0]), str(cfe[1]))

  # Finally insert all the du_edges
  dot.attr('edge', color='red')
  for due in dugraph["du_edge"]:
    dot.edge(str(due[0]), str(due[1]))

  return dot


class GenerateDotAction(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('function', type=str, help="The function that the trace is about")
    parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to")
    parser.add_argument('slice-id', type=int, help='The slice id')
    parser.add_argument('trace-id', type=int, help='The trace id', nargs="?")

  @staticmethod
  def execute(args):
    db = args.db
    var_args = vars(args)

    # Get all the data from command line input
    input_bc_file = var_args["bc-file"]
    bc_name = args.db.find_bc_name(input_bc_file)
    bc = bc_name if bc_name else input_bc_file

    fn = args.function
    slice_id = var_args["slice-id"]

    # Check if we need to generate multiple dots
    if "trace-id" in var_args and var_args["trace-id"]:
      trace_ids = [var_args["trace-id"]]
    else:
      trace_ids = range(args.db.num_traces_of_slice(fn, bc, slice_id))

    # For each trace_id we generate dot graph
    for trace_id in trace_ids:

      # Get the dugraph
      dugraph = args.db.dugraph(fn, bc, slice_id, trace_id)

      # Generate dot file
      dot = dot_of_dugraph(dugraph)

      # Save the file
      save_dir = args.db.func_bc_slice_dots_dir(fn, bc, slice_id, create=True)
      dot.save(filename=f"{trace_id}.dot", directory=save_dir)
