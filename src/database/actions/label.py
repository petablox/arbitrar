from ..meta import Executor
import json


class LabelAction(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('label', type=str, help="The label that you want to label")
    parser.add_argument('function', type=str, help="The function that the trace is about")
    parser.add_argument('bc-file', type=str, help="The bc-file that the trace belong to", nargs="?")
    parser.add_argument('slice-id', type=int, help='The slice id', nargs="?")
    parser.add_argument('trace-id', type=int, help='The trace id', nargs="?")
    parser.add_argument('-e', '--erase', action="store_true", help='Erase the given label')
    parser.add_argument('--filter', type=str)

  @staticmethod
  def execute(args):
    db = args.db
    var_args = vars(args)

    # Get all the data from command line input
    input_bc_file = var_args["bc-file"]
    bc_name = db.find_bc_name(input_bc_file)
    bc = bc_name if bc_name else input_bc_file

    # Get function and slice information
    fn = args.function

    # Slice id
    slice_id = var_args["slice-id"]

    # Check if we need to generate multiple dots
    if "trace-id" in var_args and var_args["trace-id"]:
      trace_ids = [var_args["trace-id"]]
    else:
      trace_ids = range(db.num_traces_of_slice(fn, bc, slice_id))

    # For each trace_id we label
    for trace_id in trace_ids:

      # Get the trace
      trace = db.trace(fn, bc, slice_id, trace_id)

      # Check if erase
      if args.erase:

        # Erase a label if presented
        if "labels" in trace and args.label in trace["labels"]:
          labels = set(trace["labels"])
          labels.discard(args.label)
          trace["labels"] = list(labels)

      # Add new label
      else:
        # Get its labels
        if "labels" in trace:

          # Check if it already contains the label
          if not args.label in trace["labels"]:

            # If not, add the label and save the file
            trace["labels"].append(args.label)

        else:
          trace["labels"] = [args.label]

      # Dump the updated file
      with open(db.trace_dir(fn, bc, slice_id, trace_id), 'w') as f:
        json.dump(trace, f)
