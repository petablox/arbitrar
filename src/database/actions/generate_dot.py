from ..meta import Executor
import pygraphviz as pgv


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
  if "predicate" in vertex and vertex["predicate"]:
    ret += vertex["predicate"] + " "
  if "cond" in vertex and vertex["cond"]:
    ret += vertex["cond"] + " "

  # All ops
  for i in range(10):
    key = f"op{i}"
    if key in vertex and vertex[key]:
      ret += vertex[key] + " "
  return ret


def dot_of_dugraph(dugraph):
  g = pgv.AGraph()

  # First insert all the vertices
  g.node_attr["shape"] = "box"
  g.node_attr["style"] = "filled"
  g.node_attr["fillcolor"] = "white"
  for v in dugraph["vertex"]:
    loc = v["location"]
    id = str(v["id"])
    label = f"[{loc}]\n{instr_str(v)}"
    if v["id"] == dugraph["target"]:
      g.add_node(id, label=label, fontcolor="white", fillcolor="blue")
    else:
      g.add_node(id, label=label)

  # Then insert all the cf_edges
  g.edge_attr["arrowhead"] = "vee"
  g.edge_attr["color"] = "black"
  for cfe in dugraph["cf_edge"]:
    g.add_edge(str(cfe[0]), str(cfe[1]))

  # Finally insert all the du_edges
  g.edge_attr["color"] = "red"
  for due in dugraph["du_edge"]:
    g.add_edge(str(due[0]), str(due[1]))

  return g


class GenerateDotAction(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('function', type=str, help="The function that the trace is about")
    parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to", nargs="?")
    parser.add_argument('slice-id', type=int, help='The slice id', nargs="?")
    parser.add_argument('trace-id', type=int, help='The trace id', nargs="?")

  @staticmethod
  def get_to_process_traces(db, var_args):
    to_process = []

    fn = var_args["function"]

    if var_args["bc-file"]:

      # Get all the data from command line input
      input_bc_file = var_args["bc-file"]
      bc_name = db.find_bc_name(input_bc_file)
      bc = bc_name if bc_name else input_bc_file

      if var_args["slice-id"]:
        slice_id = var_args["slice-id"]

        # Check if we need to generate multiple dots
        if var_args["trace-id"]:
          to_process = [(fn, bc, slice_id, var_args["trace-id"])]
        else:
          to_process = [(fn, bc, slice_id, trace_id) for trace_id in range(db.num_traces_of_slice(fn, bc, slice_id))]

      else:

        num_slices = db.num_slices(func_name=fn, bc=bc)
        for slice_id in range(num_slices):
          to_process += [(fn, bc, slice_id, trace_id) for trace_id in range(db.num_traces_of_slice(fn, bc, slice_id))]

    else:

      for bc in db.bc_files(full=False):
        num_slices = db.num_slices(func_name=fn, bc=bc)
        for slice_id in range(num_slices):
          to_process += [(fn, bc, slice_id, trace_id) for trace_id in range(db.num_traces_of_slice(fn, bc, slice_id))]

    return to_process

  @staticmethod
  def execute(args):
    db = args.db

    to_process = GenerateDotAction.get_to_process_traces(db, vars(args))

    # For each trace_id we generate dot graph
    for (fn, bc, slice_id, trace_id) in to_process:

      # Get the dugraph
      dugraph = db.dugraph(fn, bc, slice_id, trace_id)

      # Generate dot file
      g = dot_of_dugraph(dugraph)

      # Save the file
      save_dir = db.func_bc_slice_dots_dir(fn, bc, slice_id, create=True)
      g.write(f"{save_dir}/{trace_id}.dot")
