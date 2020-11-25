from ..meta import Executor
import shutil


class RemoveAction(Executor):
  @staticmethod
  def setup_parser(parser):
    parser.add_argument('function', type=str, help="The function that the trace is about")

  @staticmethod
  def execute(args):
    db = args.db
    shutil.rmtree(db.func_slices_dir(args.function))
    shutil.rmtree(db.func_traces_dir(args.function))
    shutil.rmtree(db.func_features_dir(args.function))
